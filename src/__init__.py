"""src: modular video clip generator."""
from .config import Config, OUTPUT_DIR, TMP_DIR, FONT_PATH, MODEL_PATH
from .args import Options, parse

__all__ = ["Config", "Options", "parse", "OUTPUT_DIR", "TMP_DIR", "FONT_PATH", "MODEL_PATH"]
