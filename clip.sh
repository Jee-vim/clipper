#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
OUTPUT_DIR="$SCRIPT_DIR/output"
TMP_DIR="$SCRIPT_DIR/tmp"
FONT_PATH="$SCRIPT_DIR/public/font/coolvetica.ttf"
MODEL_PATH="$HOME/.cache/whisper-models/ggml-medium.bin"

mkdir -p "$OUTPUT_DIR" "$TMP_DIR"

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

INPUT=""
INPUT_IS_URL=false
START=""
END=""
SEEK_ARGS=""
CROP_FILTER=""
WATERMARK="obrolan_clip"
USE_SUBTITLES=false
CUSTOM_TITLE=""
BG=""
TEMP_INPUT=""
PROXIES=""
TELEGRAM_TOKEN=""
TELEGRAM_CHAT_ID=""

# Dynamic naming flags
CROP_NAME=""
CLIP_NAME=""
HARDSUB_NAME=""
WM_NAME=""
BG_NAME=""

if [ -f "$SCRIPT_DIR/.env" ]; then
    source "$SCRIPT_DIR/.env"
fi

while [[ $# -gt 0 ]]; do
    case $1 in
         --clip)
            read -r START END <<< "$2"
            validate_time "$START"
            validate_time "$END"
            
            format_seconds() {
                local sec=$1
                if [[ "$sec" =~ ^[0-9]+$ ]]; then
                    printf "%02d:%02d:%02d" $((sec/3600)) $(( (sec%3600)/60 )) $((sec%60))
                else
                    echo "$sec"
                fi
            }

            F_START=$(format_seconds "$START")
            F_END=$(format_seconds "$END")

            SEEK_ARGS="-ss $START -to $END"
            SAFE_START="${START//:/-}"
            SAFE_END="${END//:/-}"
            CLIP_NAME="${SAFE_START}-${SAFE_END}"
            shift 2
            ;;
        --crop)
            CROP_NAME="$2"
            case $2 in
                left)   CROP_FILTER="crop=iw*0.5:ih:0:0" ;;
                center) CROP_FILTER="crop=iw*0.5:ih:iw*0.25:0" ;;
                right)  CROP_FILTER="crop=iw*0.5:ih:iw*0.5:0" ;;
            esac
            shift 2
            ;;
        --hardsub)
            USE_SUBTITLES=true
            HARDSUB_NAME="hardsub"
            shift 1
            ;;
        --title)
            CUSTOM_TITLE="$2"
            shift 2
            ;;
        --title=*)
            CUSTOM_TITLE="${1#*=}"
            shift 1
            ;;
        --watermark)
            WATERMARK="$2"
            SAFE_WM=$(echo "$WATERMARK" | sed 's/[^a-zA-Z0-9._-]/_/g')
            WM_NAME="wm-${SAFE_WM}"
            shift 2
            ;;
        --bg)
            BG="$2"
            BG_BASE=$(basename "$BG")
            SAFE_BG="${BG_BASE%.*}"
            SAFE_BG=$(echo "$SAFE_BG" | sed 's/[^a-zA-Z0-9._-]/_/g')
            BG_NAME="bg-${SAFE_BG}"
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
    UNIQUE_ID="$(date +%s)_$$"
    if [[ "$INPUT" =~ youtube\.com|youtu\.be ]]; then
        if ! command -v yt-dlp &> /dev/null; then
            echo "[ERROR] yt-dlp not found. Install: yt-dlp"
            exit 1
        fi
        
        YTDLP_RANGE=""
        if [ -n "$START" ] && [ -n "$END" ]; then
            if yt-dlp --help 2>&1 | grep -q "download-sections"; then
                YTDLP_RANGE="--download-sections *${START}-${END}"
                SEEK_ARGS=""
            fi
        fi
        
        echo "[INFO] Downloading video..."
        PROXY=$(get_random_proxy)
        YTDLP_PROXY_ARG=""
        if [ -n "$PROXY" ]; then
            YTDLP_PROXY_ARG="--proxy $PROXY"
        fi
        
        TEMP_INPUT=$(yt-dlp --restrict-filenames \
          --print after_move:filepath \
          --merge-output-format mp4 \
          --sleep-requests 3 \
          --retries 3 \
          --socket-timeout 30 \
          --downloader-args "ffmpeg_i:-reconnect 1 -reconnect_streamed 1 -reconnect_delay_max 5" \
          -f "bv*[height<=720][height>=360]+ba/b[height<=720][height>=360]" \
          $YTDLP_RANGE $YTDLP_PROXY_ARG -o "$TMP_DIR/${UNIQUE_ID}_%(title)s.%(ext)s" "$INPUT" | tail -n 1) || {
            echo "[ERROR] Failed to download YouTube video"
            exit 1
        }
    else
        echo "[INFO] Downloading input..."
        TEMP_INPUT="$TMP_DIR/tmp_input_${UNIQUE_ID}.mp4"
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
if [ -n "$CUSTOM_TITLE" ]; then
    # Sanitize title into hyphens instead of underscores
    BASE_TITLE=$(echo "$CUSTOM_TITLE" | sed 's/[^a-zA-Z0-9.-]/-/g' | tr -s '-')
else
    BASE_TITLE="${RAW_FILENAME%.*}"
    BASE_TITLE="${BASE_TITLE#[0-9]*_[0-9]*_}"
    # Replace spaces and underscores with hyphens, then squeeze multiple hyphens
    BASE_TITLE=$(echo "$BASE_TITLE" | tr ' _' '-' | sed 's/[^a-zA-Z0-9.-]/-/g' | tr -s '-')
fi

