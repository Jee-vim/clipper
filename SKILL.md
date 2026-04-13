# Clip video 

## Language
- Bash

## Dependencies
- **ffmpeg**: (v6.0+ recommended)
- **yt-dlp**: for YouTube URLs (`pip install yt-dlp`)
- **whisper-cpp** (optional): for subtitles (`whisper-cli`)
- **GGML Model** (optional): ggml-medium.bin (Stored in ~/.cache/whisper-models/)
- **Font Path**: `./public/font/Coolvetica.ttf` (Must be resolved to absolute path in script)

## Input Sources
- **Local file**: `/path/to/video.mp4`
- **URL**: `https://example.com/video.mp4`
- **YouTube**: `https://youtu.be/XXXXX` or `https://www.youtube.com/watch?v=XXXXX`

## Technical Implementation Logic
1.  **URL Detection**: If input starts with `http://` or `https://`, treat as URL.
2.  **Download**:
   - **YouTube**: Use yt-dlp with max 1080p quality (`[height<=1080]`). If `--clip` provided, use `--download-sections` to download only that portion.
   - **Regular URL**: Use curl to download full video.
   - **Local file**: Use directly.
3.  **Seek (Temporal)**: If `--clip` is provided for local files, apply `-ss` and `-to` as input parameters (before `-i`).
4.  **Audio Extraction**: Extract mono 16kHz PCM audio (pcm_s16le) as a temporary .wav for transcription.
5.  **Transcription**: Generate .srt using whisper-cpp. Output name must be fixed to allow ffmpeg to target the file.
6.  **Crop (Spatial)**: If `--crop` is passed, apply the `crop` filter first to reduce pixel data.
7.  **Fit (Standardization)**: Scale result to fit within 1080x1920. Use `force_original_aspect_ratio=decrease` to maintain source ratio.
8.  **Pad (Canvas)**: Apply `pad` to create the final 9:16 black background and center the video.
9.  **Branding (Watermark)**: Apply `drawtext` as the final filter so it sits on top of the padded canvas.

## Filter Specifications
- **Scaling**: `scale=1080:1920:force_original_aspect_ratio=decrease`
- **Padding**: `pad=1080:1920:(ow-iw)/2:(oh-ih)/2:color=black`
- **Subtitles**: `subtitles='file.srt':force_style='PrimaryColour=&H00FFFF,OutlineColour=&H000000,BorderStyle=1,Outline=2,Fontname=Coolvetica,Fontsize=18'`
- **Watermark**: `drawtext=text='obrolan_clip':fontcolor=white@0.5:fontsize=48:x=(w-tw)/2:y=(h-th)/2`

## Performance & Quality
- **Preset**: `faster`
- **CRF**: `23`
- **Pixel Format**: `yuv420p` 
- **Audio**: `-c:a aac -b:a 128k`
- **YouTube Max Quality**: 1080p

## Result
1. **Resolution**: 1080x1920 (Fixed 9:16).
2. **Dynamic Subtitle**: Only present if --subtitle is passed; styled for maximum readability.
3. **Background**: Black padding for non-matching ratios.
4. **Save Location**: `./result/` (Auto-created if missing).
5. **Naming Convention**: `clip-[original_filename]`.

## Options
- **--crop [left|center|right]**: Horizontal 50% slice logic. 
  - `left`: `crop=iw*0.5:ih:0:0`
  - `center`: `crop=iw*0.5:ih:iw*0.25:0`
  - `right`: `crop=iw*0.5:ih:iw*0.5:0`
- **--clip "[start] [end]"**: Temporal clipping. 
  - If omitted: Process entire video.
  - Supports seconds (`0 30`) or timestamp (`05:58 06:00`).
  - For YouTube: downloads only that portion.
- **--subtitle**: Trigger whisper-cpp transcription pipeline
- **--watermark "TEXT"**: Custom watermark text (default: "obrolan_clip")
