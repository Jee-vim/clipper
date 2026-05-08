#!/usr/bin/env python3
import sys
import json


def main():
    if len(sys.argv) < 3:
        print("Usage: subtitle_generator.py <json> <ass>", file=sys.stderr)
        sys.exit(1)


def format_ts(sec: float) -> str:
    h = int(sec // 3600)
    m = int((sec % 3600) // 60)
    s = sec % 60
    return f"{h:02d}:{m:02d}:{s:05.2f}"


def main():
    json_path = sys.argv[1]
    ass_path = sys.argv[2]

    with open(json_path, 'r', encoding='utf-8') as f:
        data = json.load(f)

    ass_header = """[Script Info]
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

    with open(ass_path, 'w', encoding='utf-8') as f:
        f.write(ass_header)

        for segment in data.get('transcription', []):
            tokens = segment.get('tokens', [])

            words = []
            for token in tokens:
                text = token.get('text', '').strip()
                if text and not text.startswith('[') and text not in ['', '(', ')', ',', '.', '!', '?', '-']:
                    offset_from = token.get('offsets', {}).get('from', 0) / 1000.0
                    offset_to = token.get('offsets', {}).get('to', 0) / 1000.0
                    words.append({'word': text, 't0': offset_from, 't1': offset_to})

            if not words:
                offset_from = segment.get('offsets', {}).get('from', 0) / 1000.0
                offset_to = segment.get('offsets', {}).get('to', 0) / 1000.0
                text = segment.get('text', '').replace(',', '\\,')
                f.write(f"Dialogue: 0,{format_ts(offset_from)},{format_ts(offset_to)},Default,,0,0,0,,{text}\n")
                continue

            lines = []
            current_line = []
            for w in words:
                current_line.append(w)
                if len(current_line) >= 6:
                    lines.append(current_line)
                    current_line = []
            if current_line:
                lines.append(current_line)

            for line_words in lines:
                if not line_words:
                    continue

                for i, word_data in enumerate(line_words):
                    word_start = word_data.get('t0', 0)
                    word_end = word_data.get('t1', 0)
                    current_word = word_data.get('word', '').strip()

                    if not current_word:
                        continue

                    text_with_highlight = f"{{\\1c&H00FFFF&}}{current_word}"
                    text_with_highlight = text_with_highlight.replace(',', '\\,')

                    f.write(f"Dialogue: 0,{format_ts(word_start)},{format_ts(word_end)},Default,,0,0,0,,{text_with_highlight}\n")


if __name__ == '__main__':
    main()
