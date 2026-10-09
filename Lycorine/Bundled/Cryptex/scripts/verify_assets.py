#!/usr/bin/env python3
"""Validate Cryptex1 build assets against local manifest digests.

This validates local file consistency, not an Apple Image4 signature, and it
cannot authorize custom cryptexes for a production iPhone.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import sys


def locate_bundle(folder: Path) -> Path:
    folder = folder.resolve()
    if (folder / "Restore" / "BuildManifest.plist").is_file():
        return folder
    found = [p for p in folder.iterdir() if p.is_dir() and
             (p / "Restore" / "BuildManifest.plist").is_file()]
    if len(found) != 1:
        raise ValueError(f"expected one Cryptex bundle with Restore/BuildManifest.plist in {folder}, got {len(found)}")
    return found[0].resolve()


def digest_file(path: Path, algorithm: str) -> str:
    digest = hashlib.new(algorithm)
    with path.open("rb") as f:
        for data in iter(lambda: f.read(1024 * 1024), b""):
            digest.update(data)
    return digest.hexdigest()


def analyze(folder: Path, required_variant: str | None, signed: bool) -> dict:
    bundle = locate_bundle(folder)
    restore = (bundle / "Restore").resolve()
    manifest_file = restore / "BuildManifest.plist"
    manifest = plistlib.loads(manifest_file.read_bytes())
    identities = manifest.get("BuildIdentities")
    if not isinstance(identities, list) or not identities:
        raise ValueError("BuildManifest has no BuildIdentities")
    if required_variant:
        identities = [i for i in identities
                      if i.get("Info", {}).get("Variant") == required_variant]
        if len(identities) != 1:
            raise ValueError(f"expected one {required_variant} build identity, found {len(identities)}")

    report = {"bundle": str(bundle), "manifest": str(manifest_file),
              "validation": "local SHA-384 asset integrity only, NOT signature validation",
              "has_ticket_file": False, "assets": []}
    for identity in identities:
        entries = identity.get("Manifest")
        if not isinstance(entries, dict) or not entries:
            raise ValueError("Build identity has no Manifest assets")
        for name, entry in entries.items():
            relative = entry.get("Info", {}).get("Path")
            expected = entry.get("Digest")
            if not isinstance(relative, str) or not isinstance(expected, bytes) or len(expected) != 48:
                raise ValueError(f"{name}: missing Path or SHA-384 digest")
            path = (restore / relative).resolve()
            if not path.is_relative_to(restore) or not path.is_file() or path.stat().st_size == 0:
                raise ValueError(f"{name}: absent, empty, or unsafe file path: {relative}")
            sha384 = digest_file(path, "sha384")
            if sha384 != expected.hex():
                raise ValueError(f"{name}: SHA-384 mismatch: {relative}")
            report["assets"].append({"name": name, "path": str(path),
                                     "bytes": path.stat().st_size, "sha384": sha384,
                                     "sha256": digest_file(path, "sha256")})

    # This is an inventory check, not proof that Apple actually signed the image.
    ticket_candidates = [p for p in bundle.rglob("im4m") if p.is_file() and p.stat().st_size]
    report["has_ticket_file"] = bool(ticket_candidates)
    if signed and not report["has_ticket_file"]:
        raise ValueError("bundle labelled as signed has no im4m ticket file")
    return report


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("bundle", type=Path)
    p.add_argument("--format", choices=("research",), default=None)
    p.add_argument("--signed", action="store_true")
    p.add_argument("--report", type=Path)
    args = p.parse_args()
    try:
        report = analyze(args.bundle, args.format, args.signed)
        rendered = json.dumps(report, indent=2, sort_keys=True) + "\n"
        if args.report:
            args.report.parent.mkdir(parents=True, exist_ok=True)
            args.report.write_text(rendered)
        print(rendered)
        return 0
    except (OSError, ValueError, KeyError, plistlib.InvalidFileException) as exc:
        print(f"Cryptex asset validation failed: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
