#!/usr/bin/env python3

from pathlib import Path
import sys


def der_length(length: int) -> bytes:
    if length < 128:
        return bytes([length])
    raw = length.to_bytes((length.bit_length() + 7) // 8, "big")
    return bytes([0x80 | len(raw)]) + raw


def item(tag: int, value: bytes) -> bytes:
    return bytes([tag]) + der_length(len(value)) + value


def ia5(value: str) -> bytes:
    return item(0x16, value.encode("ascii"))


def main() -> None:
    if len(sys.argv) != 3:
        raise SystemExit("usage: wrap-volume.py INPUT OUTPUT")
    source, output = map(Path, sys.argv[1:])
    metadata = source.read_bytes()
    if len(metadata) < 48 or not any(metadata):
        raise SystemExit("APFS seal metadata is missing or invalid")
    body = ia5("IM4P") + ia5("gtgv") + ia5("0") + item(0x04, metadata)
    output.write_bytes(item(0x30, body))


if __name__ == "__main__":
    main()
