from __future__ import annotations

import base64
import importlib.util
import json
import os
from pathlib import Path
import tempfile
import unittest


MODULE_PATH = Path(__file__).resolve().parents[1] / "scripts" / "restore_config.py"
SPEC = importlib.util.spec_from_file_location("restore_config", MODULE_PATH)
restore_config = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(restore_config)


def make_manifest(path: Path, original: bytes | None, expected: bytes | None) -> dict:
    return {
        "version": 1,
        "files": [{
            "path": str(path),
            "original_exists": original is not None,
            "original_data": base64.b64encode(original or b"").decode("ascii"),
            "original_permissions": 0o640,
            "expected_exists": expected is not None,
            "expected_sha256": (
                __import__("hashlib").sha256(expected).hexdigest()
                if expected is not None else ""
            ),
        }],
    }


class RollbackTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name) / "config"
        self.root.mkdir()
        self.state = self.root / "aerothemeplasma" / "rollback" / "user.json"
        self.state.parent.mkdir(parents=True)

    def tearDown(self) -> None:
        self.temp.cleanup()

    def write_manifest(self, document: dict) -> None:
        self.state.write_text(json.dumps(document), encoding="utf-8")

    def test_restores_original_file_and_mode_when_unchanged(self) -> None:
        target = self.root / "kdeglobals"
        original = b"[General]\nColorScheme=Breeze\n"
        applied = b"[General]\nColorScheme=Aero\n"
        target.write_bytes(applied)
        target.chmod(0o600)
        self.write_manifest(make_manifest(target, original, applied))

        restored, conflicts = restore_config.restore_manifest(self.state, [self.root])

        self.assertEqual((restored, conflicts), (1, 0))
        self.assertEqual(target.read_bytes(), original)
        self.assertEqual(target.stat().st_mode & 0o777, 0o640)
        self.assertFalse(self.state.exists())

    def test_removes_file_created_by_theme_when_still_unchanged(self) -> None:
        target = self.root / "kwinrulesrc"
        applied = b"[Rules]\n"
        target.write_bytes(applied)
        self.write_manifest(make_manifest(target, None, applied))

        restored, conflicts = restore_config.restore_manifest(self.state, [self.root])

        self.assertEqual((restored, conflicts), (1, 0))
        self.assertFalse(target.exists())

    def test_preserves_user_edit_and_keeps_backup_for_manual_review(self) -> None:
        target = self.root / "kwinrc"
        original = b"[Windows]\nBorderlessMaximizedWindows=false\n"
        applied = b"[Windows]\nBorderlessMaximizedWindows=true\n"
        later_user_edit = b"[Windows]\nBorderlessMaximizedWindows=false\nPlacement=Centered\n"
        target.write_bytes(later_user_edit)
        self.write_manifest(make_manifest(target, original, applied))

        restored, conflicts = restore_config.restore_manifest(self.state, [self.root])

        self.assertEqual((restored, conflicts), (0, 1))
        self.assertEqual(target.read_bytes(), later_user_edit)
        self.assertTrue(self.state.exists())


    def test_restores_target_of_managed_dotfile_symlink_without_replacing_link(self) -> None:
        target = self.root / "dotfiles" / "kdeglobals"
        link = self.root / "kdeglobals"
        original = b"[General]\\nColorScheme=Breeze\\n"
        applied = b"[General]\\nColorScheme=Aero\\n"
        target.parent.mkdir()
        target.write_bytes(applied)
        target.chmod(0o600)
        link.symlink_to(target)
        document = make_manifest(link, original, applied)
        document["files"][0]["is_symlink"] = True
        document["files"][0]["symlink_target"] = str(target.resolve())
        self.write_manifest(document)

        restored, conflicts = restore_config.restore_manifest(self.state, [self.root])

        self.assertEqual((restored, conflicts), (1, 0))
        self.assertTrue(link.is_symlink())
        self.assertEqual(link.resolve(), target)
        self.assertEqual(target.read_bytes(), original)
        self.assertEqual(target.stat().st_mode & 0o777, 0o640)

    def test_rejects_path_outside_allowed_root(self) -> None:
        outside = Path(self.temp.name) / "outside.conf"
        outside.write_text("user data", encoding="utf-8")
        self.write_manifest(make_manifest(outside, b"old", b"user data"))

        with self.assertRaises(ValueError):
            restore_config.restore_manifest(self.state, [self.root])

        self.assertEqual(outside.read_text(encoding="utf-8"), "user data")

    def test_does_not_follow_symlink_created_after_theme_application(self) -> None:
        target = self.root / "linked.conf"
        external = Path(self.temp.name) / "external.conf"
        external.write_text("do not touch", encoding="utf-8")
        applied = b"theme config"
        target.symlink_to(external)
        self.write_manifest(make_manifest(target, b"original", applied))

        restored, conflicts = restore_config.restore_manifest(self.state, [self.root])

        self.assertEqual((restored, conflicts), (0, 1))
        self.assertEqual(external.read_text(encoding="utf-8"), "do not touch")
        self.assertTrue(target.is_symlink())


if __name__ == "__main__":
    unittest.main()
