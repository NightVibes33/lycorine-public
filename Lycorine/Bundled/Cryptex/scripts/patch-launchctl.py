#!/usr/bin/env python3
"""Make launchctl's removed launch_active_user_switch import weak."""

import struct
import sys
from pathlib import Path


SYMBOL = b"_launch_active_user_switch"
WEAK_REF = 0x40


def unique(matches, kind):
    if len(matches) != 1:
        raise ValueError(f"expected one {kind} for {SYMBOL.decode()}, found {len(matches)}")
    return matches[0]


def patch(path):
    data = bytearray(path.read_bytes())
    if len(data) < 32:
        raise ValueError("short Mach-O header")
    magic, _, _, filetype, ncmds, sizeofcmds, _, _ = struct.unpack_from("<8I", data)
    if magic != 0xFEEDFACF or filetype != 2 or 32 + sizeofcmds > len(data):
        raise ValueError("expected a complete 64-bit Mach-O executable")

    commands = {}
    offset = 32
    for _ in range(ncmds):
        if offset + 8 > 32 + sizeofcmds:
            raise ValueError("truncated load command")
        command, size = struct.unpack_from("<2I", data, offset)
        if size < 8 or offset + size > 32 + sizeofcmds:
            raise ValueError("invalid load command")
        if command in (2, 0x80000034):
            if command in commands:
                raise ValueError("duplicate symbol or fixups command")
            commands[command] = offset
        offset += size
    if 2 not in commands or 0x80000034 not in commands:
        raise ValueError("missing symbol table or chained fixups")

    symoff, count, stroff, strsize = struct.unpack_from("<4I", data, commands[2] + 8)
    if symoff + count * 16 > len(data) or stroff + strsize > len(data):
        raise ValueError("symbol table out of bounds")
    names = data[stroff : stroff + strsize]
    matches = []
    for index in range(count):
        entry = symoff + index * 16
        nameoff, kind, _, description, value = struct.unpack_from("<IBBHQ", data, entry)
        if nameoff >= len(names):
            raise ValueError("symbol name out of bounds")
        if names[nameoff:].split(b"\0", 1)[0] == SYMBOL:
            if kind & 0x0E or not kind & 1 or value or description & WEAK_REF:
                raise ValueError("symbol is not a strong undefined import")
            matches.append((entry, description))
    entry, description = unique(matches, "undefined symbol")

    fixoff, fixsize = struct.unpack_from("<2I", data, commands[0x80000034] + 8)
    if fixsize < 28 or fixoff + fixsize > len(data):
        raise ValueError("chained fixups out of bounds")
    version, _, imports, symbols, count, fmt, symbols_fmt = struct.unpack_from(
        "<7I", data, fixoff
    )
    sizes = {1: 4, 2: 8, 3: 16}
    if version or symbols_fmt or fmt not in sizes:
        raise ValueError("unsupported chained import format")
    end = fixoff + fixsize
    start = fixoff + imports
    strings = fixoff + symbols
    if start + count * sizes[fmt] > end or not fixoff <= strings < end:
        raise ValueError("chained imports out of bounds")
    matches = []
    for index in range(count):
        item = start + index * sizes[fmt]
        raw = struct.unpack_from("<Q" if fmt == 3 else "<I", data, item)[0]
        weak_bit = 1 << (16 if fmt == 3 else 8)
        nameoff = raw >> (32 if fmt == 3 else 9)
        name = strings + nameoff
        if not strings <= name < end:
            raise ValueError("chained import name out of bounds")
        if data[name:end].split(b"\0", 1)[0] == SYMBOL:
            if raw & weak_bit:
                raise ValueError("chained import is already weak")
            matches.append((item, raw, weak_bit))
    item, raw, weak_bit = unique(matches, "chained import")

    struct.pack_into("<H", data, entry + 6, description | WEAK_REF)
    struct.pack_into("<Q" if fmt == 3 else "<I", data, item, raw | weak_bit)
    path.write_bytes(data)


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("usage: patch-launchctl.py PATH")
    patch(Path(sys.argv[1]))
