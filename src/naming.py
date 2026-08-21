"""Output filename construction."""
import re
from pathlib import Path

from . import timeutils


def safe_filename(value: str) -> str:
    out = value.replace(" ", "-")
    out = re.sub(r"[^a-zA-Z0-9.-]", "-", out)
    return re.sub(r"-+", "-", out)


def base_title(raw: str, custom: str) -> str:
    """Derive a clean base title from filename or custom input."""
    if custom:
        return safe_filename(custom)
    name = Path(raw).stem
    name = re.sub(r"^[0-9]*_[0-9]*_", "", name)
    return safe_filename(name)


def build_name(
    raw: str, custom_title: str, clip_name: str, *, crop: str = "", hardsub: str = "",
    wm: str = "", bg: str = "",
) -> str:
    parts = ["Clip", base_title(raw, custom_title)]
    if crop:
        parts.append(crop)
    if clip_name:
        parts.append(clip_name)
    if hardsub:
        parts.append(hardsub)
    if wm:
        parts.append(wm)
    if bg:
        parts.append(bg)
    return "-".join(parts) + ".mp4"


def clip_segment_name(start: str, end: str) -> str:
    s = timeutils.safe_name(start)
    e = timeutils.safe_name(end)
    return f"{s}-{e}"