# Append active flags dynamically
FILENAME_PARTS=("Clip" "$BASE_TITLE")
[ -n "$CROP_NAME" ] && FILENAME_PARTS+=("$CROP_NAME")
[ -n "$CLIP_NAME" ] && FILENAME_PARTS+=("$CLIP_NAME")
[ -n "$HARDSUB_NAME" ] && FILENAME_PARTS+=("$HARDSUB_NAME")
[ -n "$WM_NAME" ] && FILENAME_PARTS+=("$WM_NAME")
[ -n "$BG_NAME" ] && FILENAME_PARTS+=("$BG_NAME")

# Join array with hyphens
IFS='-'
OUTPUT_FILE="${FILENAME_PARTS[*]}.mp4"
unset IFS

FULL_OUTPUT_PATH="$OUTPUT_DIR/$OUTPUT_FILE"

UNIQUE_ID="${UNIQUE_ID:-$(date +%s)_$$}"
TEMP_AUDIO="$TMP_DIR/tmp_audio_$UNIQUE_ID.wav"
SRT_BASE="$TMP_DIR/tmp_subs_$UNIQUE_ID"
SRT_FILE="$SRT_BASE.srt"
ASS_FILE="$SRT_BASE.ass"

# Cleanup temp files on exit
cleanup() {
    [[ -n "$TEMP_INPUT" && -e "$TEMP_INPUT" ]] && rm -rf "$TEMP_INPUT" || true
    [[ -f "$TEMP_AUDIO" ]] && rm -f "$TEMP_AUDIO" || true
    [[ -f "$SRT_FILE" ]] && rm -f "$SRT_FILE" || true
    [[ -f "$ASS_FILE" ]] && rm -f "$ASS_FILE" || true
    [[ -f "$SRT_BASE.json" ]] && rm -f "$SRT_BASE.json" || true
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
        if ! ffmpeg -y -hide_banner -stats $SEEK_ARGS -i "$INPUT" -ar 16000 -ac 1 -c:a pcm_s16le "$TEMP_AUDIO"; then
            echo "[ERROR] Failed to extract audio"
            exit 1
        fi

        JSON_FILE="$SRT_BASE.json"
        WHISPER_LOG="$TMP_DIR/whisper.log"
        if ! whisper-cli -m "$MODEL_PATH" -f "$TEMP_AUDIO" -osrt -ojf -of "$SRT_BASE" -np > "$WHISPER_LOG" 2>&1; then
            echo "[WARN] Whisper transcription failed, check $WHISPER_LOG"
        else
            rm -f "$WHISPER_LOG"
        fi

        if [ -f "$JSON_FILE" ]; then
            python3 "$SCRIPT_DIR/src/ass_builder.py" "$JSON_FILE" "$ASS_FILE"

            rm -f "$JSON_FILE"
            if [ -f "$ASS_FILE" ]; then
                ESCAPED_ASS_FILE=$(printf '%s\n' "$ASS_FILE" | sed -e 's/\\/\\\\/g' -e "s/'/\\\\'/g" -e 's/:/\\:/g')
                SUBTITLE_FILTER="subtitles='$ESCAPED_ASS_FILE':force_style='Fontname=DejaVuSans-Bold,Fontsize=80,PrimaryColour=&H00FFFF00'"
            fi
        else
            echo "[WARN] JSON file not created"
        fi
    fi
fi

echo "[INFO] Generating video..."

ffmpeg_status=0
if [ -n "$BG" ]; then
    BG=$(realpath "$BG")
    echo "[INFO] Using background: $BG"

    BG_LOOP=""
    OVERLAY_SHORTEST=""
    case "${BG,,}" in
        *.mp4|*.mov|*.avi|*.mkv|*.webm|*.m4v)
            BG_LOOP="-stream_loop -1"
            OVERLAY_SHORTEST=":shortest=1"
            echo "[INFO] Background is video — looping enabled"
            ;;
    esac

    VIDEO_CHAIN="[0:v]"
    [ -n "$CROP_FILTER" ] && VIDEO_CHAIN+="$CROP_FILTER,"
    VIDEO_CHAIN+="scale=1080:1920:force_original_aspect_ratio=decrease[fg]"

    BG_CHAIN="[1:v]fps=30,scale=1080:1920:force_original_aspect_ratio=increase,crop=1080:1920[bg]"

    POST_CHAIN="[bg][fg]overlay=(W-w)/2:(H-h)/2$OVERLAY_SHORTEST"
    POST_CHAIN+=",drawtext=text='$WATERMARK':fontcolor=white@0.5:fontsize=48:x=(w-tw)/2:y=(h-th)/2:fontfile='$FONT_PATH'"
    [ -n "$SUBTITLE_FILTER" ] && POST_CHAIN+=",$SUBTITLE_FILTER"
    POST_CHAIN+="[vout]"

    ffmpeg -y -hide_banner -loglevel error $SEEK_ARGS -i "$INPUT" $BG_LOOP -i "$BG" \
        -filter_complex "$VIDEO_CHAIN;$BG_CHAIN;$POST_CHAIN" \
        -map '[vout]' -map 0:a? -c:a aac -b:a 128k \
        -c:v libx264 -preset faster -crf 23 -pix_fmt yuv420p \
        "$FULL_OUTPUT_PATH" || ffmpeg_status=$?
else
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
        "$FULL_OUTPUT_PATH" || ffmpeg_status=$?
fi

if [ $ffmpeg_status -eq 0 ]; then
    echo "[INFO] Successfully generated: $OUTPUT_FILE"
    if send_telegram "$FULL_OUTPUT_PATH"; then
        echo "[INFO] Sent to Telegram"
    else
        echo "[WARN] Skip send to send to Telegram"
    fi
else
    echo "[ERROR] Failed to generate clip"
fi

exit $ffmpeg_status
