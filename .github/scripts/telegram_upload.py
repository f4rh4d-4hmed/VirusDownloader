#!/usr/bin/env python3
"""
Telegram upload script for VirusDownloader CI/CD artifacts
"""
import os
import sys
import html
import urllib.request
import urllib.parse
import urllib.error
import json
import lzma
import shutil
import subprocess
from datetime import datetime, timezone

for stream in (sys.stdout, sys.stderr):
    try:
        stream.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass

# ── Config ───────────────────────────────────────────────────────────────────
BOT_TOKEN = os.environ.get("TG_TOKEN", "").strip()
CHAT_ID   = os.environ.get("TG_CHAT_ID", "").strip() or "6779570748"
if not BOT_TOKEN:
    print("Warning: TG_TOKEN is not set; skipping Telegram upload.", file=sys.stderr)
    sys.exit(0)
API_BASE = f"https://api.telegram.org/bot{BOT_TOKEN}"

# Maximum file size for Telegram bot API (bytes)
TELEGRAM_MAX_BYTES = 50 * 1024 * 1024
TELEGRAM_PART_BYTES = 49 * 1024 * 1024

# ── Build metadata from env ───────────────────────────────────────────────────
commit_msg   = os.environ.get("COMMIT_MSG",    "N/A")
platform     = os.environ.get("PLATFORM",      "unknown")
triggered_by = os.environ.get("TRIGGERED_BY",  "unknown")
win_result   = os.environ.get("WIN_RESULT",    "skipped")
apk_result   = os.environ.get("APK_RESULT",    "skipped")
lnx_result   = os.environ.get("LNX_RESULT",    "skipped")
build_label  = os.environ.get("BUILD_LABEL",   "")
build_name   = os.environ.get("BUILD_NAME",     "")
build_number = os.environ.get("BUILD_NUMBER",   "")

EMOJI = {"success": "✅", "failure": "❌", "skipped": "⏭️", "cancelled": "🚫"}

# ── Helpers ───────────────────────────────────────────────────────────────────
def h(value: str) -> str:
    return html.escape(str(value), quote=False)

def status_line(label: str, result: str) -> str:
    icon = EMOJI.get(result, "❓")
    return f"{icon} {h(label)}: {h(result)}"

def tg_request(endpoint: str, data: dict) -> dict:
    url     = f"{API_BASE}/{endpoint}"
    payload = json.dumps(data).encode("utf-8")
    req     = urllib.request.Request(
        url, data=payload, headers={"Content-Type": "application/json"}
    )
    try:
        with urllib.request.urlopen(req) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        body   = exc.read().decode("utf-8", errors="replace") if exc.fp else ""
        detail = body
        try:
            parsed = json.loads(body) if body else {}
            detail = parsed.get("description") or body
        except Exception:
            pass
        raise RuntimeError(f"Telegram API {exc.code} {exc.reason}: {detail}") from exc

def send_message(text: str, parse_mode: str | None = "HTML") -> dict:
    payload: dict = {"chat_id": CHAT_ID, "text": text}
    if parse_mode:
        payload["parse_mode"] = parse_mode
    return tg_request("sendMessage", payload)

def send_message_safe(text: str) -> None:
    try:
        res = send_message(text, parse_mode="HTML")
        if not res.get("ok"):
            raise RuntimeError(str(res))
    except Exception as exc:
        err = str(exc)
        if "can't parse entities" in err or "Bad Request" in err:
            plain = html.unescape(text).replace("<b>", "").replace("</b>", "")
            res   = send_message(plain, parse_mode=None)
            if not res.get("ok"):
                print(f"Error sending plain-text fallback: {res}", file=sys.stderr)
                sys.exit(1)
        else:
            print(f"Error sending message: {exc}", file=sys.stderr)
            sys.exit(1)

