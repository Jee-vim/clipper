# Clipper

Video processing CLI tool for creating vertical (9:16) clips from url, local video, or **audio** input.

## Audio input

Pass an audio file (e.g. `voice.mp3`) as input. With `--bg <video>`, the
background video becomes the only visible track while your audio is the sound
track; add `--hardsub` to burn subtitles transcribed from the audio.
Without `--bg`, a black background is used.

```bash
./clip.py --hardsub --bg public/bg.mp4 voice.mp3
```

## Usage

```bash
./clip.py <input> [options]
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
./clip.py video.mp4

# Clip a local file (seconds)
./clip.py --clip "0 30" video.mp4

# Clip a local file (timestamp)
./clip.py --clip "05:40 06:00" video.mp4

# YouTube video (full)
./clip.py "https://youtu.be/XXXXX"

# YouTube video with clip
./clip.py --clip "0 30" "https://youtu.be/XXXXX"

# Regular URL
./clip.py "https://example.com/video.mp4"

# With crop, subtitles, and custom watermark
./clip.py --clip "0 30" --crop center --hardsub --watermark "mytext" video.mp4

# With background (image or video)
./clip.py --bg public/minecraft.jpg video.mp4

## Output

Generated videos are saved to `output/` directory with a `Clip-` prefix (e.g. `Clip-<title>-<args>.mp4`).
