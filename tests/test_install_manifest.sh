#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/install_manifest.sh
source "$ROOT/scripts/install_manifest.sh"

TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT

SOURCE="$TMP/cmake-install-manifest.txt"
TARGET="$TMP/manifest/aerothemeplasma_install_manifest.txt"
mkdir -p "$(dirname -- "$TARGET")"

cat > "$TARGET" <<'MANIFEST'
/usr/share/aerothemeplasma/old-file.qml
/usr/share/aerothemeplasma/shared-file.qml
/usr/share/aerothemeplasma/old-file.qml
MANIFEST
cat > "$SOURCE" <<'MANIFEST'
/usr/share/aerothemeplasma/new-file.qml
/usr/share/aerothemeplasma/shared-file.qml
/usr/share/aerothemeplasma/file with spaces.qml

MANIFEST

merge_install_manifest "$SOURCE" "$TARGET"

[[ "$(grep -Fxc '/usr/share/aerothemeplasma/old-file.qml' "$TARGET")" -eq 1 ]] || { echo "FAIL: historical path was not preserved exactly once"; exit 1; }
[[ "$(grep -Fxc '/usr/share/aerothemeplasma/new-file.qml' "$TARGET")" -eq 1 ]] || { echo "FAIL: new path was not added exactly once"; exit 1; }
[[ "$(grep -Fxc '/usr/share/aerothemeplasma/shared-file.qml' "$TARGET")" -eq 1 ]] || { echo "FAIL: duplicate path was not deduplicated"; exit 1; }
[[ "$(grep -Fxc '/usr/share/aerothemeplasma/file with spaces.qml' "$TARGET")" -eq 1 ]] || { echo "FAIL: path containing spaces was not preserved"; exit 1; }

before="$(cat "$TARGET")"
merge_install_manifest "$SOURCE" "$TARGET"
after="$(cat "$TARGET")"
[[ "$before" == "$after" ]] || { echo "FAIL: repeated merge changed the manifest"; exit 1; }

if merge_install_manifest "$TMP/missing.txt" "$TARGET" >/dev/null 2>&1; then
    echo "FAIL: missing source manifest was accepted"
    exit 1
fi
[[ "$(cat "$TARGET")" == "$before" ]] || { echo "FAIL: failed merge modified the existing manifest"; exit 1; }

if merge_install_manifest "$SOURCE" "$SOURCE" >/dev/null 2>&1; then
    echo "FAIL: source equal to destination was accepted"
    exit 1
fi

echo "PASS: cumulative install manifests preserve historical paths and deduplicate updates"
