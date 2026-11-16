#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT

REPO="$TMP/repo"
SYSROOT="$TMP/sysroot"
mkdir -p "$REPO/manifest" "$REPO/repos/libplasma/build" "$SYSROOT/usr/share/aerothemeplasma" "$SYSROOT/usr/lib/test"
cp "$ROOT/uninstall.sh" "$REPO/uninstall.sh"

ATP_FILE="$SYSROOT/usr/share/aerothemeplasma/theme-file.dat"
PACKAGE_FILE="$SYSROOT/usr/lib/test/libplasma.so"
printf 'theme payload\n' > "$ATP_FILE"
printf 'package payload\n' > "$PACKAGE_FILE"

cat > "$REPO/manifest/test_install_manifest.txt" <<EOF
/usr/share/aerothemeplasma/theme-file.dat
/usr/lib/test/libplasma.so
/usr/share/aerothemeplasma/theme-file.dat
/etc/outside-the-allowed-root
/usr/../etc/passwd
EOF
cat > "$REPO/repos/libplasma/build/install_manifest.txt" <<EOF
/usr/share/aerothemeplasma/build-manifest-file.dat
EOF
printf 'build payload\\n' > "$SYSROOT/usr/share/aerothemeplasma/build-manifest-file.dat"
printf '/usr/lib/test/libplasma.so\n' > "$TMP/package-owned.txt"

ATP_UNINSTALL_TEST_MODE=1 \
ATP_UNINSTALL_TEST_ROOT="$SYSROOT" \
ATP_UNINSTALL_TEST_OWNED="$TMP/package-owned.txt" \
    bash "$REPO/uninstall.sh" --yes

[[ ! -e "$ATP_FILE" ]] || { echo "FAIL: unowned ATP file was not removed"; exit 1; }
[[ -e "$PACKAGE_FILE" ]] || { echo "FAIL: package-owned file was removed"; exit 1; }
[[ ! -f "$REPO/manifest/test_install_manifest.txt" ]] || { echo "FAIL: consumed manifest remained active"; exit 1; }
[[ ! -f "$REPO/repos/libplasma/build/install_manifest.txt" ]] || { echo "FAIL: build manifest remained active"; exit 1; }
[[ ! -e "$SYSROOT/usr/share/aerothemeplasma/build-manifest-file.dat" ]] || { echo "FAIL: file from build manifest was not removed"; exit 1; }

# Recreate the same path after removal (e.g. the distro package restored it).
# The consumed manifest must not be reused to delete it on a second run.
printf 'restored by distro package\n' > "$ATP_FILE"
ATP_UNINSTALL_TEST_MODE=1 \
ATP_UNINSTALL_TEST_ROOT="$SYSROOT" \
ATP_UNINSTALL_TEST_OWNED="$TMP/package-owned.txt" \
    bash "$REPO/uninstall.sh" --yes

[[ -e "$ATP_FILE" ]] || { echo "FAIL: second uninstall deleted a file restored after the first run"; exit 1; }
[[ -e "$PACKAGE_FILE" ]] || { echo "FAIL: second uninstall deleted the package-owned file"; exit 1; }

# A pending rollback snapshot must still require explicit confirmation even if
# there are no active install manifests left.
set +e
ATP_UNINSTALL_TEST_MODE=1 \
ATP_UNINSTALL_TEST_ROOT="$SYSROOT" \
ATP_UNINSTALL_TEST_ROLLBACK_PENDING=1 \
    bash "$REPO/uninstall.sh" </dev/null >/dev/null 2>&1
status=$?
set -e
[[ "$status" -ne 0 ]] || { echo "FAIL: rollback ran without confirmation"; exit 1; }

echo "PASS: uninstall protects package-owned files, consumes all manifests, and requires rollback confirmation"
