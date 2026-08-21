"""Time parsing and formatting helpers."""
import re

_SECONDS_RE = re.compile(r"^\d+(\.\d+)?$")
_HMS_RE = re.compile(r"^(\d{1,2}):(\d{1,2})(?::(\d{1,2})(\.\d+)?)?$")


class TimeFormatError(ValueError):
    pass


def validate_time(value: str) -> str:
    """Return the value if valid (seconds or HH:MM[:SS]), else raise."""
    if _SECONDS_RE.match(value) or _HMS_RE.match(value):
        return value
    raise TimeFormatError(
        f"[ERROR] Invalid time format: {value}. "
        "Use seconds (e.g., 30) or HH:MM:SS (e.g., 05:58)"
    )


def to_seconds(value: str) -> float:
    if _SECONDS_RE.match(value):
        return float(value)
    match = _HMS_RE.match(value)
    if not match:
        raise TimeFormatError(f"[ERROR] Invalid time format: {value}")
    h, m, s = int(match[1]), int(match[2]), float(match[3] or 0)
    return h * 3600 + m * 60 + s


def format_timestamp(seconds: float) -> str:
    """Integer seconds become HH:MM:SS; fractional stay as-is."""
    if seconds == int(seconds):
        total = int(seconds)
        return f"{total // 3600:02d}:{(total % 3600) // 60:02d}:{total % 60:02d}"
    return str(seconds)


def safe_name(value: str) -> str:
    """Make a value filesystem/filename safe."""
    out = re.sub(r"[^a-zA-Z0-9._-]", "_", value)
    return re.sub(r"-+", "-", out)
