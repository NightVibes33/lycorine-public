#!/usr/bin/env python3
"""Offline, read-only validation of a staged Lycorine research Cryptex root.

This verifies presence, path containment, Mach-O signatures' structural hints,
plist parseability, and potential packaging hazards. It cannot establish Apple
TSS authorization or identify a working code-signing bypass.
"""
from __future__ import annotations
import argparse
import json
import os
from pathlib import Path
import plistlib
import sys

EXECUTABLES = (
    'usr/bin/cryptex-run', 'usr/bin/lycorined', 'usr/bin/jitterd',
    'usr/bin/toybox', 'usr/bin/sh', 'usr/bin/untar', 'usr/bin/ssh-keygen',
    'usr/sbin/sshd', 'usr/libexec/lycorine/ldid',
    'usr/libexec/lycorine/cryptexctl',
    'usr/libexec/lycorine/trustcachectl',
    'usr/libexec/lycorine/start-openssh.sh',
)
PLISTS = (
    'Library/LaunchDaemons/com.hrtowii.jitterd.plist',
    'Library/LaunchDaemons/com.saccharine.lycorine.daemon.plist',
    'Library/LaunchDaemons/com.saccharine.lycorine.openssh.plist',
)
DATA = ('etc/ssh/sshd_config',)
# Inputs which have to come from public source or a separately verified build.
PRIVILEGED_TOOLS = (
    'usr/bin/lycorined', 'usr/bin/jitterd',
    'usr/libexec/lycorine/cryptexctl',
    'usr/libexec/lycorine/trustcachectl',
)

def audit(root: Path, check_macho: bool = False) -> dict:
    if not root.is_dir():
        raise ValueError(f'not a directory: {root}')
    root = root.resolve(strict=True)
    issues = []
    examined = []
    for rel in (*EXECUTABLES, *PLISTS, *DATA):
        direct = root / rel
        record = {'path': rel}
        if direct.is_symlink() and not direct.exists():
            issues.append(f'{rel}: broken symlink')
            record['status'] = 'broken-symlink'
        elif not direct.exists():
            issues.append(f'{rel}: missing')
            record['status'] = 'missing'
        else:
            actual = direct.resolve()
            if not actual.is_relative_to(root):
                issues.append(f'{rel}: symlink escapes payload root')
                record['status'] = 'unsafe-path'
            elif not actual.is_file() or actual.stat().st_size == 0:
                issues.append(f'{rel}: empty or not a regular file')
                record['status'] = 'invalid-type'
            elif rel in EXECUTABLES and not os.access(direct, os.X_OK):
                issues.append(f'{rel}: not executable')
                record['status'] = 'not-executable'
            else:
                record['status'] = 'present'
                record['bytes'] = actual.stat().st_size
                if rel in PLISTS:
                    try:
                        obj = plistlib.loads(actual.read_bytes())
                        if not isinstance(obj, dict) or not isinstance(obj.get('Label'), str):
                            raise ValueError('missing Label')
                    except (ValueError, plistlib.InvalidFileException, OSError) as exc:
                        issues.append(f'{rel}: invalid launchd plist ({exc})')
                        record['status'] = 'invalid-plist'
                if check_macho and rel in PRIVILEGED_TOOLS and record['status'] == 'present':
                    header = actual.open('rb').read(4)
                    if header not in (b'\xcf\xfa\xed\xfe', b'\xfe\xed\xfa\xcf', b'\xca\xfe\xba\xbe', b'\xbe\xba\xfe\xca', b'\xca\xfe\xba\xbf', b'\xbf\xba\xfe\xca'):
                        issues.append(f'{rel}: not a Mach-O executable (header check only)')
                        record['status'] = 'not-macho'
        examined.append(record)
    # Scan symlinks throughout the root, not only the set above. Legitimate
    # relative symlinks are okay. Absolute symlinks need an explicit decision.
    for path in root.rglob('*'):
        if path.is_symlink():
            try:
                resolved = path.resolve(strict=True)
                if not resolved.is_relative_to(root):
                    issues.append(f'{path.relative_to(root)}: symlink points outside payload')
            except (OSError, RuntimeError):
                issues.append(f'{path.relative_to(root)}: broken or recursive symlink')
    return {
        'root': str(root), 'files': examined, 'issues': sorted(set(issues)),
        'ok': not issues,
        'meaning': 'Staging preflight only; not Apple TSS signing or device authorization',
    }

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('root', type=Path)
    parser.add_argument('--check-macho', action='store_true', help='check magic bytes of privileged compiled binaries')
    parser.add_argument('--json', type=Path, help='write machine-readable report to this file')
    args = parser.parse_args()
    try:
        report = audit(args.root, args.check_macho)
    except (ValueError, OSError) as exc:
        print(f'Payload audit error: {exc}', file=sys.stderr)
        return 2
    output = json.dumps(report, indent=2) + '\n'
    if args.json:
        args.json.parent.mkdir(parents=True, exist_ok=True)
        args.json.write_text(output)
    print(output)
    return 0 if report['ok'] else 1

if __name__ == '__main__':
    raise SystemExit(main())
