#!/usr/bin/env python3
"""Restore AeroThemePlasma configuration snapshots without clobbering later edits."""

from __future__ import annotations

import argparse
import base64
import hashlib
import json
import os
import pwd
from pathlib import Path
import tempfile
from typing import Iterable


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def is_within(path: Path, roots: Iterable[Path]) -> bool:
    resolved = path.parent.resolve() / path.name
    for root in roots:
        try:
            resolved.relative_to(root.resolve())
            return True
        except ValueError:
            continue
    return False


def atomic_write(
    path: Path,
    data: bytes,
    mode: int,
    owner_id: int | None = None,
    group_id: int | None = None,
) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary = tempfile.mkstemp(prefix=".atp-restore-", dir=path.parent)
    try:
        with os.fdopen(descriptor, "wb") as stream:
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        if owner_id is not None and group_id is not None and owner_id >= 0 and group_id >= 0:
            os.chown(temporary, owner_id, group_id)
        os.chmod(temporary, mode & 0o777)
        os.replace(temporary, path)
    except Exception:
        try:
            os.unlink(temporary)
        except FileNotFoundError:
            pass
        raise


def atomic_json(path: Path, document: dict) -> None:
    encoded = json.dumps(document, separators=(",", ":")).encode("utf-8")
    atomic_write(path, encoded, 0o600)


def restore_manifest(manifest_path: Path, allowed_roots: Iterable[Path]) -> tuple[int, int]:
    """Return (restored_count, conflict_count); raise on malformed/unsafe input."""
    manifest_path = manifest_path.absolute()
    document = json.loads(manifest_path.read_text(encoding="utf-8"))
    if document.get("version") != 1 or not isinstance(document.get("files"), list):
        raise ValueError("unsupported rollback manifest")

    restored = 0
    conflicts = 0
    entries = document["files"]
    document["restore_started"] = True
    atomic_json(manifest_path, document)

    for entry in entries:
        if entry.get("restored") or entry.get("skipped"):
            continue

        path = Path(entry.get("path", ""))
        if not path.is_absolute() or not is_within(path, allowed_roots):
            raise ValueError(f"refusing path outside allowed roots: {path}")
        if entry.get("expected_unsafe"):
            print(f"CONFLICT: {path} changed type or link target; left untouched")
            conflicts += 1
            continue

        target = path
        if entry.get("is_symlink"):
            if not path.is_symlink():
                print(f"CONFLICT: {path} is no longer the original symbolic link; left untouched")
                conflicts += 1
                continue
            recorded_target = Path(entry.get("symlink_target", "")).resolve()
            try:
                target = path.resolve(strict=True)
            except OSError:
                print(f"CONFLICT: {path} no longer resolves to its original target; left untouched")
                conflicts += 1
                continue
            if target != recorded_target or not is_within(target, allowed_roots):
                print(f"CONFLICT: symbolic-link target for {path} is outside the rollback scope; left untouched")
                conflicts += 1
                continue
        elif path.is_symlink():
            print(f"CONFLICT: {path} became a symbolic link; left untouched")
            conflicts += 1
            continue

        expected_exists = bool(entry.get("expected_exists"))
        currently_exists = target.exists()
        unchanged = currently_exists == expected_exists

        if unchanged and currently_exists:
            if not target.is_file():
                unchanged = False
            else:
                expected_hash = entry.get("expected_sha256", "")
                unchanged = bool(expected_hash) and sha256_file(target) == expected_hash

        if not unchanged:
            print(f"CONFLICT: {path} changed after AeroThemePlasma applied it; left untouched")
            conflicts += 1
            continue

        if entry.get("original_exists"):
            encoded = entry.get("original_data", "")
            original = base64.b64decode(encoded, validate=True)
            atomic_write(
                target,
                original,
                int(entry.get("original_permissions", 0o600)),
                entry.get("original_owner_id"),
                entry.get("original_group_id"),
            )
        elif currently_exists:
            target.unlink()

        entry["restored"] = True
        atomic_json(manifest_path, document)
        restored += 1
        print(f"RESTORED: {path}")

    pending = [
        entry for entry in entries
        if not entry.get("restored") and not entry.get("skipped")
    ]
    if not pending:
        manifest_path.unlink(missing_ok=True)
        try:
            manifest_path.parent.rmdir()
        except OSError:
            pass

    return restored, conflicts


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--scope", choices=("user", "system"), required=True)
    args = parser.parse_args()

    if args.scope == "user":
        config_home = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config"))
        manifest = config_home / "aerothemeplasma" / "rollback" / "user.json"
        roots = [config_home, Path.home()]
    else:
        manifest = Path("/var/lib/aerothemeplasma/rollback/system.json")
        try:
            sddm_home = Path(pwd.getpwnam("sddm").pw_dir)
        except KeyError:
            sddm_home = Path("/var/lib/sddm")
        roots = [
            Path("/etc"),
            Path("/usr/share/icons"),
            sddm_home,
        ]

    if not manifest.exists():
        print(f"No {args.scope} rollback snapshot found; nothing to restore.")
        return 0

    try:
        restored, conflicts = restore_manifest(manifest, roots)
    except (OSError, ValueError, json.JSONDecodeError) as error:
        print(f"ERROR: rollback stopped safely: {error}")
        return 1

    print(f"{args.scope.capitalize()} rollback: {restored} file(s) restored, {conflicts} conflict(s).")
    if conflicts:
        print(f"Snapshot retained for manual review: {manifest}")
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
