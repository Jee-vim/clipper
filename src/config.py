"""Paths, environment, and runtime configuration."""
import os
from dataclasses import dataclass, field
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent.parent
OUTPUT_DIR = SCRIPT_DIR / "output"
TMP_DIR = SCRIPT_DIR / "tmp"
FONT_PATH = SCRIPT_DIR / "input" / "font" / "coolvetica.ttf"
MODEL_PATH = Path.home() / ".cache" / "whisper-models" / "ggml-medium.bin"


def load_env(path: Path = SCRIPT_DIR / ".env") -> None:
    """Source a simple KEY=VALUE .env file into os.environ (no export)."""
    if not path.is_file():
        return
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, val = line.partition("=")
        os.environ.setdefault(key.strip(), val.strip())


@dataclass
class Config:
    output_dir: Path = OUTPUT_DIR
    tmp_dir: Path = TMP_DIR
    font_path: Path = FONT_PATH
    model_path: Path = MODEL_PATH
    proxies: list[str] = field(default_factory=list)
    telegram_token: str = ""
    telegram_chat_id: str = ""

    @classmethod
    def from_env(cls) -> "Config":
        load_env()
        proxies = [p.strip() for p in os.environ.get("PROXIES", "").split(",") if p.strip()]
        return cls(
            proxies=proxies,
            telegram_token=os.environ.get("TELEGRAM_TOKEN", ""),
            telegram_chat_id=os.environ.get("TELEGRAM_CHAT_ID", ""),
        )