def send_document(file_path: str, caption: str = "") -> dict:
    import mimetypes
    filename = os.path.basename(file_path)
    mime     = mimetypes.guess_type(filename)[0] or "application/octet-stream"

    size = os.path.getsize(file_path)
    if size > TELEGRAM_MAX_BYTES:
        raise RuntimeError(
            f"File is too large for Telegram bot API ({size} bytes). "
            "Telegram limits bot uploads to 50 MB."
        )

    try:
        import requests  # type: ignore
    except Exception:
        requests = None

    if requests:
        url = f"{API_BASE}/sendDocument"
        data = {"chat_id": CHAT_ID}
        if caption:
            data["caption"] = caption
            data["parse_mode"] = "HTML"
        with open(file_path, "rb") as f:
            files = {"document": (filename, f, mime)}
            resp = requests.post(url, data=data, files=files, timeout=300)
        try:
            res = resp.json()
        except Exception:
            raise RuntimeError(f"Failed to decode Telegram response: {resp.status_code} {resp.text}")
        if not res.get("ok"):
            raise RuntimeError(f"Telegram API error: {res}")
        return res

    boundary = "----FormBoundary7MA4YWxkTrZu0gW"

    def field(name: str, value: str) -> bytes:
        return (
            f"--{boundary}\r\n"
            f'Content-Disposition: form-data; name="{name}"\r\n\r\n'
            f"{value}\r\n"
        ).encode("utf-8")

    parts = [field("chat_id", str(CHAT_ID))]
    if caption:
        parts.append(field("caption", caption))
        parts.append(field("parse_mode", "HTML"))

    with open(file_path, "rb") as f:
        file_data = f.read()

    parts.append(
        (
            f"--{boundary}\r\n"
            f'Content-Disposition: form-data; name="document"; filename="{filename}"\r\n'
            f"Content-Type: {mime}\r\n\r\n"
        ).encode("utf-8")
        + file_data
        + b"\r\n"
    )
    parts.append(f"--{boundary}--\r\n".encode("utf-8"))
    body = b"".join(parts)

    url = f"{API_BASE}/sendDocument"
    req = urllib.request.Request(url, data=body, headers={
        "Content-Type": f"multipart/form-data; boundary={boundary}",
    })
    with urllib.request.urlopen(req) as resp:
        return json.loads(resp.read().decode("utf-8"))

def base_caption(filename: str, size_mb: float, now_utc: str, note: str = "") -> str:
    label_line = f"🏷️ {h(build_label)}\n" if build_label else ""
    version_line = f"🔖 <b>v{h(build_name)}</b> (build {h(build_number)})\n" if build_name else ""
    note_line = f"\n{h(note)}" if note else ""
    return (
        f"🔨 <b>VirusDownloader Build Ready</b>\n"
        f"{label_line}"
        f"{version_line}"
        f"📦 <b>{h(filename)}</b>\n"
        f"📏 {size_mb:.1f} MB\n"
        f"🕐 {h(now_utc)}\n"
        f"👤 {h(triggered_by)}\n"
        f"💬 {h(commit_msg)}"
        f"{note_line}"
    )

def compress_xz(file_path: str) -> str:
    out = f"{file_path}.xz"
    filename = os.path.basename(file_path)
    xz_bin = shutil.which("xz")
    if xz_bin:
        print(f"Compressing {filename} with system xz (-T0 -5)...")
        try:
            subprocess.run([xz_bin, "-T0", "-5", "-k", "-f", file_path], check=True)
            if os.path.isfile(out):
                return out
        except Exception as exc:
            print(f"System xz failed ({exc}), falling back to Python lzma...")

    print(f"Compressing {filename} with LZMA preset 5...")
    with open(file_path, "rb") as fin, lzma.open(out, "wb", preset=5) as fout:
        shutil.copyfileobj(fin, fout, length=1024 * 1024)
    return out

