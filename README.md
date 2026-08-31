# Clipper

Vertical (9:16) clip generator from url, video, or audio input.

## Commands

```bash
# Local file
./clip.py video.mp4

# Clip a range (seconds or HH:MM:SS)
./clip.py --clip "0 30" video.mp4
./clip.py --clip "05:40 06:00" video.mp4

# URL input
./clip.py "https://youtu.be/XXXXX"
./clip.py --clip "0 30" "https://youtu.be/XXXXX"
./clip.py "https://example.com/video.mp4"

# Crop + subtitles + watermark
./clip.py --clip "0 30" --crop center --hardsub --watermark "mytext" video.mp4

# Background image/video
./clip.py --bg input/minecraft.jpg video.mp4

# Audio input + background video + transcribed subtitles
./clip.py --hardsub --bg input/bg.mp4 voice.mp3

# Story: generate TTS from a script
./clip.py --story script.txt --bg input/bg.mp4
./clip.py --story script.srt --bg input/bg.mp4
./clip.py --story script.txt --bg input/bg.mp4 --hardsub

# Story: use an existing audio file, transcript extracted from it
./clip.py --story podcast.mp3 --bg input/bg.mp4
./clip.py --story podcast.mp3

# AI story: Gemini writes the script from a topic, then TTS
./clip.py --topic "why is the ocean salty" --bg input/bg.mp4
```

## Options

| Option | Description | Example |
|--------|-------------|---------|
| `input` | File path or URL | `video.mp4` |
| `--clip "START END"` | Time range to extract | `--clip "0 30"` |
| `--crop left\|center\|right` | Crop horizontal position | `--crop center` |
| `--hardsub` | Generate and embed subtitles | `--hardsub` |
| `--title TEXT` | Custom output title | `--title "ep1"` |
| `--watermark TEXT` | Watermark text (default: `obrolan_clip`) | `--watermark "mytext"` |
| `--bg PATH` | Image/video background | `--bg input/bg.jpg` |
| `--story SCRIPT` | TTS audio from a script (output `<script>.mp3`) | `--story script.txt` |
| `--story AUDIO` | Use audio directly, extract transcript | `--story podcast.mp3` |
| `--topic TOPIC` | Gemini writes a two-speaker script, then TTS | `--topic "ocean facts"` |

## Output

Saved to `output/` with a `Clip-` prefix (e.g. `Clip-<title>-<args>.mp4`).

## AI story setup

Set `GEMINI_API_KEY` (free key from Google AI Studio) in `.env` or the shell.
Optional `GEMINI_MODEL` overrides the default `gemini-2.5-flash`. The generated
script is saved as `output/story_<topic>.txt` so you can reuse or edit it.
