# iPhone 16 / iOS 27 Simulator smoke test

This fork has a [GitHub Actions workflow](../.github/workflows/lycorine-simulator.yml) that:
1. Detects the actual installed Xcode, iOS 27 Simulator runtime **and build**, and iPhone 16 device profile.
2. Prefers **iOS 27.0 developer beta 4 (24A5390f)** if that exact runtime is installed. Otherwise selects an available iOS 27 runtime, documents the substitution and explicitly says it is *not* beta 4.
3. Boots an **iPhone 16 Simulator**.
4. Compiles the real Lycorine SwiftUI iOS Simulator app, installs, launches, and captures a PNG screenshot with diagnostic logs.
5. Uploads `runtime-evidence.json`, build logs, and screenshots to the workflow's Artifacts section.

## Important boundaries

The iPhone 16 **device profile** does not reproduce the real A18's Apple Secure Enclave, TXM firmware, boot trust chain, Image4 measurements, or Apple TSS device personalization. Thus, successful Simulator execution does **not** validate a Lycorine signing bypass on a stock iPhone 16 running iOS 27 beta 4.

In Simulator builds, the app deliberately disables the jailbreak action and hardware pairing/callbacks. This is not a simulated successful exploit.

The fork also builds an unsigned **physical iOS** application in a separate Xcode workflow. That build likewise cannot provide or manufacture a signed Lycorine research Cryptex.

## Where to see results

[Actions — Lycorine iPhone 16 Simulator smoke test](https://github.com/NightVibes33/lycorine-public/actions/workflows/lycorine-simulator.yml)

Open a successful run, then the artifact **Lycorine-iPhone16-iOS27-simulator-evidence**. Check its `runtime-evidence.json` before referring to the test as iOS 27.0 beta 4.

## What remains untested

An actual new Apple authorization for a custom trust-cache payload on a **physical**, stock iPhone 16. That would require a real device and a demonstrated Apple-approved or exploited authorization path, not a Simulator.
