#!/usr/bin/env bash

# Resolve absolute paths
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
RESULT_DIR="$SCRIPT_DIR/result"
FONT_PATH="$SCRIPT_DIR/public/font/Coolvetica.ttf"
MODEL_PATH="$HOME/.cache/whisper-models/ggml-medium.bin"

mkdir -p "$RESULT_DIR"

if [ -f "$SCRIPT_DIR/.env" ]; then
    source "$SCRIPT_DIR/.env"
fi

YTDLP_PROXY=""
CURL_PROXY=""
if [ -n "$PROXIES" ]; then
    # Pick random if has multi proxy
    IFS=',' read -ra PROXY_ARRAY <<< "$PROXIES"
    RANDOM_INDEX=$((RANDOM % ${#PROXY_ARRAY[@]}))
    SELECTED_PROXY="${PROXY_ARRAY[$RANDOM_INDEX]}"
    YTDLP_PROXY="--proxy \"$SELECTED_PROXY\""
    CURL_PROXY="-x \"$SELECTED_PROXY\""
fi

# Variables
INPUT=""
INPUT_IS_URL=false
START=""
END=""
SEEK_ARGS=""
CROP_FILTER=""
WATERMARK="obrolan_clip"
USE_SUBTITLES=false

# Argument Parsing
while [[ $# -gt 0 ]]; do
    case $1 in
        --clip)
            read -r START END <<< "$2"
            SEEK_ARGS="-ss $START -to $END"
            shift 2
            ;;
        --crop)
            case $2 in
                left)   CROP_FILTER="crop=iw*0.5:ih:0:0," ;;
                center) CROP_FILTER="crop=iw*0.5:ih:iw*0.25:0," ;;
                right)  CROP_FILTER="crop=iw*0.5:ih:iw*0.5:0," ;;
            esac
            shift 2
            ;;
        --subtitle)
            USE_SUBTITLES=true
            shift 1
            ;;
        --watermark)
            WATERMARK="$2"
            shift 2
            ;;
        *)
            INPUT="$1"
            shift 1
            ;;
    esac
done

send_telegram() {
    local video_path="$1"
    if [ -z "$TELEGRAM_TOKEN" ] || [ -z "$TELEGRAM_CHAT_ID" ]; then
        return 1
    fi
    curl -fsSL -X POST "https://api.telegram.org/bot$TELEGRAM_TOKEN/sendVideo" -F chat_id="$TELEGRAM_CHAT_ID" -F video="@$video_path" > /dev/null 2>&1
}

