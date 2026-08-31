#!/usr/bin/env python3
"""SplitShare waitlist landing page — serves the site and stores emails locally."""

from __future__ import annotations

import json
import re
import sys
import threading
from datetime import datetime, timezone
from http import HTTPStatus
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse

ROOT = Path(__file__).resolve().parent
DATA_FILE = ROOT / "data" / "waitlist.json"
EMAIL_RE = re.compile(r"^[^\s@]+@[^\s@]+\.[^\s@]+$")
LOCK = threading.Lock()
HOST = "0.0.0.0"
PORT = 8080


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def load_waitlist() -> dict:
    if not DATA_FILE.exists():
        return {"emails": []}
    try:
        return json.loads(DATA_FILE.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return {"emails": []}


def save_waitlist(payload: dict) -> None:
    DATA_FILE.parent.mkdir(parents=True, exist_ok=True)
    tmp = DATA_FILE.with_suffix(".tmp")
    tmp.write_text(json.dumps(payload, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    tmp.replace(DATA_FILE)


class WaitlistHandler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(ROOT), **kwargs)

    def log_message(self, format: str, *args) -> None:
        sys.stderr.write("%s - %s\n" % (self.address_string(), format % args))

    def _json(self, status: int, payload: dict) -> None:
        body = json.dumps(payload).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self) -> None:
        path = urlparse(self.path).path
        if path == "/api/waitlist":
            with LOCK:
                count = len(load_waitlist().get("emails", []))
            self._json(HTTPStatus.OK, {"count": count})
            return
        if path == "/":
            self.path = "/index.html"
        super().do_GET()

    def do_POST(self) -> None:
        path = urlparse(self.path).path
        if path != "/api/waitlist":
            self._json(HTTPStatus.NOT_FOUND, {"error": "Nicht gefunden."})
            return

        length = int(self.headers.get("Content-Length", "0") or 0)
        if length > 2048:
            self._json(HTTPStatus.REQUEST_ENTITY_TOO_LARGE, {"error": "Anfrage zu groß."})
            return

        raw = self.rfile.read(length) if length else b"{}"
        try:
            data = json.loads(raw.decode("utf-8"))
        except (json.JSONDecodeError, UnicodeDecodeError):
            self._json(HTTPStatus.BAD_REQUEST, {"error": "Ungültige Anfrage."})
            return

        email = str(data.get("email", "")).strip().lower()
        if not EMAIL_RE.match(email) or len(email) > 254:
            self._json(HTTPStatus.BAD_REQUEST, {"error": "Bitte eine gültige E-Mail eingeben."})
            return

        with LOCK:
            payload = load_waitlist()
            emails = payload.setdefault("emails", [])
            if any(entry.get("email") == email for entry in emails):
                self._json(HTTPStatus.CONFLICT, {"alreadyJoined": True, "count": len(emails)})
                return
            emails.append({"email": email, "createdAt": utc_now()})
            save_waitlist(payload)
            count = len(emails)

        self._json(HTTPStatus.CREATED, {"ok": True, "count": count})


def main() -> None:
    DATA_FILE.parent.mkdir(parents=True, exist_ok=True)
    if not DATA_FILE.exists():
        save_waitlist({"emails": []})

    server = ThreadingHTTPServer((HOST, PORT), WaitlistHandler)
    print(f"SplitShare Waitlist läuft auf http://127.0.0.1:{PORT}")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nServer gestoppt.")
        server.server_close()


if __name__ == "__main__":
    main()
