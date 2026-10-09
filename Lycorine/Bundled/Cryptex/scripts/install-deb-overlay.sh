#!/bin/zsh
set -euo pipefail

if (( $# != 3 )); then
    print -u2 -- "usage: install-deb-overlay.sh STAGE PACKAGE.deb STATE"
    exit 2
fi

STAGE=${1:A}
DEB=${2:A}
STATE=$3
SCRIPT_DIR=${0:A:h}
[[ "$STATE" == (unpacked|installed) ]] || { print -u2 -- "invalid dpkg state: $STATE"; exit 2; }
[[ -d "$STAGE/var/jb/Library/dpkg" ]] || { print -u2 -- "invalid bootstrap stage: $STAGE"; exit 2; }
[[ -f "$DEB" ]] || { print -u2 -- "missing deb: $DEB"; exit 2; }

WORK=$(mktemp -d "${TMPDIR:-/private/tmp}/lycorine-deb.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
(
    cd "$WORK"
    /usr/bin/ar -x "$DEB"
)
DATA=($WORK/data.tar.*)
CONTROL=($WORK/control.tar.*)
(( ${#DATA} == 1 && ${#CONTROL} == 1 )) || { print -u2 -- "invalid deb archive: $DEB"; exit 1; }

mkdir -p "$WORK/control"
tar -xpf "$CONTROL[1]" -C "$WORK/control"
PACKAGE=$(awk -F ': *' '$1 == "Package" { print $2; exit }' "$WORK/control/control")
[[ -n "$PACKAGE" ]] || { print -u2 -- "deb has no Package field: $DEB"; exit 1; }

tar -xpf "$DATA[1]" -C "$STAGE"
INFO=$STAGE/var/jb/Library/dpkg/info
mkdir -p "$INFO"
for name in postinst preinst prerm postrm triggers conffiles md5sums; do
    if [[ -f "$WORK/control/$name" ]]; then
        cp "$WORK/control/$name" "$INFO/$PACKAGE.$name"
        [[ "$name" == (postinst|preinst|prerm|postrm) ]] && chmod 755 "$INFO/$PACKAGE.$name"
    fi
done
tar -tf "$DATA[1]" | sed -e 's#^\./#/#' -e 's#/$##' | awk 'NF' > "$INFO/$PACKAGE.list"
python3 "$SCRIPT_DIR/update-dpkg-status.py" \
    "$STAGE/var/jb/Library/dpkg/status" "$WORK/control/control" "$STATE"
print -- "  overlaid $PACKAGE ($STATE)"

