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
    YTDLP_PROXY="--proxy $SELECTED_PROXY"
    CURL_PROXY="-x $SELECTED_PROXY"
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
                left)   CROP_FILTER="crop=iw*0.5:ih:0:0" ;;
                center) CROP_FILTER="crop=iw*0.5:ih:iw*0.25:0" ;;
                right)  CROP_FILTER="crop=iw*0.5:ih:iw*0.5:0" ;;
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
        if ! ffmpeg -y -hide_banner -loglevel error $SEEK_ARGS -i "$INPUT" -ar 16000 -ac 1 -c:a pcm_s16le "$TEMP_AUDIO"; then
            echo "[ERROR] Failed to extract audio"
            exit 1
        fi

        # Get full JSON with word-level timestamps
        JSON_FILE="$SRT_BASE.json"
        whisper-cli -m "$MODEL_PATH" -f "$TEMP_AUDIO" -osrt -ojf -of "$SRT_BASE" -np > /dev/null 2>&1

        # Generate ASS subtitle
        if [ -f "$JSON_FILE" ]; then
            python3 "$SCRIPT_DIR/subtitle_generator.py" "$JSON_FILE" "$ASS_FILE"

            rm -f "$JSON_FILE"
            if [ -f "$ASS_FILE" ]; then
                SUBTITLE_FILTER="subtitles='$ASS_FILE':force_style='Fontname=DejaVuSans-Bold,Fontsize=80,PrimaryColour=&H00FFFF00'"
            fi
        else
            echo "[WARN] JSON file not created"
        fi
    fi
fi

# Build video filters array
VF_FILTERS=()
[ -n "$CROP_FILTER" ] && VF_FILTERS+=("$CROP_FILTER")
VF_FILTERS+=("scale=1080:1920:force_original_aspect_ratio=decrease,pad=1080:1920:(ow-iw)/2:(oh-ih)/2:color=black")
VF_FILTERS+=("drawtext=text='$WATERMARK':fontcolor=white@0.5:fontsize=48:x=(w-tw)/2:y=(h-th)/2:fontfile='$FONT_PATH'")
[ -n "$SUBTITLE_FILTER" ] && VF_FILTERS+=("$SUBTITLE_FILTER")

echo "[INFO] Generating video..."

IFS=',' eval 'VF_ARG="${VF_FILTERS[*]}"'
ffmpeg -y -hide_banner -loglevel error $SEEK_ARGS -i "$INPUT" \
    -vf "$VF_ARG" \
    -c:v libx264 -preset faster -crf 23 -pix_fmt yuv420p \
    -c:a aac -b:a 128k "$FULL_OUTPUT_PATH"

if [ $? -eq 0 ]; then
    echo "[INFO] Successfully generated: $OUTPUT_FILE"
    # send_telegram "$FULL_OUTPUT_PATH"
else
    echo "[ERROR] Failed to generate clip"
fi