# URL Detection
if [[ "$INPUT" =~ ^https?:// ]]; then
    INPUT_IS_URL=true
elif [[ -z "$INPUT" || ! -f "$INPUT" ]]; then
    echo "[ERROR] Valid input file or URL required."
    exit 1
else
    INPUT=$(realpath "$INPUT")
fi

# Download URL to temp file if needed
if [ "$INPUT_IS_URL" = true ]; then
    TEMP_INPUT="$RESULT_DIR/tmp_input_$(date +%s).mp4"
    if [[ "$INPUT" =~ youtube\.com|youtu\.be ]]; then
        if ! command -v yt-dlp &> /dev/null; then
            echo "[ERROR] yt-dlp not found. Install: yt-dlp"
            exit 1
        fi
        # Use download-sections to get only the clip range
        YTDLP_RANGE=""
        if [ -n "$START" ] && [ -n "$END" ]; then
            YTDLP_RANGE="--download-sections *${START}-${END}"
            SEEK_ARGS=""
        fi
        echo "[INFO] Downloading video..."
        yt-dlp --no-progress -q -f "bestvideo[height<=1080][ext=mp4]+bestaudio[ext=m4a]/best[height<=1080][ext=mp4]/best" $YTDLP_RANGE $YTDLP_PROXY -o "$TEMP_INPUT" "$INPUT" || {
            echo "[ERROR] Failed to download YouTube video"
            exit 1
        }
    else
        echo "[INFO] Downloading input..."
        curl -fsSL $CURL_PROXY -o "$TEMP_INPUT" "$INPUT" || {
            echo "[ERROR] Failed to download URL"
            exit 1
        }
    fi
    INPUT="$TEMP_INPUT"
    RAW_FILENAME="${INPUT##*/}"
else
    RAW_FILENAME=$(basename "$INPUT")
fi

# Naming Logic
CLEAN_FILENAME="${RAW_FILENAME// /-}"
OUTPUT_FILE="clip-$CLEAN_FILENAME"
FULL_OUTPUT_PATH="$RESULT_DIR/$OUTPUT_FILE"
TEMP_AUDIO="$RESULT_DIR/tmp_audio.wav"
SRT_BASE="$RESULT_DIR/tmp_subs"
SRT_FILE="$SRT_BASE.srt"
ASS_FILE="$SRT_BASE.ass"

# Cleanup temp files on exit
cleanup() {
    [[ -f "$TEMP_INPUT" ]] && rm "$TEMP_INPUT"
    [[ -f "$TEMP_AUDIO" ]] && rm "$TEMP_AUDIO"
    [[ -f "$SRT_FILE" ]] && rm "$SRT_FILE"
    [[ -f "$ASS_FILE" ]] && rm "$ASS_FILE"
    [[ -f "$SRT_BASE.json" ]] && rm "$SRT_BASE.json"
}
trap cleanup EXIT

# Transcription Logic
SUBTITLE_FILTER=""
if [ "$USE_SUBTITLES" = true ]; then
    if ! command -v whisper-cli &> /dev/null; then
        echo "[WARN] whisper-cpp not found. Skipping subtitles."
    elif [ ! -f "$MODEL_PATH" ]; then
        echo "[WARN] GGML model not found at $MODEL_PATH. Skipping subtitles."
    else
        echo "[INFO] Extracting audio and Transcribing..."
        ffmpeg -y -hide_banner -loglevel error $SEEK_ARGS -i "$INPUT" -ar 16000 -ac 1 -c:a pcm_s16le "$TEMP_AUDIO"
        
        # Get full JSON with word-level timestamps
        JSON_FILE="$SRT_BASE.json"
        whisper-cli -m "$MODEL_PATH" -f "$TEMP_AUDIO" -osrt -ojf -of "$SRT_BASE" -np > /dev/null 2>&1

        # Generate ASS subtitle with word-by-word highlighting (TikTok style)
        if [ -f "$JSON_FILE" ]; then
            python3 - "$JSON_FILE" "$ASS_FILE" << 'PYEOF'
import sys
import json

def format_ts(sec):
    h = int(sec // 3600)
    m = int((sec % 3600) // 60)
    s = sec % 60
    return f"{h}:{m:02d}:{s:05.2f}"

with open(sys.argv[1], 'r', encoding='utf-8') as f:
    data = json.load(f)

# Write ASS header
ass_header = """[Script Info]
Title: TikTok Style Subtitles
ScriptType: v4.00+
Collisions: Normal
PlayResX: 1080
PlayResY: 1920
PlayDepth: 0
Timer: 100.0.0

[V4+ Styles]
Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
Style: Default,DejaVuSans-Bold,80,&H00FFFF00,&H000000FF,&H00000000,&H00000000,-1,0,0,0,100,100,0,0,1,2,0,5,10,10,-960,1

[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
"""

with open(sys.argv[2], 'w', encoding='utf-8') as f:
    f.write(ass_header)

    # Process each segment with word-level timing
    for segment in data.get('transcription', []):
        tokens = segment.get('tokens', [])
        
        # Extract actual words from tokens (filter out special tokens)
        words = []
        for token in tokens:
            text = token.get('text', '').strip()
            # Skip special tokens
            if text and not text.startswith('[') and text not in ['', '(', ')', ',', '.', '!', '?', '-']:
                offset_from = token.get('offsets', {}).get('from', 0) / 1000.0
                offset_to = token.get('offsets', {}).get('to', 0) / 1000.0
                words.append({'word': text, 't0': offset_from, 't1': offset_to})
        
        if not words:
            # Fallback: use segment-level timing
            offset_from = segment.get('offsets', {}).get('from', 0) / 1000.0
            offset_to = segment.get('offsets', {}).get('to', 0) / 1000.0
            text = segment.get('text', '').replace(',', '\\,')
            f.write(f"Dialogue: 0,{format_ts(offset_from)},{format_ts(offset_to)},Default,,0,0,0,,{text}\n")
            continue

        # Group words into lines (roughly 5-6 words per line for readability)
        lines = []
        current_line = []
        for w in words:
            current_line.append(w)
            if len(current_line) >= 6:
                lines.append(current_line)
                current_line = []
        if current_line:
            lines.append(current_line)

        # Generate dialogue for each line
        for line_idx, line_words in enumerate(lines):
            if not line_words:
                continue

            line_start = line_words[0].get('t0', 0)
            line_end = line_words[-1].get('t1', 0)
            
            # Create word-by-word highlights for this line
            for i, word_data in enumerate(line_words):
                word_start = word_data.get('t0', line_start)
                word_end = word_data.get('t1', line_end)
                word_text = word_data.get('word', '').strip()
                
                if not word_text:
                    continue

                # Highlight: spoken words yellow, upcoming words gray
                spoken = line_words[:i+1]
                upcoming = line_words[i+1:]
                
                # Build colored text: highlighted (yellow) + faded (gray)
                if spoken and upcoming:
                    text_with_highlight = f"{{\\1c&H00FFFF&}}{' '.join([w.get('word','').strip() for w in spoken])} {{\\1c&H888888&}}{' '.join([w.get('word','').strip() for w in upcoming])}"
                elif spoken:
                    text_with_highlight = f"{{\\1c&H00FFFF&}}{' '.join([w.get('word','').strip() for w in spoken])}"
                else:
                    text_with_highlight = f"{{\\1c&H888888&}}{' '.join([w.get('word','').strip() for w in upcoming])}"

                text_with_highlight = text_with_highlight.replace(',', '\\,')
                
                # Only show one text at a time - each word's time range is its own
                f.write(f"Dialogue: 0,{format_ts(word_start)},{format_ts(word_end)},Default,,0,0,0,,{text_with_highlight}\n")
PYEOF
            
            rm -f "$JSON_FILE"
            if [ -f "$ASS_FILE" ]; then
                SUBTITLE_FILTER="subtitles='$ASS_FILE':force_style='Fontname=DejaVuSans-Bold,Fontsize=80,PrimaryColour=&H00FFFF00',"
            fi
        else
            echo "[WARN] JSON file not created"
        fi
    fi
fi

echo "[INFO] Generating video..."

ffmpeg -y -hide_banner -loglevel error $SEEK_ARGS -i "$INPUT" \
    -vf "${CROP_FILTER}scale=1080:1920:force_original_aspect_ratio=decrease,pad=1080:1920:(ow-iw)/2:(oh-ih)/2:color=black,drawtext=text='$WATERMARK':fontcolor=white@0.5:fontsize=48:x=(w-tw)/2:y=(h-th)/2:fontfile='$FONT_PATH',${SUBTITLE_FILTER}" \
    -c:v libx264 -preset faster -crf 23 -pix_fmt yuv420p \
    -c:a aac -b:a 128k "$FULL_OUTPUT_PATH"

if [ $? -eq 0 ]; then
    echo "[INFO] Successfully generated: $OUTPUT_FILE"
    # send_telegram "$FULL_OUTPUT_PATH"
else
    echo "[ERROR] Failed to generate clip"
fi
