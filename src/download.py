"""Download URLs (YouTube via yt-dlp, generic via curl)."""
import re
import shutil
import subprocess
from pathlib import Path

from .proxy import proxy_flag

_YT_RE = re.compile(r"youtube\.com|youtu\.be")


def _unique_id() -> str:
    import time, os
    return f"{int(time.time())}_{os.getpid()}"


def download(url: str, tmp_dir: Path, proxies: list[str], start: str = "", end: str = "") -> tuple[Path, bool]:
    """Return (path, trimmed) where trimmed=True if already cut to start/end."""
    tmp_dir.mkdir(parents=True, exist_ok=True)
    uid = _unique_id()
    if _YT_RE.search(url):
        return _download_youtube(url, tmp_dir, uid, proxies, start, end)
    return _download_generic(url, tmp_dir, uid, proxies), False


def _has_feature(tool: str, pattern: str) -> bool:
    try:
        out = subprocess.run([tool, "--help"], capture_output=True, text=True).stdout
        return pattern in out
    except FileNotFoundError:
        return False


def _download_youtube(url, tmp_dir, uid, proxies, start, end) -> tuple[Path, bool]:
    if shutil.which("yt-dlp") is None:
        raise RuntimeError("[ERROR] yt-dlp not found. Install: yt-dlp")
    print("[INFO] Downloading video...")
    section = ""
    trimmed = False
    if start and end:
        if _has_feature("yt-dlp", "download-sections"):
            section = f"--download-sections *{start}-{end}"
            trimmed = True
    proxy = proxy_flag(proxies)
    cmd = [
        "yt-dlp", "--restrict-filenames",
        "--print", "after_move:filepath",
        "--merge-output-format", "mp4",
        "--sleep-requests", "3", "--retries", "3", "--socket-timeout", "30",
        "--downloader-args",
        "ffmpeg_i:-reconnect 1 -reconnect_streamed 1 -reconnect_delay_max 5",
        "-f", "bv*[height<=720][height>=360]+ba/b[height<=720][height>=360]",
        *section.split(), *proxy.split(),
        "-o", f"{tmp_dir}/{uid}_%(title)s.%(ext)s", url,
    ]
    res = subprocess.run(cmd, capture_output=True, text=True)
    if res.returncode != 0:
        raise RuntimeError("[ERROR] Failed to download YouTube video")
    return Path(res.stdout.splitlines()[-1].strip()), trimmed


def _download_generic(url, tmp_dir, uid, proxies) -> Path:
    print("[INFO] Downloading input...")
    dest = tmp_dir / f"tmp_input_{uid}.mp4"
    proxy = proxy_flag(proxies)
    cmd = ["curl", "-fsSL", *proxy.split(), "-o", str(dest), url]
    res = subprocess.run(cmd)
    if res.returncode != 0:
        raise RuntimeError("[ERROR] Failed to download URL")
    return dest
