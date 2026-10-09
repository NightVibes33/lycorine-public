#!/usr/bin/env python3
from __future__ import annotations

import pathlib
import sys


def paragraphs(text: str) -> list[str]:
    return [part.strip() for part in text.split("\n\n") if part.strip()]


def field(paragraph: str, name: str) -> str | None:
    prefix = f"{name}:"
    for line in paragraph.splitlines():
        if line.startswith(prefix):
            return line[len(prefix) :].strip()
    return None


def main() -> None:
    if len(sys.argv) != 4:
        raise SystemExit("usage: update-dpkg-status.py STATUS CONTROL STATE")
    status_path = pathlib.Path(sys.argv[1])
    control_path = pathlib.Path(sys.argv[2])
    state = sys.argv[3]
    control = control_path.read_text(encoding="utf-8").strip()
    package = field(control, "Package")
    if not package:
        raise SystemExit("control file has no Package field")

    existing = paragraphs(status_path.read_text(encoding="utf-8"))
    existing = [p for p in existing if field(p, "Package") != package]
    control_lines = [line for line in control.splitlines() if not line.startswith("Status:")]
    control_lines.append(f"Status: install ok {state}")
    existing.append("\n".join(control_lines))
    status_path.write_text("\n\n".join(existing) + "\n\n", encoding="utf-8")


if __name__ == "__main__":
    main()
