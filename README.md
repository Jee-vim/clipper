# Clipper

Video processing CLI tool for creating vertical (9:16) clips from url or local video

## Usage

```bash
./clip.sh <input> [options]
```

## Options

| Option | Description | Example |
|--------|-------------|---------|
| `--clip "START END"` | Time range to extract | `--clip "0 30"` or `--clip "05:40 06:00"` |
| `--crop left\|center\|right` | Crop horizontal position | `--crop center` |
| `--hardsub` | Auto generate and embed subtitles | `--hardsub` |
| `--watermark "TEXT"` | Custom watermark (default: "obrolan_clip") | `--watermark "mytext"` |
| `--bg PATH` | Image/video as background instead of black | `--bg public/bg.jpg` |

## Examples

```bash
# Local file
./clip.sh video.mp4

# Clip a local file (seconds)
./clip.sh --clip "0 30" video.mp4

# Clip a local file (timestamp)
./clip.sh --clip "05:40 06:00" video.mp4

# YouTube video (full)
./clip.sh "https://youtu.be/XXXXX"

# YouTube video with clip
./clip.sh --clip "0 30" "https://youtu.be/XXXXX"

# Regular URL
./clip.sh "https://example.com/video.mp4"

# With crop, subtitles, and custom watermark
./clip.sh --clip "0 30" --crop center --hardsub --watermark "mytext" video.mp4

# With background (image or video)
./clip.sh --bg public/minecraft.jpg video.mp4

## Output

Generated videos are saved to `result/` directory with `clip-` prefix.
