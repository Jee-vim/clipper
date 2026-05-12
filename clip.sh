#!/usr/bin/env bash

# Resolve absolute paths
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
RESULT_DIR="$SCRIPT_DIR/result"
FONT_PATH="$SCRIPT_DIR/public/font/coolvetica.ttf"
MODEL_PATH="$HOME/.cache/whisper-models/ggml-medium.bin"

mkdir -p "$RESULT_DIR"

if [ -f "$SCRIPT_DIR/.env" ]; then
    source "$SCRIPT_DIR/.env"
fi

get_random_proxy() {
    if [ -z "$PROXIES" ]; then
        return 0
    fi
    IFS=',' read -ra PROXY_ARRAY <<< "$PROXIES"
    RANDOM_INDEX=$((RANDOM % ${#PROXY_ARRAY[@]}))
    echo "${PROXY_ARRAY[$RANDOM_INDEX]}"
}

validate_time() {
    local time=$1
    if [[ "$time" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
        return 0
    elif [[ "$time" =~ ^[0-9]{1,2}:[0-9]{1,2}$ ]]; then
        return 0
    elif [[ "$time" =~ ^[0-9]{1,2}:[0-9]{1,2}:[0-9]{1,2}(\.[0-9]+)?$ ]]; then
        return 0
    else
        echo "[ERROR] Invalid time format: $time. Use seconds (e.g., 30) or HH:MM:SS (e.g., 05:58)"
        exit 1
    fi
}

# Variables
INPUT=""
INPUT_IS_URL=false
START=""
END=""
SEEK_ARGS=""
CROP_FILTER=""
WATERMARK="obrolan_clip"
USE_SUBTITLES=false
BG=""

# Argument Parsing
while [[ $# -gt 0 ]]; do
    case $1 in
        --clip)
            read -r START END <<< "$2"
            validate_time "$START"
            validate_time "$END"
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
        --bg)
            BG="$2"
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
            # Only use --download-sections if yt-dlp supports it
            if yt-dlp --help 2>&1 | grep -q "download-sections"; then
                YTDLP_RANGE="--download-sections *${START}-${END}"
                SEEK_ARGS=""
            fi
            # If unsupported, keep SEEK_ARGS for ffmpeg to clip
        fi
        echo "[INFO] Downloading video..."
        PROXY=$(get_random_proxy)
        YTDLP_PROXY_ARG=""
        if [ -n "$PROXY" ]; then
            YTDLP_PROXY_ARG="--proxy $PROXY"
        fi
        yt-dlp --no-progress -q -f "bestvideo[height<=1080][ext=mp4]+bestaudio[ext=m4a]/best[height<=1080][ext=mp4]/best" $YTDLP_RANGE $YTDLP_PROXY_ARG -o "$TEMP_INPUT" "$INPUT" || {
            echo "[ERROR] Failed to download YouTube video"
            exit 1
        }
    else
        echo "[INFO] Downloading input..."
        PROXY=$(get_random_proxy)
        CURL_PROXY_ARG=""
        if [ -n "$PROXY" ]; then
            CURL_PROXY_ARG="-x $PROXY"
        fi
        curl -fsSL $CURL_PROXY_ARG -o "$TEMP_INPUT" "$INPUT" || {
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
        WHISPER_LOG="$SCRIPT_DIR/whisper.log"
        if ! whisper-cli -m "$MODEL_PATH" -f "$TEMP_AUDIO" -osrt -ojf -of "$SRT_BASE" -np > "$WHISPER_LOG" 2>&1; then
            echo "[WARN] Whisper transcription failed, check $WHISPER_LOG"
        else
            rm -f "$WHISPER_LOG"
        fi

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

echo "[INFO] Generating video..."

if [ -n "$BG" ]; then
    # Use media as background instead of solid black
    BG=$(realpath "$BG")
    echo "[INFO] Using background: $BG"

    # Detect if bg is video (needs loop) or image (single frame)
    BG_LOOP=""
    OVERLAY_SHORTEST=""
    case "${BG,,}" in
        *.mp4|*.mov|*.avi|*.mkv|*.webm|*.m4v)
            BG_LOOP="-stream_loop -1"
            OVERLAY_SHORTEST=":shortest=1"
            echo "[INFO] Background is video — looping enabled"
            ;;
    esac

    # Video processing: crop (optional) + scale to fit
    VIDEO_CHAIN="[0:v]"
    [ -n "$CROP_FILTER" ] && VIDEO_CHAIN+="$CROP_FILTER,"
    VIDEO_CHAIN+="scale=1080:1920:force_original_aspect_ratio=decrease[fg]"

    # Background: scale to fill frame (cover mode for horizontal→vertical)
    BG_CHAIN="[1:v]scale=1080:1920:force_original_aspect_ratio=increase,crop=1080:1920[bg]"

    # Overlay + text + subtitles
    POST_CHAIN="[bg][fg]overlay=(W-w)/2:(H-h)/2$OVERLAY_SHORTEST"
    POST_CHAIN+=",drawtext=text='$WATERMARK':fontcolor=white@0.5:fontsize=48:x=(w-tw)/2:y=(h-th)/2:fontfile='$FONT_PATH'"
    [ -n "$SUBTITLE_FILTER" ] && POST_CHAIN+=",$SUBTITLE_FILTER"
    POST_CHAIN+="[vout]"

    ffmpeg -y -hide_banner -loglevel error $SEEK_ARGS -i "$INPUT" $BG_LOOP -i "$BG" \
        -filter_complex "$VIDEO_CHAIN;$BG_CHAIN;$POST_CHAIN" \
        -map '[vout]' -map 0:a? -c:a aac -b:a 128k \
        -c:v libx264 -preset faster -crf 23 -pix_fmt yuv420p \
        "$FULL_OUTPUT_PATH"
else
    # Original: black background via pad
    VF_FILTERS=()
    [ -n "$CROP_FILTER" ] && VF_FILTERS+=("$CROP_FILTER")
    VF_FILTERS+=("scale=1080:1920:force_original_aspect_ratio=decrease,pad=1080:1920:(ow-iw)/2:(oh-ih)/2:color=black")
    VF_FILTERS+=("drawtext=text='$WATERMARK':fontcolor=white@0.5:fontsize=48:x=(w-tw)/2:y=(h-th)/2:fontfile='$FONT_PATH'")
    [ -n "$SUBTITLE_FILTER" ] && VF_FILTERS+=("$SUBTITLE_FILTER")

    printf -v VF_ARG '%s,' "${VF_FILTERS[@]}"
    VF_ARG="${VF_ARG%,}"
    ffmpeg -y -hide_banner -loglevel error $SEEK_ARGS -i "$INPUT" \
        -vf "$VF_ARG" \
        -c:v libx264 -preset faster -crf 23 -pix_fmt yuv420p \
        -c:a aac -b:a 128k \
        "$FULL_OUTPUT_PATH"
fi

if [ $? -eq 0 ]; then
    echo "[INFO] Successfully generated: $OUTPUT_FILE"
    if send_telegram "$FULL_OUTPUT_PATH"; then
        echo "[INFO] Sent to Telegram"
    else
        echo "[WARN] Failed to send to Telegram"
    fi
else
    echo "[ERROR] Failed to generate clip"
fi