def split_file(file_path: str, part_size: int | None = None) -> list[str]:
    part_size = part_size or TELEGRAM_PART_BYTES
    parts: list[str] = []
    index = 1
    with open(file_path, "rb") as fin:
        while True:
            chunk = fin.read(part_size)
            if not chunk:
                break
            part = f"{file_path}.part{index:02d}"
            with open(part, "wb") as fout:
                fout.write(chunk)
            parts.append(part)
            index += 1
    return parts

def upload_document_or_fail(file_path: str, caption: str) -> None:
    filename = os.path.basename(file_path)
    size_mb = os.path.getsize(file_path) / (1024 * 1024)
    print(f"Uploading {filename} ({size_mb:.1f} MB) to Telegram...")
    res = send_document(file_path, caption=caption)
    if res.get("ok"):
        print(f"✅ {filename} uploaded successfully.")
        return
    raise RuntimeError(f"Upload failed: {res}")

def run_summary() -> None:
    now_utc = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M UTC")
    lines = [
        "📋 <b>VirusDownloader Build Summary</b>",
        "",
        f"🕐 <b>Date/Time:</b> {h(now_utc)}",
        f"📦 <b>Platform:</b> {h(platform)}",
        f"👤 <b>Triggered by:</b> {h(triggered_by)}",
        f"💬 <b>Last commit:</b> {h(commit_msg)}",
        "",
        "<b>Build Results:</b>",
        status_line("Windows", win_result),
        status_line("Android", apk_result),
        status_line("Linux",   lnx_result),
    ]
    print("Sending build summary…")
    send_message_safe("\n".join(lines))
    print("Summary sent.")

def run_single_file(file_path: str) -> None:
    if not os.path.isfile(file_path):
        print(f"Error: file not found: {file_path}", file=sys.stderr)
        sys.exit(1)

    filename = os.path.basename(file_path)
    size_bytes = os.path.getsize(file_path)
    size_mb  = size_bytes / (1024 * 1024)
    now_utc  = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M UTC")

    try:
        if size_bytes <= TELEGRAM_MAX_BYTES:
            upload_document_or_fail(file_path, base_caption(filename, size_mb, now_utc))
            return

        compressed = compress_xz(file_path)
        compressed_name = os.path.basename(compressed)
        compressed_size = os.path.getsize(compressed)
        compressed_mb = compressed_size / (1024 * 1024)
        if compressed_size <= TELEGRAM_MAX_BYTES:
            upload_document_or_fail(
                compressed,
                base_caption(
                    compressed_name,
                    compressed_mb,
                    now_utc,
                    note=f"Compressed from {filename} ({size_mb:.1f} MB).",
                ),
            )
            return

        parts = split_file(compressed)
        if not parts:
            raise RuntimeError(f"Could not split compressed artifact: {compressed}")

        send_message_safe(
            "📦 <b>VirusDownloader Build Artifact Split for Telegram</b>\n"
            f"{f'🏷️ {h(build_label)}' if build_label else ''}\n"
            f"Original: <b>{h(filename)}</b> ({size_mb:.1f} MB)\n"
            f"Compressed: <b>{h(compressed_name)}</b> ({compressed_mb:.1f} MB)\n"
            f"Parts: {len(parts)}\n"
            "Reassemble with: <code>cat *.part* &gt; artifact.xz</code>"
        )
        for index, part in enumerate(parts, start=1):
            part_name = os.path.basename(part)
            part_mb = os.path.getsize(part) / (1024 * 1024)
            upload_document_or_fail(
                part,
                base_caption(
                    part_name,
                    part_mb,
                    now_utc,
                    note=f"Part {index}/{len(parts)} of compressed {filename}.",
                ),
            )
    except Exception as exc:
        print(f"❌ Exception uploading {filename}: {exc}", file=sys.stderr)
        sys.exit(1)

if __name__ == "__main__":
    args = sys.argv[1:]

    if not args or args[0] == "--summary":
        run_summary()
    else:
        run_single_file(args[0])

