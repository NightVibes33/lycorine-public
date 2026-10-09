#!/bin/zsh
set -euo pipefail

ROOT_DIR=${0:A:h:h}
REPO_DIR=${ROOT_DIR:h:h:h}
BUILD_DIR=$REPO_DIR/build/Cryptex
DOWNLOAD_DIR=$ROOT_DIR/downloads
STAGE=$BUILD_DIR/bootstrap-root
OUTPUT=$BUILD_DIR/artifacts/bootstrap.tar.zst

BASE=$ROOT_DIR/bootstrap/bootstrap_1900.tar.zst

die() { print -u2 -- "error: $*"; exit 1; }
[[ -f "$BASE" ]] || die "missing bundled bootstrap: $BASE"

rm -rf "$STAGE"
mkdir -p "$STAGE" "$BUILD_DIR/artifacts"
zstd -dc "$BASE" | tar -xpf - -C "$STAGE"
JB=$STAGE/var/jb
[[ -x "$JB/usr/bin/dpkg" ]] || die "bootstrap has no executable var/jb/usr/bin/dpkg"
[[ -f "$JB/prep_bootstrap.sh" ]] || die "bootstrap has no var/jb/prep_bootstrap.sh"

# Compose pinned packages in lock-file order. Their maintainer scripts are
# registered for first-boot dpkg configuration, never executed on macOS.
while IFS='|' read -r package version url state; do
    [[ -z "$package" || "$package" == \#* ]] && continue
    deb="$DOWNLOAD_DIR/$package-$version.deb"
    [[ -f "$deb" ]] || die "missing package $package; run make fetch"
    /bin/zsh "$ROOT_DIR/scripts/install-deb-overlay.sh" "$STAGE" "$deb" "$state"
done < "$ROOT_DIR/config/bootstrap-packages.lock"

SILEO_POSTINST=$JB/Library/dpkg/info/org.coolstar.sileo.postinst
python3 - "$SILEO_POSTINST" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()
old = "uicache -p /Applications/Sileo.app"
if text.count(old) != 1:
    raise SystemExit("unexpected Sileo uicache trigger")
path.write_text(text.replace(old, "uicache -p /var/jb/Applications/Sileo.app"))
PY


ELLEKIT_MACHOS=(
    "$JB/usr/lib/ellekit/MobileSafety.dylib"
    "$JB/usr/lib/ellekit/libinjector.dylib"
    "$JB/usr/lib/ellekit/pspawn.dylib"
    "$JB/usr/lib/libellekit.dylib"
    "$JB/usr/libexec/ellekit/loader"
)
for macho in "${ELLEKIT_MACHOS[@]}"; do
    codesign --force --sign - --timestamp=none --pagesize 4096 \
        --generate-entitlement-der --preserve-metadata=entitlements "$macho"
done

OPAINJECT=$DOWNLOAD_DIR/opainject-1.0.6
install -m 755 "$OPAINJECT" "$JB/usr/bin/opainject"
codesign --force --sign - --timestamp=none --pagesize 4096 \
    --entitlements "$ROOT_DIR/config/opainject.entitlements.plist" \
    --generate-entitlement-der "$JB/usr/bin/opainject"

OVERLAY=$ROOT_DIR/bootstrap/overlay
make -C "$ROOT_DIR/../Uicache" overlay
if [[ -d "$OVERLAY" ]]; then
    COPYFILE_DISABLE=1 tar -C "$OVERLAY" \
        --exclude='./README.md' -cf - . | tar -xpf - -C "$STAGE"
fi
SILEO=$JB/Applications/Sileo.app
[[ -x "$SILEO/Sileo" && -x "$SILEO/giveMeRoot" ]] || die "Sileo executables missing"
codesign --force --sign - --timestamp=none --pagesize 4096 \
    --entitlements "$ROOT_DIR/config/uicache.entitlements.plist" --generate-entitlement-der \
    "$JB/usr/bin/uicache"
codesign --force --sign - --timestamp=none --pagesize 4096 \
    --entitlements "$ROOT_DIR/config/sileo-helper.entitlements.plist" --generate-entitlement-der \
    "$SILEO/giveMeRoot"
codesign --force --sign - --timestamp=none --pagesize 4096 \
    --entitlements "$ROOT_DIR/config/sileo.entitlements.plist" --generate-entitlement-der \
    "$SILEO"
codesign --verify --strict "$JB/usr/bin/uicache"
codesign --verify --strict "$SILEO"

LAUNCHCTL=$JB/usr/bin/launchctl
[[ -f "$LAUNCHCTL" ]] || die "bootstrap has no launchctl"
python3 "$ROOT_DIR/scripts/patch-launchctl.py" "$LAUNCHCTL"
codesign --force --sign - --timestamp=none --pagesize 4096 \
    --preserve-metadata=identifier,entitlements "$LAUNCHCTL"

while IFS= read -r package; do
    [[ -z "$package" || "$package" == \#* ]] && continue
    grep -q "^Package: $package$" "$JB/Library/dpkg/status" || \
        die "required package missing after composition: $package"
done < "$ROOT_DIR/config/bootstrap-required-packages.txt"

COPYFILE_DISABLE=1 tar -C "$STAGE" -cpf - . | zstd -19 -T0 -f -o "$OUTPUT.partial" >/dev/null
mv -f "$OUTPUT.partial" "$OUTPUT"
print -- "prepared composed bootstrap: $OUTPUT"
