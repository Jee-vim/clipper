# Clip video 

## Language
- Bash

## Dependencies
- **ffmpeg**: (v6.0+ recommended)
- **Font Path**: `./public/font/Coolvetica.ttf` (Must be resolved to absolute path in script)

## Technical Implementation Logic
1.  **Seek (Temporal)**: If `--clip` is provided, apply `-ss` and `-to` as **input parameters** (before `-i`) to enable fast seeking.
2.  **Crop (Spatial)**: If `--crop` is passed, apply the `crop` filter first to reduce pixel data.
3.  **Fit (Standardization)**: Scale result to fit within 1080x1920. Use `force_original_aspect_ratio=decrease` to maintain source ratio.
4.  **Pad (Canvas)**: Apply `pad` to create the final 9:16 black background and center the video.
5.  **Branding (Watermark)**: Apply `drawtext` as the final filter so it sits on top of the padded canvas.

## Filter Specifications
- **Scaling**: `scale=1080:1920:force_original_aspect_ratio=decrease`
- **Padding**: `pad=1080:1920:(ow-iw)/2:(oh-ih)/2:color=black`
- **Watermark**: `drawtext=text='jee':fontcolor=white@0.5:fontsize=48:x=(w-tw)/2:y=(h-th)/2`

## Performance & Quality
- **Preset**: `faster`
- **CRF**: `23`
- **Pixel Format**: `yuv420p` 
- **Audio**: `-c:a aac -b:a 128k`

## Result
1. **Resolution**: 1080x1920 (Fixed)
2. **Aspect Ratio**: 9:16
3. **Background**: Black padding for non-matching ratios
4. **Branding**: Hardcoded "jee" at 50% opacity
5. **Save Location**: `./result/` (Auto-created if missing)
6. **Naming Convention**: `clip-[original_filename]`

## Options
- **--crop [left|center|right]**: Horizontal 50% slice logic. 
  - `left`: `crop=iw*0.5:ih:0:0`
  - `center`: `crop=iw*0.5:ih:iw*0.25:0`
  - `right`: `crop=iw*0.5:ih:iw*0.5:0`
- **--clip "[start] [end]"**: Temporal clipping. 
  - If omitted: Process entire video.
  - Usage: `--clip "00:00:50 00:01:00"`
