"""Gemini (Google AI Studio) script generation.

Takes a topic and returns a podcast-style script that
feeds straight into the TTS pipeline. Uses only the stdlib urllib so no extra
dependency is required.
"""
import json
import re
import urllib.error
import urllib.request
from pathlib import Path

GEN_URL = "https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent"
DEFAULT_MODEL = "gemini-2.5-flash"

DEFAULT_SYSTEM_PROMPT = (
    "Write a short podcast-style monologue explaining [TOPIC].\n"
    "\n"
    "Make the script around 30-60 seconds when spoken naturally.\n"
    "\n"
    "Style:\n"
    "Start immediately with a natural question about the topic.\n"
    "After asking the question, smoothly jump into the explanation yourself.\n"
    "Make it sound like someone casually explaining something to a friend, not giving a formal presentation.\n"
    "The speaker should sound curious and conversational, as if they are asking a question and then explaining the answer.\n"
    "Use natural transitions such as \u201cSo, what exactly is...?\u201d, \u201cBut how does that work?\u201d, \u201cBasically...\u201d, \u201cThe simple way to think about it is...\u201d, or \u201cIn other words...\u201d.\n"
    "Keep the language simple and easy to understand for someone who knows almost nothing about the topic.\n"
    "Avoid professional, academic, or overly technical language.\n"
    "If a technical term is necessary, explain it immediately in simple words.\n"
    "Focus only on the most important points.\n"
    "Cut unnecessary details, examples, and explanations to stay within roughly 30 seconds.\n"
    "Keep sentences short and natural for speaking.\n"
    "Don't force jokes or overly dramatic lines.\n"
    "End with a controversial take, a bold opinion, or a direct provocative question that forces listeners to drop their opinions in the comments section.\n"
    "\n"
    "Formatting:\n"
    "Output ONLY plain text.\n"
    "Do NOT use Markdown.\n"
    "Do NOT use headings, bullet points, bold text, or quotation marks.\n"
    "Write one sentence per line.\n"
    "\n"
    "Formatting:\n"
    "Output ONLY plain text.\n"
    "Do NOT use Markdown.\n"
    "Do NOT use headings, bullet points, bold text, or quotation marks.\n"
)

_FENCE_RE = re.compile(r"^```[a-zA-Z]*\s*|\s*```$", re.MULTILINE)


def _build_body(topic: str, system_prompt: str) -> dict:
    system = system_prompt.replace("[TOPIC]", topic)
    return {
        "systemInstruction": {"parts": [{"text": system}]},
        "contents": [{"role": "user", "parts": [{"text": f"Write the script about: {topic}"}]}],
        "generationConfig": {"temperature": 0.8},
    }


def _extract_text(data: dict) -> str:
    try:
        text = data["candidates"][0]["content"]["parts"][0]["text"]
    except (KeyError, IndexError, TypeError) as exc:
        raise RuntimeError(f"[ERROR] Unexpected Gemini response: {exc}") from exc
    if not text.strip():
        raise RuntimeError("[ERROR] Gemini returned an empty script")
    return _FENCE_RE.sub("", text).strip() + "\n"


def generate_script(
    topic: str, *, api_key: str, model: str = DEFAULT_MODEL,
    system_prompt: str = DEFAULT_SYSTEM_PROMPT, out_dir: Path,
) -> Path:
    """Generate a script .txt from a topic. Returns the script path."""
    if not topic or not topic.strip():
        raise ValueError("[ERROR] Topic must not be empty")
    if not api_key:
        raise ValueError("[ERROR] GEMINI_API_KEY not set in environment/.env")

    body = json.dumps(_build_body(topic, system_prompt)).encode()
    url = f"{GEN_URL.format(model=model)}?key={api_key}"
    req = urllib.request.Request(
        url, data=body, headers={"Content-Type": "application/json"}, method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=90) as resp:
            data = json.loads(resp.read().decode())
    except urllib.error.HTTPError as exc:
        raise RuntimeError(
            f"[ERROR] Gemini API error {exc.code}: {exc.read().decode()[:200]}"
        ) from exc
    except urllib.error.URLError as exc:
        raise RuntimeError(f"[ERROR] Gemini request failed: {exc.reason}") from exc

    text = _extract_text(data)
    from . import timeutils
    out = out_dir / f"story_{timeutils.safe_name(topic)}.txt"
    out.write_text(text, encoding="utf-8")
    return out
