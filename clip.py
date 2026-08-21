#!/usr/bin/env python3
"""Modular entry point for clip.sh migration.

Usage mirrors the original shell script:
    clip.py <input> [--clip START END] [--crop left|center|right]
            [--hardsub] [--title TITLE] [--watermark TEXT] [--bg PATH]
"""
import sys
from pathlib import Path

from src import Config, Options, parse
from src import download, naming, transcribe, ffmpeg, telegram, timeutils

_TMP_FILES: list[Path] = []


def _cleanup() -> None:
    for f in _TMP_FILES:
        if f.is_file():
            f.unlink()
        elif f.is_dir():
            import shutil
            shutil.rmtree(f, ignore_errors=True)


def _resolve_input(opts: Options, cfg: Config) -> tuple[Path, bool, bool]:
    src = opts.input
    if src.startswith("http://") or src.startswith("https://"):
        path, trimmed = download.download(src, cfg.tmp_dir, cfg.proxies, opts.start, opts.end)
        return path, True, trimmed
    if not src or not Path(src).is_file():
        raise SystemExit("[ERROR] Valid input file or URL required.")
    return Path(src).resolve(), False, False


def main(argv: list[str]) -> int:
    opts = parse(argv)
    cfg = Config.from_env()
    cfg.output_dir.mkdir(parents=True, exist_ok=True)
    cfg.tmp_dir.mkdir(parents=True, exist_ok=True)

    try:
        input_path, is_temp, trimmed = _resolve_input(opts, cfg)
        if is_temp:
            _TMP_FILES.append(input_path)

        seek = "" if trimmed else ffmpeg.seek_args(opts.start, opts.end)
        clip_name = naming.clip_segment_name(opts.start, opts.end) if opts.start else ""

        wm_token = timeutils.safe_name(opts.watermark)
        bg_token = naming.safe_filename(opts.bg.stem) if opts.bg else ""
        out_name = naming.build_name(
            input_path.name, opts.title, clip_name,
            crop=opts.crop, hardsub="hardsub" if opts.hardsub else "",
            wm=f"wm-{wm_token}" if opts.watermark else "",
            bg=f"bg-{bg_token}" if opts.bg else "",
        )
        output_path = cfg.output_dir / out_name

        ass = None
        if opts.hardsub:
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
