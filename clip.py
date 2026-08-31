#!/usr/bin/env python3
"""Modular entry point for clip.sh migration.

Usage mirrors the original shell script:
    clip.py <input> [--clip START END] [--crop left|center|right]
            [--hardsub] [--title TITLE] [--watermark TEXT] [--bg PATH]

TTS story mode (generate audio from a script):
    clip.py --story SCRIPT [AUDIO_OUT] --bg BG_VIDEO

Audio story mode (use existing audio, transcript extracted from it):
    clip.py --story AUDIO [--bg BG_VIDEO]
"""
import sys
from pathlib import Path

from src import Config, Options, parse, generate_story
from src import download, naming, transcribe, ffmpeg, telegram, timeutils
from src import gemini

_TMP_FILES: list[Path] = []

AUDIO_EXTS = (".mp3", ".wav", ".m4a", ".aac", ".ogg", ".oga", ".opus", ".flac")


def _is_audio(path: str) -> bool:
    return Path(path).suffix.lower() in AUDIO_EXTS


def _cleanup() -> None:
    for f in _TMP_FILES:
        if f.is_file():
            f.unlink()
        elif f.is_dir():
            import shutil
            shutil.rmtree(f, ignore_errors=True)


def _resolve_story(opts: Options, cfg: Config) -> tuple[Path, bool]:
    """Resolve a --story target.

    Returns (audio_path, is_audio_input). When the argument is an audio
    file it is used directly and the transcript is extracted from it; when it
    is a script the TTS audio is generated from it.
    """
    first = opts.story[0]
    if _is_audio(first):
        return Path(first).resolve(), True

    script = first
    audio_out = f"{Path(script).stem}.mp3"
    out_path = (cfg.output_dir / audio_out).resolve()
    out_path.parent.mkdir(parents=True, exist_ok=True)
    print(f"[INFO] Generating TTS from story: {script}")
    audio_path = generate_story(Path(script), out_path)
    return audio_path, False


def _resolve_topic(opts: Options, cfg: Config) -> Path:
    """Write an AI script from a topic, then generate its TTS audio."""
    print(f"[INFO] Writing script from topic via Gemini: {opts.topic}")
    script = gemini.generate_script(
        opts.topic, api_key=cfg.gemini_api_key, model=cfg.gemini_model,
        out_dir=cfg.output_dir,
    )
    audio_out = script.with_suffix(".mp3")
    print(f"[INFO] Generating TTS from AI script: {script.name}")
    return generate_story(script, audio_out)


def _resolve_input(opts: Options, cfg: Config) -> tuple[Path, bool, bool, bool]:
    if opts.topic:
        return _resolve_topic(opts, cfg), True, False, False
    if opts.story:
        path, is_audio = _resolve_story(opts, cfg)
        return path, True, False, is_audio

    src = opts.input
    if src.startswith("http://") or src.startswith("https://"):
        path, trimmed = download.download(src, cfg.tmp_dir, cfg.proxies, opts.start, opts.end)
        return path, True, trimmed
    if not src or not Path(src).is_file():
        raise SystemExit("[ERROR] Valid input file, URL, or --story required.")
    return Path(src).resolve(), False, False, False


def main(argv: list[str]) -> int:
    opts = parse(argv)
    cfg = Config.from_env()
    cfg.output_dir.mkdir(parents=True, exist_ok=True)
    cfg.tmp_dir.mkdir(parents=True, exist_ok=True)

    try:
        input_path, is_temp, trimmed, story_is_audio = _resolve_input(opts, cfg)
        if is_temp:
            _TMP_FILES.append(input_path)

        seek = "" if trimmed else ffmpeg.seek_args(opts.start, opts.end)
        clip_name = naming.clip_segment_name(opts.start, opts.end) if opts.start else ""

        wm_token = timeutils.safe_name(opts.watermark)
        bg_token = naming.safe_filename(opts.bg.stem) if opts.bg else ""
        out_name = naming.build_name(
            input_path.name, opts.title, clip_name,
            crop=opts.crop, hardsub="hardsub" if (opts.hardsub or story_is_audio) else "",
            wm=f"wm-{wm_token}" if opts.watermark else "",
            bg=f"bg-{bg_token}" if opts.bg else "",
        )
        output_path = cfg.output_dir / out_name

        ass = None
        if opts.hardsub or story_is_audio:
            if story_is_audio:
                print("[INFO] Extracting transcript from audio for subtitles")
            uid = f"{id(output_path)}"
            base = cfg.tmp_dir / f"tmp_subs_{uid}"
            _TMP_FILES.append(base.with_suffix(".wav"))
            _TMP_FILES.append(base.with_suffix(".ass"))
            _TMP_FILES.append(base.with_suffix(".json"))
            ass = transcribe.transcribe(input_path, base, cfg.model_path, seek)

        print("[INFO] Generating video...")
        status = ffmpeg.render(
            input_path, output_path,
            crop=opts.crop, watermark=opts.watermark, font=cfg.font_path,
            bg=opts.bg, ass=ass, seek=seek,
        )

        if status == 0:
            print(f"[INFO] Successfully generated: {out_name}")
            if telegram.send_video(output_path, cfg.telegram_token, cfg.telegram_chat_id):
                print("[INFO] Sent to Telegram")
            else:
                print("[WARN] Skip send to Telegram")
        else:
            print("[ERROR] Failed to generate clip")
        return status
    finally:
        _cleanup()


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
