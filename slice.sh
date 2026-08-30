#!/usr/bin/env bash
# Slice a large video into 10-minute parts, then each part into 1.2-minute clips.
# Uses stream copy (no re-encode) so it is fast. Usage: ./slice.sh [INPUT]
set -euo pipefail

IN="${1:-public/minecraft.mp4}"
SEG10="tmp/seg10"
SEG12="public/clips"
BIG=600   # 10 minutes
SMALL=72  # 1.2 minutes (72s)

mkdir -p "$SEG10" "$SEG12"
rm -f "$SEG10"/*.mp4 "$SEG12"/*.mp4 2>/dev/null || true

echo "[INFO] Splitting into ${BIG}s segments..."
ffmpeg -y -i "$IN" -c copy -f segment -segment_time "$BIG" -reset_timestamps 1 "$SEG10/part_%03d.mp4"

echo "[INFO] Splitting each part into ${SMALL}s clips..."
for f in "$SEG10"/*.mp4; do
  base="$(basename "${f%.mp4}")"
  ffmpeg -y -i "$f" -c copy -f segment -segment_time "$SMALL" -reset_timestamps 1 "$SEG12/${base}_%04d.mp4"
done

count="$(ls -1 "$SEG12"/*.mp4 2>/dev/null | wc -l)"
echo "[INFO] Done. ${count} clips in $SEG12"
