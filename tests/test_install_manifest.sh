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

# A missing generated manifest is a hard failure, not a warning that allows
# the installer to report success without a persistent uninstall inventory.
if record_install_manifest "$TMP/missing-generated-manifest.txt" "$TARGET" >/dev/null 2>&1; then
    echo "FAIL: missing generated manifest was silently accepted"
    exit 1
fi
[[ "$(cat "$TARGET")" == "$before" ]] || { echo "FAIL: missing manifest changed the persistent inventory"; exit 1; }

# A directory must not be accepted in place of a generated manifest either.
mkdir -p "$TMP/not-a-manifest"
if record_install_manifest "$TMP/not-a-manifest" "$TARGET" >/dev/null 2>&1; then
    echo "FAIL: directory was accepted as a generated manifest"
    exit 1
fi
[[ "$(cat "$TARGET")" == "$before" ]] || { echo "FAIL: invalid manifest changed the persistent inventory"; exit 1; }

# Valid generated manifest must be recorded as part of the component install.
record_install_manifest "$SOURCE" "$TARGET"
[[ "$(grep -Fxc '/usr/share/aerothemeplasma/new-file.qml' "$TARGET")" -eq 1 ]] || { echo "FAIL: required manifest record was not persisted"; exit 1; }

echo "PASS: cumulative manifests are retained and every successful component install requires a readable manifest"
