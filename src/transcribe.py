"""Audio extraction + whisper transcription + ASS build."""
import shutil
import subprocess
from pathlib import Path

from .subtitles import build_ass


class SkipTranscription(Exception):
    pass


def extract_audio(input_path: Path, audio_path: Path, seek: str) -> None:
    cmd = [
        "ffmpeg", "-y", "-hide_banner", "-stats",
        *seek.split(), "-i", str(input_path),
        "-ar", "16000", "-ac", "1", "-c:a", "pcm_s16le", str(audio_path),
    ]
    res = subprocess.run(cmd)
    if res.returncode != 0:
        raise RuntimeError("[ERROR] Failed to extract audio")


def transcribe(input_path: Path, base: Path, model: Path, seek: str) -> Path | None:
    """Return ASS path if subtitles generated, else None."""
    if shutil.which("whisper-cli") is None:
        print("[WARN] whisper-cpp not found. Skipping subtitles.")
        return None
    if not model.is_file():
        print(f"[WARN] GGML model not found at {model}. Skipping subtitles.")
        return None

    print("[INFO] Extracting audio and Transcribing...")
    audio = base.with_suffix(".wav")
    extract_audio(input_path, audio, seek)

    json_file = base.with_suffix(".json")
    log = base.parent / "whisper.log"
    cmd = [
        "whisper-cli", "-m", str(model), "-f", str(audio),
        "-osrt", "-ojf", "-of", str(base), "-np",
    ]
    res = subprocess.run(cmd, stdout=log.open("w"), stderr=subprocess.STDOUT)
    if res.returncode != 0:
        print(f"[WARN] Whisper transcription failed, check {log}")
        return None
    log.unlink(missing_ok=True)

    if not json_file.is_file():
        print("[WARN] JSON file not created")
        return None

    ass = base.with_suffix(".ass")
    build_ass(json_file, ass)
    json_file.unlink(missing_ok=True)
    return ass if ass.is_file() else None
