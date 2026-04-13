#!/usr/bin/env bash

echo "[INFO] Initializing video processing..."

# Resolve absolute paths
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
RESULT_DIR="$SCRIPT_DIR/result"
FONT_PATH="$SCRIPT_DIR/public/font/Coolvetica.ttf"
MODEL_PATH="$HOME/.cache/whisper-models/ggml-medium.bin"

mkdir -p "$RESULT_DIR"

# Variables
INPUT=""
SEEK_ARGS=""
CROP_FILTER=""
WATERMARK="jee"
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
            INPUT=$(realpath "$1")
            shift 1
            ;;
    esac
done

if [[ -z "$INPUT" || ! -f "$INPUT" ]]; then
    echo "[ERROR] Valid input file required."
    exit 1
fi

# Naming Logic
RAW_FILENAME=$(basename "$INPUT")
CLEAN_FILENAME="${RAW_FILENAME// /-}"
OUTPUT_FILE="clip-$CLEAN_FILENAME"
FULL_OUTPUT_PATH="$RESULT_DIR/$OUTPUT_FILE"
TEMP_AUDIO="$RESULT_DIR/tmp_audio.wav"
SRT_BASE="$RESULT_DIR/tmp_subs"
SRT_FILE="$SRT_BASE.srt"

# Transcription Logic
SUBTITLE_FILTER=""
if [ "$USE_SUBTITLES" = true ]; then
    if ! command -v whisper-cli &> /dev/null; then
        echo "[WARN] whisper-cpp not found. Skipping subtitles."
    elif [ ! -f "$MODEL_PATH" ]; then
        echo "[WARN] GGML model not found at $MODEL_PATH. Skipping subtitles."
    else
        echo "[INFO] Extracting audio..."
        ffmpeg -y -hide_banner -loglevel error $SEEK_ARGS -i "$INPUT" -ar 16000 -ac 1 -c:a pcm_s16le "$TEMP_AUDIO"
        echo "[INFO] Transcribing..."
        whisper-cli -m "$MODEL_PATH" -f "$TEMP_AUDIO" -osrt -of "$SRT_BASE" > /dev/null 2>&1
        SUBTITLE_FILTER="subtitles='$SRT_FILE':force_style='PrimaryColour=&H00FFFF,OutlineColour=&H000000,BorderStyle=1,Outline=2,Fontname=Coolvetica,Fontsize=18',"
    fi
fi

echo "[INFO] Generating: $OUTPUT_FILE"

# FFmpeg Execution
ffmpeg -y -hide_banner -loglevel error $SEEK_ARGS -i "$INPUT" \
    -vf "${CROP_FILTER}scale=1080:1920:force_original_aspect_ratio=decrease,pad=1080:1920:(ow-iw)/2:(oh-ih)/2:color=black,${SUBTITLE_FILTER}drawtext=text='$WATERMARK':fontcolor=white@0.5:fontsize=48:x=(w-tw)/2:y=(h-th)/2:fontfile='$FONT_PATH'" \
    -c:v libx264 -preset faster -crf 23 -pix_fmt yuv420p \
    -c:a aac -b:a 128k "$FULL_OUTPUT_PATH"

# Cleanup
if [ $? -eq 0 ]; then
    echo "[INFO] Successfully generated: $OUTPUT_FILE"
    [[ -f "$TEMP_AUDIO" ]] && rm "$TEMP_AUDIO"
    [[ -f "$SRT_FILE" ]] && rm "$SRT_FILE"
else
    echo "[ERROR] Failed to generate clip"
    [[ -f "$TEMP_AUDIO" ]] && rm "$TEMP_AUDIO"
    [[ -f "$SRT_FILE" ]] && rm "$SRT_FILE"
fi
