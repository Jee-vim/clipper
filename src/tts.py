"""TTS story generator (Chatterbox, local + free).

Turns a plain-text script into a single audio file. The heavy ML imports
(torch/chatterbox) are lazy so video-only runs of the parent CLI stay light.

Script format (one sentence per line):
    spoken text

A .srt file may also be used instead of .txt. The SRT timing cues drive the
playback speed (atempo) of each segment so the generated audio matches the
script's cadence.
"""
import os
import re
import shutil
import subprocess
import tempfile
from pathlib import Path

def resolve_ref(
    speaker: str, ref_a: Path | None, ref_b: Path | None
) -> Path | None:
    if speaker == "A":
        return ref_a
    if speaker == "B":
        return ref_b
    return None

LINE_RE = re.compile(r"^([A-Za-z]+):[ \t]*(.*)$")
SPEAKER_PREFIX_RE = re.compile(r"^([A-Za-z]+):[ \t]*")
SRT_RE = re.compile(
    r"(\d{2}):(\d{2}):(\d{2}),(\d{3})\s*-->\s*"
    r"(\d{2}):(\d{2}):(\d{2}),(\d{3})"
)


def log(level: str, msg: str) -> None:
    print(f"[{level}] {msg}")


def validate_assets(ref_a: Path | None, ref_b: Path | None) -> None:
    for path in (ref_a, ref_b):
        if path and not Path(path).is_file():
            log("ERROR", f"Reference audio not found: {path}")
            raise SystemExit(1)


def _srt_time_to_sec(h: str, m: str, s: str, ms: str) -> float:
    return int(h) * 3600 + int(m) * 60 + int(s) + int(ms) / 1000.0


def _parse_srt_cues(path: Path) -> list[tuple[float, float, str]]:
    cues: list[tuple[float, float, str]] = []
    text = Path(path).read_text(encoding="utf-8").strip()
    for block in re.split(r"\n\s*\n", text):
        lines = [l for l in block.splitlines() if l.strip()]
        if len(lines) < 2:
            continue
        tc_idx = next(
            (i for i, l in enumerate(lines) if SRT_RE.search(l)), None
        )
        if tc_idx is None:
            continue
        m = SRT_RE.search(lines[tc_idx])
        start = _srt_time_to_sec(*m.group(1, 2, 3, 4))
        end = _srt_time_to_sec(*m.group(5, 6, 7, 8))
        spoken = "\n".join(lines[tc_idx + 1:]).strip()
        if not spoken or not end > start:
            continue
        cues.append((start, end, spoken))
    return cues


def ref_for_line(
    text: str, ref_a: Path | None, ref_b: Path | None
) -> Path | None:
    m = LINE_RE.match(text)
    if m and m.group(1) in ("A", "B"):
        return resolve_ref(m.group(1), ref_a, ref_b)
    return ref_a


def _min_cue_dur(text: str, cps: float = 14.0, floor: float = 2.0) -> float:
    return max(floor, len(text) / cps)


def _normalize_cues(
    cues: list[tuple[float, float, str]],
) -> list[tuple[float, float, str]]:
    out: list[tuple[float, float, str]] = []
    cursor: float | None = None
    for start, end, text in cues:
        dur = end - start
        need = max(dur, _min_cue_dur(text))
        ns = start if cursor is None else max(start, cursor)
        ne = ns + need
        out.append((ns, ne, text))
        cursor = ne
    return out


