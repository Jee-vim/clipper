#!/usr/bin/env bash

echo "[INFO] Initializing video processing..."

# Resolve absolute paths
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
RESULT_DIR="$SCRIPT_DIR/result"
FONT_PATH="$SCRIPT_DIR/public/font/Coolvetica.ttf"
mkdir -p "$RESULT_DIR"

# Variables
INPUT=""
SEEK_ARGS=""
CROP_FILTER=""
WATERMARK="jee"

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

if [[ -z "$INPUT" ]]; then
    echo "[ERROR] No input file provided."
    exit 1
fi

# Naming Logic
RAW_FILENAME=$(basename "$INPUT")
CLEAN_FILENAME="${RAW_FILENAME// /-}"
OUTPUT_FILE="clip-$CLEAN_FILENAME"
FULL_OUTPUT_PATH="$RESULT_DIR/$OUTPUT_FILE"

echo "[INFO] Generating: $OUTPUT_FILE"

# FFmpeg Execution
ffmpeg -y -hide_banner -loglevel error $SEEK_ARGS -i "$INPUT" \
    -vf "${CROP_FILTER}scale=1080:1920:force_original_aspect_ratio=decrease,pad=1080:1920:(ow-iw)/2:(oh-ih)/2:color=black,drawtext=text='$WATERMARK':fontcolor=white@0.5:fontsize=48:x=(w-tw)/2:y=(h-th)/2:fontfile='$FONT_PATH'" \
    -c:v libx264 -preset faster -crf 23 -pix_fmt yuv420p \
    -c:a aac -b:a 128k "$FULL_OUTPUT_PATH" > /dev/null 2>&1

if [ $? -eq 0 ]; then
    echo "[INFO] Successfully generated: $OUTPUT_FILE"
else
    echo "[ERROR] Failed to generate clip"
fi
