"""Command-line interface definition."""
import argparse
from dataclasses import dataclass, field
from pathlib import Path

from . import timeutils

CROP_CHOICES = ("left", "center", "right")


@dataclass
class Options:
    input: str = ""
    start: str = ""
    end: str = ""
    crop: str = ""
    hardsub: bool = False
    title: str = ""
    watermark: str = "obrolan_clip"
    bg: Path | None = None


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="clip.py", description="Modular video clip generator."
    )
    p.add_argument("input", nargs="?", help="Input file path or URL")
    p.add_argument(
        "--clip", nargs="*", metavar=("START", "END"),
        help="Clip range: seconds or HH:MM:SS (e.g. --clip 30 50 or --clip '30 50')",
    )
    p.add_argument("--crop", choices=CROP_CHOICES, help="Crop half: left/center/right")
    p.add_argument("--hardsub", action="store_true", help="Burn subtitles")
    p.add_argument("--title", help="Custom output title")
    p.add_argument("--watermark", default="obrolan_clip", help="Watermark text")
    p.add_argument("--bg", type=Path, help="Background image or video")
    return p


def parse(argv: list[str]) -> Options:
    ns = build_parser().parse_args(argv)
    opts = Options(
        input=ns.input or "",
        crop=ns.crop or "",
        hardsub=ns.hardsub,
        title=ns.title or "",
        watermark=ns.watermark,
        bg=ns.bg,
    )
    if ns.clip:
        raw = ns.clip
        if len(raw) == 1:
            raw = raw[0].split()
        if len(raw) != 2:
            raise SystemExit(
                "[ERROR] --clip needs two values: START END"
            )
        start, end = raw
        timeutils.validate_time(start)
        timeutils.validate_time(end)
        opts.start, opts.end = start, end
    return opts
