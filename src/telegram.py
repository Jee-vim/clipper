"""Send finished clip to Telegram via curl."""
import subprocess
from pathlib import Path


def send_video(path: Path, token: str, chat_id: str) -> bool:
    if not token or not chat_id:
        return False
    cmd = [
        "curl", "-fsSL", "-X", "POST",
        f"https://api.telegram.org/bot{token}/sendVideo",
        "-F", f"chat_id={chat_id}", "-F", f"video=@{path}",
    ]
    res = subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return res.returncode == 0
