#!/bin/zsh
# Public-source reconstruction of Lycorine's MISSING Cryptex build orchestrator.
# This is NOT the original script and does NOT reproduce the unpublished
# vulnerability allowing arbitrary production-device Cryptex signatures.
set -euo pipefail
IFS=$'\n\t'

HERE=$(cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(cd -- "$HERE/.." && pwd)
BUNDLED=$(cd -- "$ROOT/.." && pwd)
REPO=$(cd -- "$ROOT/../../.." && pwd)
WORK="$REPO/build/Cryptex"
DOWNLOAD="$ROOT/downloads"
STAGE="$WORK/cryptex-root"
ARTIFACTS="$WORK/artifacts"
IDENTIFIER=${LYCORINE_CRYPTEX_ID:-com.saccharine.lycorine.recovery}
VERSION=${LYCORINE_CRYPTEX_VERSION:-1.0.0.0}
TOOL=${LYCORINE_CRYPTEXCTL:-}

log() { printf '[lycorine-reconstruction] %s\n' "$*" >&2; }
die() { log "ERROR: $*"; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "missing command: $1"; }

# Deliberately fail on absent inputs; never silently fabricate privileged tools.
need_file() { [[ -f "$1" ]] || die "missing required source input: $1"; }
need_executable() { [[ -x "$1" ]] || die "missing required executable: $1"; }
require_macos() { [[ $(uname -s) == Darwin ]] || die "This build phase requires macOS + Apple's toolchain"; }
find_cryptexctl() {
  if [[ -n "$TOOL" ]]; then need_executable "$TOOL"; return; fi
  for p in /System/Library/SecurityResearch/usr/bin/cryptexctl /usr/bin/cryptexctl; do
    if [[ -x "$p" ]]; then TOOL="$p"; return; fi
  done
  if command -v cryptexctl >/dev/null 2>&1; then TOOL=$(command -v cryptexctl); return; fi
  die "cryptexctl missing; only Apple's supported tooling may create research images"
}

usage() {
  cat <<EOF
Lycorine Cryptex builder (reconstruction, NOT original build.sh)
Usage: scripts/build.sh {doctor|fetch|build|audit|image|personalize|bundle|clean|distclean}

  doctor    Print exact missing dependencies; does not change device
  fetch     Download publicly pinned upstream source versions and DEBs
  build     Build root helper and jitter daemon; compose Procursus archive
  audit     Read-only audit of staged payload (no signing or device operations)
  image     Package complete research Cryptex root as APFS DMG + .cxbd
  personalize  Ask Apple's TSS to authorize the research Cryptex
  bundle    Package an EXTERNALLY authorized, signed Cryptex bundle
  clean     Delete local generated build output
  distclean Delete generated build output and downloads

Environment:
  LYCORINE_CRYPTEXCTL           path to Apple's cryptexctl
  LYCORINE_CRYPTEX_ID           default $IDENTIFIER
  LYCORINE_CRYPTEX_VERSION      default $VERSION
  LYCORINE_SIGNED_CRYPTEX_DIR   externally authorized complete .cxbd.signed
  LYCORINE_RESEARCH_DEVICE_UDID optional intended research-device UDID
  LYCORINE_PAYLOAD_ROOT         fully populated research Cryptex dstroot
  LYCORINE_OPAINJECT_URL        explicit provenance for missing opainject binary

NO production-device signing bypass is included. A successfully created image
is NOT evidence it will install on a customer iPhone.
EOF
}

doctor() {
  local failed=0
  check() {
    if [[ "$1" == command ]]; then
      if command -v "$2" >/dev/null 2>&1; then log "OK   command: $2"; else log "MISS command: $2"; failed=1; fi
    elif [[ "$1" == executable ]]; then
      if [[ -x "$2" ]]; then log "OK   executable: $2"; else log "MISS executable: $2"; failed=1; fi
    else
      if [[ -f "$2" ]]; then log "OK   source: $2"; else log "MISS source: $2"; failed=1; fi
    fi
  }
  log "Checking public Lycorine source and host tooling."
  for c in zsh make python3 curl tar zstd xcrun codesign hdiutil; do check command "$c"; done
  check file "$ROOT/bootstrap/bootstrap_1900.tar.zst"
  check file "$ROOT/scripts/prepare-bootstrap.sh"
  check file "$HERE/audit_payload.py"
  check file "$ROOT/config/sshd_config.reconstructed"
  check file "$HERE/verify_assets.py"
  check file "$ROOT/config/sources.lock"
  check file "$ROOT/config/bootstrap-packages.lock"
  check file "$BUNDLED/RootHelper/Makefile"
  check file "$BUNDLED/Hooks/jitterd/Makefile"
  check executable "${THEOS:-$HOME/theos}/bin/nic"
  for f in ldid cryptexctl trustcachectl; do
    check executable "$BUNDLED/RootHelper/Cloning/Tools/$f"
  done
  if [[ $(uname -s) != Darwin ]]; then log 'MISS host must be macOS'; failed=1; fi
  if [[ -z "$TOOL" ]] && ! command -v cryptexctl >/dev/null 2>&1 && \
     [[ ! -x /System/Library/SecurityResearch/usr/bin/cryptexctl ]]; then
    log 'MISS Apple Cryptex tooling (research hardware workflow)'; failed=1
  fi
  [[ "$failed" == 0 ]] || log 'Doctor: missing build inputs. Do not run image until fixed.'
  log 'Independent unresolved boundary: no public normal-device image signing exploit.'
  return "$failed"
}

# Pull exactly the versions from the public lockfiles. Upstream locks contain
# URLs, not content hashes; the downloaded archives should be verified before use.
download_locked() {
  local file="$1" url="$2" tmp
  [[ "$url" == https://* ]] || die "refusing a non-HTTPS dependency: $url"
  if [[ -s "$file" ]]; then log "cached $(basename "$file")"; return; fi
  tmp="$file.partial"
  log "fetch $(basename "$file")"
  curl --fail --location --retry 3 --connect-timeout 20 --max-time 600 -o "$tmp" "$url" || {
    rm -f -- "$tmp"; die "download failed: $url";
  }
  [[ -s "$tmp" ]] || die "download was empty: $url"
  mv -- "$tmp" "$file"
}
fetch() {
  need curl; need_file "$ROOT/config/sources.lock"; need_file "$ROOT/config/bootstrap-packages.lock"
  mkdir -p "$DOWNLOAD"
  local name version url state
  while IFS='|' read -r name version url || [[ -n "$name" ]]; do
    [[ -z "$name" || "$name" == \#* ]] && continue
    download_locked "$DOWNLOAD/$name-$version.tar.gz" "$url"
  done < "$ROOT/config/sources.lock"
  while IFS='|' read -r name version url state || [[ -n "$name" ]]; do
    [[ -z "$name" || "$name" == \#* ]] && continue
    download_locked "$DOWNLOAD/$name-$version.deb" "$url"
  done < "$ROOT/config/bootstrap-packages.lock"
  if [[ -n "${LYCORINE_OPAINJECT_URL:-}" ]]; then
    download_locked "$DOWNLOAD/opainject-1.0.6" "$LYCORINE_OPAINJECT_URL"
    chmod 755 "$DOWNLOAD/opainject-1.0.6"
  else
    log 'opainject binary is not in public lockfiles; supply verified binary manually'
  fi
  log 'Fetch complete. The public lockfiles have NO SHA-256 hashes: verify provenance.'
}

# Build the actual public Theos components and compose the supplied bootstrap.
# Does not invent the missing cross-compiled OpenSSH/Toybox/ExecMainBinary tools.
build() {
  require_macos
  for c in make xcrun codesign python3 zstd tar; do need "$c"; done
  need_file "$ROOT/bootstrap/bootstrap_1900.tar.zst"
  need_file "$ROOT/scripts/prepare-bootstrap.sh"
  for f in ldid cryptexctl trustcachectl; do
    need_executable "$BUNDLED/RootHelper/Cloning/Tools/$f"
  done
  [[ -d "${THEOS:-$HOME/theos}/makefiles" ]] || die 'Theos is missing: set THEOS to your installation'
  mkdir -p "$STAGE/usr/bin" "$STAGE/Library/LaunchDaemons" "$ARTIFACTS"
  log 'Compiling lycorined and the supported hook modules'
  make -C "$BUNDLED/RootHelper" cryptex-install CRYPTEX_ROOT="$STAGE" DEBUG=0
  log 'Compiling jitterd'
  make -C "$BUNDLED/Hooks/jitterd" cryptex-install CRYPTEX_ROOT="$STAGE" DEBUG=0
  log 'Staging available public launchd jobs and OpenSSH launcher'
  local sourcefile
  mkdir -p "$STAGE/usr/libexec/lycorine" "$STAGE/etc/ssh"
  for sourcefile in \
    com.hrtowii.jitterd.plist \
    com.saccharine.lycorine.daemon.plist \
    com.saccharine.lycorine.openssh.plist; do
    need_file "$ROOT/launchd/$sourcefile"
    install -m 644 "$ROOT/launchd/$sourcefile" "$STAGE/Library/LaunchDaemons/$sourcefile"
  done
  need_file "$ROOT/payload/start-openssh.sh"
  install -m 755 "$ROOT/payload/start-openssh.sh" "$STAGE/usr/libexec/lycorine/start-openssh.sh"
  need_file "$ROOT/config/sshd_config.reconstructed"
  install -m 644 "$ROOT/config/sshd_config.reconstructed" "$STAGE/etc/ssh/sshd_config"
  if [[ -n "${AUTHORIZED_KEYS_FILE:-}" ]]; then
    need_file "$AUTHORIZED_KEYS_FILE"
    # This is a PUBLIC key only; do not include SSH private-key material.
    [[ $(head -n 1 "$AUTHORIZED_KEYS_FILE") == ssh-* || \
       $(head -n 1 "$AUTHORIZED_KEYS_FILE") == ecdsa-* ]] || \
       die 'AUTHORIZED_KEYS_FILE must begin with a public OpenSSH key'
    install -m 600 "$AUTHORIZED_KEYS_FILE" "$STAGE/etc/lycorine_authorized_key"
  else
    log 'No AUTHORIZED_KEYS_FILE: SSH requires you to provision a public key before deployment.'
  fi
  log 'Composing pinned rootless bootstrap archive'
  /bin/zsh "$ROOT/scripts/prepare-bootstrap.sh"
  log 'Built public components. The root also needs OpenSSH, Toybox, cryptex-run, untar,'
  log 'ExecMainBinary, and signed tools. Use LYCORINE_PAYLOAD_ROOT with a verified complete root.'
}

# Read-only audit of staged content. No Apple TSS calls, no device operations.
audit() {
  need python3
  local input_root="${LYCORINE_PAYLOAD_ROOT:-$STAGE}"
  python3 "$HERE/audit_payload.py" "$input_root" --check-macho \
    --json "$ARTIFACTS/payload-preflight.json"
}
verify_root() {
  local root="$1"
  need_file "$ARTIFACTS/bootstrap.tar.zst"
  # A shell-friendly readable error report lives alongside the build outputs.
  python3 "$HERE/audit_payload.py" "$root" --check-macho \
    --json "$ARTIFACTS/payload-preflight.json" || \
    die "invalid payload: inspect $ARTIFACTS/payload-preflight.json"
}
# The documented cryptexctl create input is a disk image, NOT a folder.
# This corrects the error in the first reconstruction.
image() {
  require_macos
  for c in python3 hdiutil; do need "$c"; done
  find_cryptexctl
  local input_root="${LYCORINE_PAYLOAD_ROOT:-$STAGE}"
  local dest="$ARTIFACTS/research"
  local dmg="$dest/$IDENTIFIER.dmg"
  local cxbd="$dest/$IDENTIFIER.cxbd"
  [[ -d "$input_root" ]] || die "missing Cryptex root: $input_root"
  verify_root "$input_root"
  mkdir -p "$dest"
  [[ ! -e "$dmg" && ! -e "$cxbd" ]] ||
    die "existing image or bundle at destination; move/delete it explicitly before rebuilding"
  log 'Making APFS disk image from complete distribution root'
  hdiutil create -fs APFS -format UDRW -srcfolder "$input_root" "$dmg"
  [[ -s "$dmg" ]] || die "hdiutil returned without a usable disk image"
  log 'Creating research-format Cryptex bundle (does not sign it)'
  "$TOOL" create --research --identifier="$IDENTIFIER" \
    --version="$VERSION" --variant=research -o "$dest" "$dmg"
  [[ -d "$cxbd" ]] || die "cryptexctl did not create $cxbd"
  python3 "$HERE/verify_assets.py" "$cxbd" --format research
  log 'CREATED (unsigned): Apple TSS personalization is a separate step.'
}

# Valid only when Apple's TSS service chooses to authorize a research image.
# The original Lycorine consumer-device TSS authorization flaw is patched.
personalize() {
  require_macos
  need python3
  find_cryptexctl
  local dest="$ARTIFACTS/research"
  local cxbd="$dest/$IDENTIFIER.cxbd"
  local signed="$dest/$IDENTIFIER.cxbd.signed"
  [[ -d "$cxbd" ]] || die "missing unsigned Cryptex: $cxbd; run image first"
  [[ ! -e "$signed" ]] ||
    die "signed output already exists: $signed; clear explicitly before continuing"
  python3 "$HERE/verify_assets.py" "$cxbd" --format research
  log 'Requesting documented research personalization from Apple TSS'
  log 'Authorization is controlled by Apple. Patched consumer-device bypass is NOT available.'
  # macOS ships Bash 3.2; under set -u, empty array expansion can abort.
  if [[ -n "${LYCORINE_RESEARCH_DEVICE_UDID:-}" ]]; then
    "$TOOL" --udid "$LYCORINE_RESEARCH_DEVICE_UDID" personalize --research \
      --variant=research -o "$dest" "$cxbd"
  else
    "$TOOL" personalize --research \
      --variant=research -o "$dest" "$cxbd"
  fi
  [[ -d "$signed" ]] || die "TSS returned without creating $signed"
  python3 "$HERE/verify_assets.py" "$signed" --format research --signed
  log 'Personalization output present. No on-device installation or execution was attempted.'
}

bundle() {
  need python3
  local input="${LYCORINE_SIGNED_CRYPTEX_DIR:-}"
  [[ -n "$input" ]] || die 'Set LYCORINE_SIGNED_CRYPTEX_DIR to an authorized signed Cryptex directory.'
  [[ -d "$input" ]] || die "no signed bundle directory: $input"
  mkdir -p "$ARTIFACTS"
  python3 "$HERE/verify_assets.py" "$input" --signed --report "$ARTIFACTS/asset-manifest.json"
  log 'Asset inventory complete. Presence of im4m DOES NOT authenticate the signature.'
  log "Wrote $ARTIFACTS/asset-manifest.json"
}

cmd=${1:-doctor}
case "$cmd" in
  doctor) doctor ;;
  fetch) fetch ;;
  build) build ;;
  audit) audit ;;
  image) image ;;
  personalize|sign) personalize ;;
  bundle) bundle ;;
  clean) [[ -n "$WORK" && "$WORK" == "$REPO/build/Cryptex" ]] || die 'unsafe clean path'; rm -rf -- "$WORK" ;;
  distclean) [[ -n "$WORK" && "$WORK" == "$REPO/build/Cryptex" ]] || die 'unsafe clean path'; rm -rf -- "$WORK" "$DOWNLOAD" ;;
  -h|--help|help) usage ;;
  *) usage >&2; die "unknown command: $cmd" ;;
esac
