#!/bin/sh
set -eu

: "${CRYPTEX_MOUNT_PATH:?missing CRYPTEX_MOUNT_PATH}"
TOYBOX="$CRYPTEX_MOUNT_PATH/usr/bin/toybox"
SSH_KEYGEN="$CRYPTEX_MOUNT_PATH/usr/bin/ssh-keygen"
SSHD="$CRYPTEX_MOUNT_PATH/usr/sbin/sshd"
KEY_DIR=/var/root/.ssh
AUTHORIZED_KEYS="$KEY_DIR/authorized_keys"
HOST_KEY="$KEY_DIR/lycorine_ssh_host_ed25519_key"

"$TOYBOX" mkdir -p "$KEY_DIR" /var/empty
"$TOYBOX" chmod 700 "$KEY_DIR"
"$TOYBOX" touch "$AUTHORIZED_KEYS"

KEY_FILE="$CRYPTEX_MOUNT_PATH/etc/lycorine_authorized_key"
if [ -s "$KEY_FILE" ]; then
    KEY=$(awk 'NF { print; exit }' "$KEY_FILE")
    if [ -n "$KEY" ] && ! "$TOYBOX" grep -qxF "$KEY" "$AUTHORIZED_KEYS"; then
        printf '%s\n' "$KEY" >> "$AUTHORIZED_KEYS"
    fi
fi
"$TOYBOX" chmod 600 "$AUTHORIZED_KEYS"

if [ ! -s "$HOST_KEY" ]; then
    "$SSH_KEYGEN" -q -t ed25519 -N '' -f "$HOST_KEY"
fi
"$TOYBOX" chmod 600 "$HOST_KEY"

exec "$SSHD" -D -e -f "$CRYPTEX_MOUNT_PATH/etc/ssh/sshd_config"