def _sec_to_srt_time(sec: float) -> str:
    sec = max(0.0, float(sec))
    h = int(sec // 3600)
    m = int(sec % 3600 // 60)
    s = int(sec % 60)
    ms = int(round((sec - int(sec)) * 1000))
    if ms >= 1000:
        ms = 999
    return f"{h:02d}:{m:02d}:{s:02d},{ms:03d}"


def _speed_wav(in_path: Path, out_path: Path, target_dur: float) -> None:
    import torchaudio

    info = torchaudio.info(str(in_path))
    cur = info.num_frames / info.sample_rate
    if cur <= 0 or abs(cur - target_dur) < 0.001:
        if in_path != out_path:
            shutil.copy(in_path, out_path)
        return
    f = target_dur / cur
    parts: list[float] = []
    while f > 2.0:
        parts.append(2.0)
        f /= 2.0
    while f < 0.5:
        parts.append(0.5)
        f /= 0.5
    parts.append(f)
    chain = ",".join(f"atempo={p:.4f}" for p in parts)
    cmd = [
        "ffmpeg", "-y", "-i", str(in_path), "-af", chain, str(out_path),
    ]
    res = subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    if res.returncode != 0:
        log("ERROR", "ffmpeg atempo failed")
        raise SystemExit(1)


def _sec_to_ass_time(sec: float) -> str:
    sec = max(0.0, float(sec))
    h = int(sec // 3600)
    m = int(sec % 3600 // 60)
    s = int(sec % 60)
    cs = int(round((sec - int(sec)) * 100))
    if cs >= 100:
        cs = 99
    return f"{h:02d}:{m:02d}:{s:02d}.{cs:02d}"


def _split_words(
    start: float, end: float, spoken: str
) -> list[tuple[float, float, str]]:
    """Spread a cue's duration across its words for a progressive reveal."""
    words = spoken.split()
    if len(words) <= 1:
        return [(start, end, spoken)]
    weights = [len(w) + 1 for w in words]
    total = sum(weights)
    out: list[tuple[float, float, str]] = []
    cursor = 0.0
    for i, w in enumerate(words):
        ws = start + (end - start) * cursor / total
        cursor += weights[i]
        out.append((ws, end, " ".join(words[: i + 1])))
    return out


_ASS_HEADER = (
    "[Script Info]\n"
    "ScriptType: v4.00+\n"
    "PlayResX: 384\n"
    "PlayResY: 288\n"
    "ScaledBorderAndShadow: yes\n"
    "\n"
    "[V4+ Styles]\n"
    "Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, "
    "OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, "
    "ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, "
    "Alignment, MarginL, MarginR, MarginV, Encoding\n"
    "Style: Default,Arial,16,&H00FFFFFF,&H000000FF,&H00000000,"
    "&H64000000,0,0,0,0,100,100,0,0,1,2,1,2,10,10,10,1\n"
    "\n"
    "[Events]\n"
    "Format: Layer, Start, End, Style, Name, MarginL, MarginR, "
    "MarginV, Effect, Text\n"
)


def srt_to_ass(srt_path: Path, ass_path: Path) -> Path:
    """Convert a script .srt into an .ass with word-by-word reveal."""
    cues = _parse_srt_cues(srt_path)
    if not cues:
        log("ERROR", f"No valid cues found in {srt_path}")
        raise SystemExit(1)
    events: list[str] = []
    for s, e, spoken in cues:
        for ws, we, text in _split_words(s, e, spoken):
            events.append(
                f"Dialogue: 0,"
                f"{_sec_to_ass_time(ws)},"
                f"{_sec_to_ass_time(we)},"
                f"Default,,0,0,0,,{text}"
            )
    with open(ass_path, "w", encoding="utf-8") as fh:
        fh.write(_ASS_HEADER + "\n".join(events) + "\n")
    return ass_path


def to_mp3(wav_path: Path, output: Path) -> None:
    if not shutil.which("ffmpeg"):
        log("ERROR", "ffmpeg not found in PATH")
        raise SystemExit(1)
    cmd = [
        "ffmpeg", "-y", "-i", str(wav_path),
        "-c:a", "libmp3lame", "-q:a", "2", str(output),
    ]
    res = subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    if res.returncode != 0:
        log("ERROR", "ffmpeg mp3 encode failed")
        raise SystemExit(1)


def generate_story(
    script: Path,
    output: Path,
    *,
    device: str = "cpu",
    ref_a: Path | None = None,
    ref_b: Path | None = None,
    exaggeration: float = 0.5,
    temperature: float = 0.8,
) -> Path:
    """Generate an MP3 podcast from a script file. Returns output path."""
    import torch
    import torchaudio
    import perth
    from chatterbox.tts import ChatterboxTTS

    class _NoWatermarker:
        def apply_watermark(self, wav, sample_rate=None, **kwargs):
            return wav

    if getattr(perth, "PerthImplicitWatermarker", None) is None:
        perth.PerthImplicitWatermarker = _NoWatermarker

    script = Path(script)
    output = Path(output)
    validate_assets(ref_a, ref_b)

    if not script.is_file():
        log("ERROR", f"Input file not found: {script}")
        raise SystemExit(1)

    if not ref_a and not ref_b:
        log("WARN", "No reference clips given: both speakers use the default voice")

    log("INFO", f"Loading Chatterbox on device={device}")
    model = ChatterboxTTS.from_pretrained(device=device)
    sr = model.sr

    segs: list = []
    idx = 0
    skipped = 0
    is_srt = script.suffix.lower() == ".srt"

    if is_srt:
        raw = _parse_srt_cues(script)
        if not raw:
            log("ERROR", f"No valid cues found in {script}")
            raise SystemExit(1)
        for s, e, spoken in raw:
            if e - s < _min_cue_dur(spoken):
                log("WARN", f"Widening cue to fit natural speech: {spoken[:40]}...")
        cues = _normalize_cues(raw)
        tmpd = tempfile.mkdtemp(prefix="tts_story_")
        try:
            prev_end = 0.0
            for i, (start, end, spoken) in enumerate(cues):
                gap = start - prev_end
                if gap > 0:
                    segs.append(torch.zeros(int(sr * gap)).unsqueeze(0))
                tts_text = SPEAKER_PREFIX_RE.sub("", spoken)
                ref = ref_for_line(tts_text, ref_a, ref_b)
                wav = model.generate(
                    tts_text,
                    audio_prompt_path=ref,
                    exaggeration=exaggeration,
                    temperature=temperature,
                )
                raw_wav = Path(tmpd) / f"raw_{i}.wav"
                adj_wav = Path(tmpd) / f"adj_{i}.wav"
                torchaudio.save(raw_wav, wav.cpu(), sr)
                _speed_wav(raw_wav, adj_wav, end - start)
                segs.append(torchaudio.load(adj_wav)[0])
                idx += 1
                log("INFO", f"Cue {idx} ({start:.2f}-{end:.2f}s) rendered")
                prev_end = end
        finally:
            shutil.rmtree(tmpd, ignore_errors=True)
    else:
        gap = torch.zeros(int(sr * 0.35)).unsqueeze(0)
        with open(script, encoding="utf-8") as fh:
            for raw in fh:
                line = raw.rstrip("\n")
                if not line.strip():
                    continue
                text = line.strip()
                if not text:
                    continue

                ref = ref_a
                wav = model.generate(
                    text,
                    audio_prompt_path=ref,
                    exaggeration=exaggeration,
                    temperature=temperature,
                )
                if segs:
                    segs.append(gap)
                segs.append(wav)
                idx += 1
                label = os.path.basename(ref) if ref else "default"
                log("INFO", f"Segment {idx} ({label}) written")

    if idx == 0:
        log("ERROR", f"No valid dialogue segments found in {script}")
        raise SystemExit(1)

    combined = torch.cat(segs, dim=1)
    tmp_wav = output.with_name(output.stem + ".tmp.wav")
    torchaudio.save(tmp_wav, combined.cpu(), sr)
    to_mp3(tmp_wav, output)
    tmp_wav.unlink(missing_ok=True)
    log("INFO", f"Audio ready: {output} (segments={idx}, skipped={skipped})")
    return output
