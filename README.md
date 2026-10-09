# Lycorine-public

* Using the worst codesigning bypass for an untethered-ish JB on iOS 27.0 and lower.

**Original upstream notice:** the personalizing/signing code for the sealed cryptex image was not published, so this source alone cannot build a functional jailbreak.

Write-up: https://www.hrtowii.dev/blog/making-a-not-jailbreak-in-3-weeks

## NightVibes33 fork: experimental Cryptex build tooling

This fork adds a **community reconstruction** of the missing Cryptex build orchestration, with dependency diagnostics, conservative payload auditing, integrity checks and offline tests.

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
