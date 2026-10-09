# Lycorine Cryptex pipeline — public-source reconstruction (revision 3)

**Status as of 2026-10-09:** Reconstructed build/personalization *orchestration*, testable offline. **Not a usable iOS 27 jailbreak, signing bypass, or Apple TSS authorization.** This is not the upstream author's implementation.

## Why the missing signer cannot simply be regenerated

The original author's [technical write-up](https://github.com/hrtowii/personal-website/blob/main/src/content/blog/Making%20a%20not-jailbreak%20in%203%20weeks.md) describes a **server-side Apple TSS authorization bug**. Apple's server previously agreed to personalize trust caches for arbitrary binaries and entitlements from ordinary devices. The developer states that Apple **patched that server-side bug**, and chose not to release the code that used it.

Reimplementing a TSS client or using a different Mach-O signer does **not** make Apple's server resume issuing those authorizations. Cryptex1 **packaging** is separate from the Apple-signed Image4 manifest needed for execution. An `im4m` file on disk by itself is also not proof that Apple issued a valid, target-authorized ticket.

## Source and corrections

- Upstream: [hrtowii/lycorine-public](https://github.com/hrtowii/lycorine-public), `Lycorine/Bundled/Cryptex/Makefile`, `scripts/prepare-bootstrap.sh`, `RootHelper/Makefile`, `Cloning/TrustCache.m`.
- Primary reference for supported personalization: [Apple's cryptexctl personalize manual](https://manp.gs/mac/1/cryptexctl-personalize); documented flow adapted from [insidegui/appcryptex](https://github.com/insidegui/appcryptex/blob/main/install.sh).
- **Revision 2 fixes an error in the earlier reconstruction:** `cryptexctl create` requires a **disk image** (`.dmg`), not a directory. The tool now constructs an APFS DMG from an already complete distribution root using `hdiutil` before `cryptexctl create`.
- **Revision 2 fixes another error:** the upstream `prepare-bootstrap.sh` writes to repository-root `build/Cryptex/artifacts`, not `Lycorine/Bundled/Cryptex/build/artifacts`.
- The upstream Makefile calls `build.sh` via `/bin/zsh`, so the script uses a zsh-compatible script path and shebang. Static syntax was checked with Bash; **native zsh/macOS execution was not available** here.
- **Revision 3** adds `audit_payload.py` to prevent accidental packaging of missing binaries, non-Mach-O placeholder root daemons, malformed launchd plists, and symlinks that escape the payload. A machine-readable `payload-preflight.json` is generated.
- **Revision 3** stages the publicly available launchd property lists and the `start-openssh.sh` launcher during `build`, alongside a clearly marked reconstructed key-only OpenSSH configuration. The script does **not** create or ship an SSH private key.
- **Revision 3** includes a replacement `Makefile` with `doctor`, `audit`, and `personalize` targets, so the public project can call the diagnostic phases normally.

## Patch overlay usage

Copy this archive's `Lycorine/Bundled/Cryptex/{Makefile,scripts/,config/sshd_config.reconstructed}` into a **separate clean checkout** of Lycorine. This archive does not contain the upstream repository or its bootstrap tarball; it includes the two replacement scripts, documentation, and test suite only. Use macOS with Xcode, Theos, `hdiutil`, and Apple `cryptexctl`.

```sh
cd /path/to/lycorine-public
chmod +x Lycorine/Bundled/Cryptex/scripts/build.sh
make -C Lycorine/Bundled/Cryptex doctor
make -C Lycorine/Bundled/Cryptex fetch
make -C Lycorine/Bundled/Cryptex build
make -C Lycorine/Bundled/Cryptex audit # read-only staged-root audit
# Build requires separately supplied nonpublic helper binaries described below.

# Once you have a complete research distribution root:
export LYCORINE_PAYLOAD_ROOT=/absolute/path/to/complete/research/dstroot
make -C Lycorine/Bundled/Cryptex image

# For an *authorized* Security Research Device only. Apple TSS must accept it:
export LYCORINE_RESEARCH_DEVICE_UDID=YOUR_RESEARCH_DEVICE_UDID
make -C Lycorine/Bundled/Cryptex personalize

# Only after personalization produced an externally signed artifact:
export LYCORINE_SIGNED_CRYPTEX_DIR="$PWD/build/Cryptex/artifacts/research/com.saccharine.lycorine.recovery.cxbd.signed"
make -C Lycorine/Bundled/Cryptex bundle
```

Commands:

- `doctor`: check original source prerequisites and required host tools, no device side effects.
- `audit`: inspect staged files, launchd plist validity, executable Mach-O headers and unsafe symlinks without contacting TSS. Store JSON preflight output in `build/Cryptex/artifacts/payload-preflight.json`.
- `fetch`: fetch public package/archive lockfile URLs. Lockfiles have no content hashes: verify provenance.
- `build`: build public Theos RootHelper and jitterd, prepare rootless bootstrap, stage public launch daemons and key-only SSH config. Fails explicitly when unpublished executables are missing.
- `image`: verify *complete* distribution root, make APFS `.dmg`, create unsigned research `.cxbd`, check local BuildManifest digests.
- `personalize` / `sign`: use documented **research** `cryptexctl personalize` path to ask Apple TSS for approval. It never substitutes a fake signature and does not install anything.
- `bundle`: inventory asset hashes for an externally authorized bundle; requires an `im4m` file but **does not cryptographically verify Apple's signature**.
- `clean` / `distclean`: remove locally generated output and, for distclean, cached download artifacts.

## Still missing from the public project

1. A **working replacement** for the patched TSS authorization bypass. This is the irreplaceable requirement for an arbitrary production iPhone; no public implementation has been validated here.
2. `RootHelper/Cloning/Tools/{ldid,cryptexctl,trustcachectl}` as packaged target executables, plus separately sourced `opainject-1.0.6`.
3. Published, validated build steps and toolchain outputs for OpenSSH, Toybox, `ExecMainBinary`, `cryptex-run`, `untar`, trust-cache generation, and any other sealed-image inputs. Some source files are published, but compilation and installation into the target root were not demonstrated here.
4. Actual Apple-issued authorization and a working on-device runtime test.

## Tests completed

On Linux, using standard Python 3 and **mock Apple binaries**:

```sh
bash -n Lycorine/Bundled/Cryptex/scripts/build.sh
python3 -m unittest discover -s tests -v
# 15 tests pass (5 asset checks + 8 offline pipeline checks + 2 static overlay checks)
```

Test coverage includes archive-path alignment, DMG input to `cryptexctl create`, research `personalize` command arguments, missing unsigned input rejection, partial-payload rejection, SHA-384 manifest checking, and ticket-presence-not-equalling-signature-verification semantics.

**Nothing was run on an iPhone. The fifteen offline tests DO NOT indicate a valid cryptex signature, macOS end-to-end build, successful personalization or jailbreak.**
