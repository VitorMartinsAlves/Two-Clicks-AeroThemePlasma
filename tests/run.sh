#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

echo "==> Bash syntax checks"
for script in install.sh uninstall.sh migration-uninstall.sh scripts/setup_terminal.sh scripts/install_manifest.sh scripts/installer_lock.sh tests/test_install_manifest.sh tests/test_installer_lock.sh tests/test_uninstall.sh tests/run.sh; do
    bash -n "$script"
done

echo "==> Python rollback tests"
python3 -m unittest discover -s tests -p 'test_*.py' -v

echo "==> Cumulative install manifest tests"
bash tests/test_install_manifest.sh

echo "==> Installer concurrency lock tests"
bash tests/test_installer_lock.sh

echo "==> Installer/uninstaller integration test"
bash tests/test_uninstall.sh

if command -v shellcheck >/dev/null 2>&1; then
    echo "==> ShellCheck"
    shellcheck -x install.sh uninstall.sh scripts/install_manifest.sh scripts/installer_lock.sh tests/run.sh tests/test_install_manifest.sh tests/test_installer_lock.sh tests/test_uninstall.sh
else
    echo "==> ShellCheck not installed; skipped"
fi

echo "All repository safety tests passed."
