#!/usr/bin/env python3

from pathlib import Path
import sys


def der_length(n: int) -> bytes:
    if n < 128:
        return bytes([n])
    raw = n.to_bytes((n.bit_length() + 7) // 8, "big")
    return bytes([0x80 | len(raw)]) + raw


def item(tag: int, data: bytes) -> bytes:
    return bytes([tag]) + der_length(len(data)) + data


def ia5(value: str) -> bytes:
    return item(0x16, value.encode("ascii"))


def read_length(data: bytes, offset: int) -> tuple[int, int]:
    first = data[offset]
    offset += 1
    if first < 128:
        return first, offset
    width = first & 0x7F
    return int.from_bytes(data[offset : offset + width], "big"), offset + width


def main() -> None:
    source, output = map(Path, sys.argv[1:3])
    data = source.read_bytes()
    if not data or data[0] != 0x30:
        raise SystemExit("trust cache is not a DER sequence")
    total, offset = read_length(data, 1)
    end = offset + total
    octets = None
    while offset < end:
        tag = data[offset]
        length, value_offset = read_length(data, offset + 1)
        value = data[value_offset : value_offset + length]
        offset = value_offset + length
        if tag == 0x04:
            octets = value
    if octets is None:
        raise SystemExit("trust cache DER contains no octet string")
    body = ia5("IM4P") + ia5("gtcd") + ia5("1") + item(0x04, octets)
    output.write_bytes(item(0x30, body))


if __name__ == "__main__":
    main()

