# Lycorine-public

* Using the worst codesigning bypass for an untethered-ish JB on iOS 27.0 and lower.

**Original upstream notice:** the personalizing/signing code for the sealed cryptex image was not published, so this source alone cannot build a functional jailbreak.

Write-up: https://www.hrtowii.dev/blog/making-a-not-jailbreak-in-3-weeks

## NightVibes33 fork: experimental Cryptex build tooling and iOS app

This fork adds a **community reconstruction** of the missing Cryptex build orchestration, with dependency diagnostics, conservative payload auditing, integrity checks and offline tests. It also adds a public-API `cryptexd` service for RSD inventory and installing **pre-authorized** signed cryptexes; the published original service was missing.

### iOS 27 app build

The SwiftUI project is compiled on the `xcode-27` GitHub runner with `CODE_SIGNING_ALLOWED=NO`. A passing workflow proves the UI and FFI code compile and link; it does **not** verify on-device execution or that Apple's TSS will authorize a modified trust cache.

From [Actions → Lycorine iOS app compile](https://github.com/NightVibes33/lycorine-public/actions/workflows/lycorine-ios-compile.yml), open a successful run and retrieve the `Lycorine-unsigned-UI-only` artifact. The resulting IPA is **unsigned** and is intended for app UI/diagnostics testing after separate normal app signing, not as a working jailbreak.

The app's `load_sealed_img()` explicitly fails unless it finds a validly packaged `com.saccharine.lycorine.recovery.cxbd.signed` and matching local SHA-384 assets. The public repository does **not** contain that signed image or the withheld TSS exploit.

See [reconstruction instructions](docs/RECONSTRUCTION.md).

**The Apple TSS authorization bug is patched.** No functioning code-signing bypass or working iOS 27 jailbreak is provided. Passing the offline CI proves neither Apple signing nor device execution.

To run the diagnostics on macOS:

```sh
make -C Lycorine/Bundled/Cryptex doctor
make -C Lycorine/Bundled/Cryptex audit
```

To run mock-backed offline tests:

```sh
python3 -m unittest discover -s tests -v
```

## RSD compatibility and troubleshooting (October 2026)

This fork no longer treats iOS 27 beta 4 as the only supported build. The minimum deployment target remains iOS 18; the app probes the actual RSD and cryptexd services at runtime. API availability and the firmware's signing policy may vary on earlier and later releases. There is **no claim of a working code-signing exploit on all firmware versions**.

The RSD tunnel uses a local VPN endpoint, default `10.7.0.1:49152`, now configurable in Settings. Import validates that the supplied pairing file parses as a remote-pairing record; the separate **Test RSD / Cryptexd connection** operation verifies the active tunnel. A socket reset at handshake is a transport or remote-pairing failure, **not** an Apple TSS rejection. The previous "starting heartbeat" log was misleading: the IDeviceKit heartbeat library does not use that path for iOS 17.4+ RSD.

A legitimate Apple-signed Lycorine cryptex is still required to proceed with a privileged install. The public code and Xcode success do not replace the patched Apple TSS authorization flaw.
