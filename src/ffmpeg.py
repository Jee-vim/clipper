"""FFmpeg filter construction and rendering."""
import subprocess
from pathlib import Path

CROP_FILTERS = {
    "left": "crop=iw*0.5:ih:0:0",
    "center": "crop=iw*0.5:ih:iw*0.25:0",
    "right": "crop=iw*0.5:ih:iw*0.5:0",
}

VIDEO_EXTS = (".mp4", ".mov", ".avi", ".mkv", ".webm", ".m4v")


def seek_args(start: str, end: str) -> str:
    if start and end:
        return f"-ss {start} -to {end}"
    return ""


def _watermark(font: Path, text: str) -> str:
    return (
        f"drawtext=text='{text}':fontcolor=white@0.5:fontsize=48:"
        f"x=(w-tw)/2:y=(h-th)/2:fontfile='{font}'"
    )


def _subtitle_filter(ass: Path) -> str:
    esc = str(ass).replace("\\", "\\\\").replace("'", "\\'").replace(":", "\\:")
    return (
        f"subtitles='{esc}':"
        "force_style='Fontname=DejaVuSans-Bold,Fontsize=80,PrimaryColour=&H00FFFF00'"
    )


def render(
    input_path: Path, output_path: Path, *,
    crop: str = "", watermark: str = "", font: Path, bg: Path | None = None,
    ass: Path | None = None, seek: str = "",
) -> int:
    if bg:
        return _render_with_bg(input_path, output_path, bg, crop, watermark, font, ass, seek)
    return _render_plain(input_path, output_path, crop, watermark, font, ass, seek)


def _common_filters(crop, watermark, font, ass):
    vf = []
    if crop:
        vf.append(CROP_FILTERS[crop])
    vf.append(
        "scale=1080:1920:force_original_aspect_ratio=decrease,"
        "pad=1080:1920:(ow-iw)/2:(oh-ih)/2:color=black"
    )
    vf.append(_watermark(font, watermark))
    if ass:
        vf.append(_subtitle_filter(ass))
    return ",".join(vf)


def _render_plain(input_path, output_path, crop, watermark, font, ass, seek) -> int:
    vf = _common_filters(crop, watermark, font, ass)
    cmd = [
        "ffmpeg", "-y", "-hide_banner", "-loglevel", "error",
        *seek.split(), "-i", str(input_path),
        "-vf", vf,
        "-c:v", "libx264", "-preset", "faster", "-crf", "23", "-pix_fmt", "yuv420p",
        "-c:a", "aac", "-b:a", "128k", str(output_path),
    ]
    return subprocess.run(cmd).returncode


def _render_with_bg(input_path, output_path, bg, crop, watermark, font, ass, seek) -> int:
    bg = bg.resolve()
    loop = "-stream_loop -1" if bg.suffix.lower() in VIDEO_EXTS else ""
    shortest = ":shortest=1" if loop else ""
    if loop:
        print("[INFO] Background is video - looping enabled")

    v_chain = "[0:v]"
    if crop:
        v_chain += CROP_FILTERS[crop] + ","
    v_chain += "scale=1080:1920:force_original_aspect_ratio=decrease[fg]"
    bg_chain = "[1:v]fps=30,scale=1080:1920:force_original_aspect_ratio=increase,crop=1080:1920[bg]"
    post = f"[bg][fg]overlay=(W-w)/2:(H-h)/2{shortest}"
    post += f",{_watermark(font, watermark)}"
    if ass:
        post += f",{_subtitle_filter(ass)}"
    post += "[vout]"
    fc = f"{v_chain};{bg_chain};{post}"

    cmd = [
        "ffmpeg", "-y", "-hide_banner", "-loglevel", "error",
        *seek.split(), "-i", str(input_path),
        *loop.split(), "-i", str(bg),
        "-filter_complex", fc,
        "-map", "[vout]", "-map", "0:a?", "-c:a", "aac", "-b:a", "128k",
        "-c:v", "libx264", "-preset", "faster", "-crf", "23", "-pix_fmt", "yuv420p",
        str(output_path),
    ]
    return subprocess.run(cmd).returncode
