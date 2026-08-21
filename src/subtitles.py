"""Build ASS subtitles from whisper JSON (ported from ass_builder.py)."""
import json
from pathlib import Path


def format_ts(sec: float) -> str:
    h = int(sec // 3600)
    m = int((sec % 3600) // 60)
    s = sec % 60
    return f"{h:02d}:{m:02d}:{s:05.2f}"


def _header() -> str:
    return """[Script Info]
Title: TikTok Style Subtitles
ScriptType: v4.00+
Collisions: Normal
PlayResX: 1080
PlayResY: 1920
PlayDepth: 0
Timer: 100.0.0

[V4+ Styles]
Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
Style: Default,DejaVuSans-Bold,80,&H00FFFF00,&H000000FF,&H00000000,&H00000000,-1,0,0,0,100,100,0,0,1,2,0,5,10,10,-960,1

[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
"""


def build_ass(json_path: Path, ass_path: Path) -> None:
    data = json.loads(json_path.read_text(encoding="utf-8"))
    with ass_path.open("w", encoding="utf-8") as f:
        f.write(_header())
        for segment in data.get("transcription", []):
            tokens = segment.get("tokens", [])
            words = []
            for tok in tokens:
                text = tok.get("text", "").strip()
                if text and not text.startswith("[") and text not in ["", "(", ")", ",", ".", "!", "?", "-"]:
                    off = tok.get("offsets", {})
                    words.append({
                        "word": text,
                        "t0": off.get("from", 0) / 1000.0,
                        "t1": off.get("to", 0) / 1000.0,
                    })
            if not words:
                off = segment.get("offsets", {})
                f.write(_line(
                    off.get("from", 0) / 1000.0, off.get("to", 0) / 1000.0,
                    segment.get("text", "").replace(",", "\\,"),
                ))
                continue
            lines = [words[i:i + 6] for i in range(0, len(words), 6)]
            for line_words in lines:
                for w in line_words:
                    wd = w.get("word", "").strip()
                    if not wd:
                        continue
                    text = ("{\\1c&H00FFFF&}" + wd).replace(",", "\\,")
                    f.write(_line(w.get("t0", 0), w.get("t1", 0), text))


def _line(t0: float, t1: float, text: str) -> str:
    return f"Dialogue: 0,{format_ts(t0)},{format_ts(t1)},Default,,0,0,0,,{text}\n"
