# iOS 27 signing research: verified public evidence (2026-10-09)

## Goal and ground rules

Target: a **stock, consumer** A18 iPhone 16 running iOS 27.0 developer beta 4. The same research question can apply across device families; the *vulnerability* need not be model-specific, while individual Image4 tickets and nonces may still constrain where they can be used.

**Current result: NO verified, publicly reproducible, stock-device signing bypass was found in the sources audited below.** This document records verified implementation boundaries; a green Xcode/CI build or successful ad-hoc Mach-O signature does not establish code execution with arbitrary entitlements.

## The missing Lycorine primitive

Source: [upstream TrustCache.m](https://github.com/hrtowii/lycorine-public/blob/main/Lycorine/Bundled/RootHelper/Cloning/TrustCache.m).

1. Lycorine finds an installed recovery cryptex's `im4m` and uses its `gtcd` trust cache as a source.
2. It invokes a bundled, **not publicly included**, `cryptexctl generate-trust-cache` to write a new `gtcd` for cloned binaries.
3. Immediately after logging `trust clone: personalizing cache`, the published code contains `// lalala too bad`.
4. It then attempts to load `cache.img4` through `trustcachectl` despite no public implementation creating a personalized `cache.img4` from the newly generated `gtcd`.

This is NOT a functional trust-cache signing/loading chain. Building the Xcode app or rebuilding its cryptex assets does not fill step 3.

The developer's [October 9 write-up](https://github.com/hrtowii/personal-website/blob/main/src/content/blog/Making%20a%20not-jailbreak%20in%203%20weeks.md) attributes Lycorine's original ability to trust-cache arbitrary executables to a then-unintended **Apple TSS server-side authorization** of custom research cryptex images for consumer devices. The write-up says the bug was patched and the signing/personalization implementation would not be released.

## Independent candidate audit

| Candidate | What public source actually establishes | Requirement not met by a stock A18 |
|---|---|---|
| [Xplo8E/TrollStore27](https://github.com/Xplo8E/TrollStore27/releases) | iOS 27 app-registration fixes for TrollStore **Lite**, tested on a patched iPhone 11 | Its release says explicitly that it does nothing on stock hardware and requires a patched kernelcache and TXM. It does **not** introduce an iOS 27 CoreTrust exploit. |
| [TXM patchfinder](https://github.com/apkunpacker/usbliter8-txm-patchfinder) | Binary patch discovery for TXM firmware extracted from IPSWs | Producing edited bytes is not a boot-chain exploit or authority to run patched TXM on stock A18. |
| [Xplo8E/Liter8](https://github.com/Xplo8E/Liter8) | A separate **tethered**, custom-boot iPhone 11 jailbreak with TrollStore support | The maintainer claims tested device support for iPhone 11; the path requires pwn DFU/modified boot chain, not a stock A18 jailbreak. |
| [applecert/vsignv2 (3105)](https://github.com/applecert/vsignv2/blob/main/README_3105.md) | Container-file workspace and patches, with stated support for specified iOS 27 betas and enterprise provisioning | No trust-cache authorization or arbitrary-signing primitive. The README explicitly says no persistent jailbreak. |
| [vvirei333/abrake27](https://github.com/vvirei333/abrake27) | Research on **normal Developer Mode** and firmware diffing | Developer Mode does not grant platform entitlements or authorize arbitrary research trust caches. |
| [idevice](https://github.com/jkcoxson/idevice/blob/main/idevice/src/tss.rs) and [pymobiledevice3](https://github.com/doronz88/pymobiledevice3) | Legitimate Cryptex1 TSS request framing, nonce handling, and device service communication | The client can REQUEST a ticket, but only Apple's server can grant one. Having the protocol implementation does not reinstate its former vulnerable policy. |

## Why old signed cryptexes do not prove the exploit remains available

- A previously signed customized cryptex may remain mounted and useful until it is removed or invalidated; the author's write-up reports persistence across ordinary reboots.
- This can explain a privately demonstrated *currently running* jailbreak or TrollStore-like installer **without** demonstrating the ability to get a **new** arbitrary cryptex signed today.
- Apple's [Secure Boot Tag documentation](https://security.apple.com/documentation/private-cloud-compute/appendix_secureboot) identifies `gtcd` (trust-cache hashes), `gtgv` (APFS seal root), `ginf` (cryptex metadata), and `cnch` (Cryptex1 nonce hash). Tickets bind measured content and may carry device or nonce constraints. Ticket reuse on another model/device is not established.

## Reproducibility gate: what would count as a real stock-A18 bypass

Before calling any reconstruction an exploit, require **all** of:

1. An independently obtained **new**, not recycled, valid Apple Image4 authorization for custom cryptex content, or a separately demonstrated on-device mechanism that overrides the required trust check.
2. Verification that the authorized object covers the *custom* code-directory hashes and not merely Apple's standard developer image.
3. Successful execution of an arbitrary controlled test binary with specifically justified privileged entitlements on a stock, unpatched device; ordinary developer certificates, Developer Mode, or SideStore are insufficient.
4. Reliable reproduction on the exact iOS build and boot state, with logs that distinguish signature acceptance from app registration or an already-patched environment.
5. A clear account of reboot/persistence, nonces, and failure modes.

A working request format, valid ad-hoc Mach-O signature, installed DeveloperDiskImage, `cryptexd` enumeration, or green unsigned IPA does **not** pass this gate.

## Practical next step

Research the **authorization decision itself**, not more build-script plumbing:

- Preserve existing on-device `cryptexd` diagnostics and code-signing rejection logs when testing your own device.
- Compare a *legitimate* Apple-authorized Cryptex1 transaction with the published Lycorine custom trust-cache flow to identify where server-side policy now rejects it. Do not present a hypothetical TSS response as an accepted ticket.
- Treat any newly public CoreTrust/TXM/IMG4 finding as a candidate only after its prerequisites and stock-A18 applicability are independently verified.

**Status: application compiles; arbitrary Cryptex/TSS signing bypass NOT recovered.** The project’s unsigned diagnostic IPA is not a jailbreak.
