#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
HELPER="$ROOT/scripts/installer_lock.sh"
TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT

LOCK="$TMP/installer.lock"
READY="$TMP/first-process-ready"

bash -c '
    set -Eeuo pipefail
    source "$1"
    acquire_installer_lock "$2"
    : > "$3"
    sleep 1
' bash "$HELPER" "$LOCK" "$READY" &
first_pid=$!

for _ in {1..100}; do
    [[ -e "$READY" ]] && break
    sleep 0.02
done

[[ -e "$READY" ]] || { echo "FAIL: first installer did not acquire the lock"; exit 1; }

set +e
bash -c 'source "$1"; acquire_installer_lock "$2"' bash "$HELPER" "$LOCK" >/dev/null 2>&1
second_status=$?
set -e
[[ "$second_status" -ne 0 ]] || { echo "FAIL: concurrent installer acquired an occupied lock"; exit 1; }

wait "$first_pid"

bash -c 'source "$1"; acquire_installer_lock "$2"' bash "$HELPER" "$LOCK" || {
    echo "FAIL: lock was not released when the first installer exited"
    exit 1
}

SYMLINK_LOCK="$TMP/symlink.lock"
ln -s "$LOCK" "$SYMLINK_LOCK"
set +e
bash -c 'source "$1"; acquire_installer_lock "$2"' bash "$HELPER" "$SYMLINK_LOCK" >/dev/null 2>&1
symlink_status=$?
set -e
[[ "$symlink_status" -ne 0 ]] || { echo "FAIL: symlink lock path was accepted"; exit 1; }

echo "PASS: installer lock prevents concurrent runs, releases on exit, and rejects symlinks"
