"""Offline contract tests for the reconstructed Cryptex CLI.

Fake Apple tools exercise the argument plumbing; this DOES NOT validate an
actual signed cryptex or any bypass of Apple's signing service.
"""
from __future__ import annotations
import hashlib
from pathlib import Path
import plistlib
import os
import shutil
import subprocess
import tempfile
import textwrap
import unittest

SRC = Path(__file__).resolve().parents[1] / 'Lycorine' / 'Bundled' / 'Cryptex' / 'scripts'
EXECUTABLES = ('usr/bin/cryptex-run', 'usr/bin/lycorined', 'usr/bin/jitterd',
               'usr/bin/toybox', 'usr/bin/sh', 'usr/bin/untar', 'usr/bin/ssh-keygen',
               'usr/sbin/sshd', 'usr/libexec/lycorine/ldid',
               'usr/libexec/lycorine/cryptexctl',
               'usr/libexec/lycorine/trustcachectl',
               'usr/libexec/lycorine/start-openssh.sh')
DATA = ('Library/LaunchDaemons/com.hrtowii.jitterd.plist',
        'Library/LaunchDaemons/com.saccharine.lycorine.daemon.plist',
        'Library/LaunchDaemons/com.saccharine.lycorine.openssh.plist',
        'etc/ssh/sshd_config')

class BuildPipelineTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.dir = Path(self.tmp.name)
        self.repo = self.dir / 'lycorine'
        self.scripts = self.repo / 'Lycorine' / 'Bundled' / 'Cryptex' / 'scripts'
        self.scripts.mkdir(parents=True)
        for name in ('build.sh', 'verify_assets.py', 'audit_payload.py'):
            shutil.copy2(SRC / name, self.scripts / name)
        self.payload = self.dir / 'payload'
        for name in EXECUTABLES:
            p = self.payload / name
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_bytes(b'\xcf\xfa\xed\xfe' + b'fixture executable' if name in ('usr/bin/lycorined', 'usr/bin/jitterd', 'usr/libexec/lycorine/cryptexctl','usr/libexec/lycorine/trustcachectl') else b'fixture executable')
            p.chmod(0o755)
        for name in DATA:
            p = self.payload / name
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_bytes(plistlib.dumps({'Label':'test.'+p.stem}) if name.endswith('.plist') else b'fixture configuration')
        build_artifacts = self.repo / 'build' / 'Cryptex' / 'artifacts'
        build_artifacts.mkdir(parents=True)
        (build_artifacts / 'bootstrap.tar.zst').write_bytes(b'test archive')

        self.bin = self.dir / 'bin'
        self.bin.mkdir()
        uname = self.bin / 'uname'
        uname.write_text('#!/bin/sh\nprintf "Darwin\\n"\n')
        uname.chmod(0o755)
        hdiutil = self.bin / 'hdiutil'
        hdiutil.write_text('#!/bin/sh\nfor last; do :; done\nprintf "fake image" > "$last"\n')
        hdiutil.chmod(0o755)

        self.cryptexctl = self.bin / 'cryptexctl'
        self.cryptexctl.write_text(textwrap.dedent('''\
            #!/usr/bin/env python3
            import hashlib, os, pathlib, plistlib, shutil, sys
            a = sys.argv[1:]
            command = 'create' if 'create' in a else 'personalize' if 'personalize' in a else 'unknown'
            with open(os.environ['CALL_LOG'], 'a') as f:
                f.write(' '.join(a) + '\\n')
            dest = pathlib.Path(a[a.index('-o')+1])
            if command == 'create':
                assert '--research' in a
                assert a[-1].endswith('.dmg')
                ident = next(x.split('=',1)[1] for x in a if x.startswith('--identifier='))
                bundle = dest / (ident+'.cxbd')
                store = bundle / 'Restore'
                store.mkdir(parents=True)
                (store/'gtcd').write_bytes(b'fake')
                manifest = {'BuildIdentities':[{'Info':{'Variant':'research'},
                     'Manifest':{'Cryptex1,GenericTrustCache':{'Info':{'Path':'gtcd'},
                         'Digest':hashlib.sha384(b'fake').digest()}}}]}
                (store/'BuildManifest.plist').write_bytes(plistlib.dumps(manifest))
            elif command == 'personalize':
                assert '--research' in a
                orig = pathlib.Path(a[-1])
                bundle = dest/(orig.name+'.signed')
                shutil.copytree(orig, bundle)
                (bundle/'im4m').write_bytes(b'MOCK TICKET - NOT VALID')
            else:
                raise SystemExit('unexpected command: '+str(a))
            '''))
        self.cryptexctl.chmod(0o755)
        self.log = self.dir / 'calls.txt'
        self.env = os.environ.copy()
        self.env['PATH'] = f"{self.bin}:{os.environ['PATH']}"
        self.env['LYCORINE_CRYPTEXCTL'] = str(self.cryptexctl)
        self.env['LYCORINE_PAYLOAD_ROOT'] = str(self.payload)
        self.env['CALL_LOG'] = str(self.log)

    def call(self, cmd):
        return subprocess.run(['/bin/bash', str(self.scripts/'build.sh'), cmd],
                              env=self.env, text=True, capture_output=True)

    def test_creates_dmg_before_cryptex(self):
        result = self.call('image')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('create --research', self.log.read_text())
        self.assertTrue((self.repo/'build/Cryptex/artifacts/research/com.saccharine.lycorine.recovery.dmg').is_file())

    def test_official_research_personalization_path(self):
        self.assertEqual(self.call('image').returncode, 0)
        result = self.call('personalize')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('personalize --research', self.log.read_text())
        signed = self.repo/'build/Cryptex/artifacts/research/com.saccharine.lycorine.recovery.cxbd.signed'
        self.assertTrue(signed.is_dir())
        # Ticket is not cryptographically verified by offline mock.
        self.assertIn('No on-device installation', result.stderr)

    def test_detect_non_macho_roothelper(self):
        (self.payload/'usr/bin/lycorined').write_bytes(b'a fake binary')
        result = self.call('image')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('not a Mach-O',
            (self.repo/'build/Cryptex/artifacts/payload-preflight.json').read_text())
        self.assertFalse(self.log.exists())

    def test_audit_does_not_contact_signing_service(self):
        result = self.call('audit')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('Staging preflight only', result.stdout)
        self.assertFalse(self.log.exists())

    def test_symlink_escape_rejected_prior_to_image(self):
        target = self.payload/'usr/bin/lycorined'
        target.unlink()
        target.symlink_to(self.dir/'outside')
        (self.dir/'outside').write_bytes(b'\xcf\xfa\xed\xfe' + b'x')
        result = self.call('image')
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.log.exists())

    def test_invalid_launchd_plist_rejected(self):
        (self.payload/DATA[0]).write_bytes(b'# comment')  # unrelated data remains allowed
        (self.payload/'Library/LaunchDaemons/com.hrtowii.jitterd.plist').write_bytes(b'invalid plist')
        result = self.call('image')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('invalid-plist',
            (self.repo/'build/Cryptex/artifacts/payload-preflight.json').read_text())

    def test_prevent_unproved_personalization(self):
        result = self.call('personalize')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('missing unsigned Cryptex', result.stderr)

    def test_refuse_partial_payload(self):
        (self.payload/'usr/bin/sshd').unlink() if (self.payload/'usr/bin/sshd').exists() else None
        (self.payload/'usr/sbin/sshd').unlink()
        result = self.call('image')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('invalid payload', result.stderr)
        self.assertFalse(self.log.exists())

if __name__=='__main__':
    unittest.main()

class OverlayStaticTests(unittest.TestCase):
    def test_makefile_new_targets(self):
        mk = (SRC.parent/'Makefile').read_text()
        self.assertIn('doctor fetch build audit image personalize bundle', mk)
        self.assertIn('$(SCRIPT) $@', mk)

    def test_ssh_config_key_only(self):
        config = (SRC.parent/'config'/'sshd_config.reconstructed').read_text()
        self.assertIn('PasswordAuthentication no', config)
        self.assertIn('PermitRootLogin prohibit-password', config)
        self.assertIn('KbdInteractiveAuthentication no', config)
        self.assertIn('AuthorizedKeysFile ', config)
