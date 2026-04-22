#!/usr/bin/env python3
"""Package plugin/ into dist/harness.plugin and dist/harness.zip.

The Claude webapp accepts only .plugin or .zip uploads. Both files are the
same archive with different extensions; the webapp treats them identically.

The archive places the plugin manifest (.claude-plugin/plugin.json) and all
component directories (hooks/, skills/, CLAUDE.md) at the archive root — NOT
under a plugin/ wrapper directory. This matches what `claude plugin validate`
and the webapp's installer both expect.

The build is deterministic: same source bytes → same archive bytes. That
lets CI verify that the committed harness.plugin at the repo root is in
sync with the plugin/ sources (run with --check).

Usage:
    python scripts/build-plugin.py           # build + copy to repo-root harness.plugin
    python scripts/build-plugin.py --clean   # also removes dist/ first
    python scripts/build-plugin.py --check   # CI: fail if committed .plugin is stale
"""
from __future__ import annotations

import argparse
import os
import shutil
import sys
import zipfile
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
PLUGIN_SRC = REPO_ROOT / "plugin"
DIST_DIR = REPO_ROOT / "dist"
PUBLISHED_PLUGIN = REPO_ROOT / "harness.plugin"


def validate_source() -> None:
    manifest = PLUGIN_SRC / ".claude-plugin" / "plugin.json"
    if not manifest.is_file():
        sys.exit(f"error: manifest not found at {manifest}")
    hooks_json = PLUGIN_SRC / "hooks" / "hooks.json"
    if not hooks_json.is_file():
        sys.exit(f"error: hooks config not found at {hooks_json}")


TEXT_EXTENSIONS = {".md", ".sh", ".json", ".yml", ".yaml", ".txt"}


def read_normalised(path: Path) -> bytes:
    """Read a file and normalise line endings to LF if it's text.

    The plugin has no binary assets today, but guard by extension anyway
    so a future PNG/ICO doesn't get corrupted. Normalising on read makes
    the archive deterministic regardless of how git checked out the
    working tree — Windows autocrlf can't perturb the result.
    """
    raw = path.read_bytes()
    if path.suffix.lower() in TEXT_EXTENSIONS:
        # CRLF → LF, and a stray CR → LF (old Mac line endings). Idempotent.
        raw = raw.replace(b"\r\n", b"\n").replace(b"\r", b"\n")
    return raw


def build_zip(out: Path) -> None:
    """Write a deterministic zip of plugin/ contents to `out`.

    Deterministic means: same source bytes in git → same archive bytes.
    Achieved by (a) walking entries in sorted order, (b) fixing the mtime
    of every entry to a constant, (c) writing files via ZipInfo so mode
    bits don't vary with the host OS, (d) normalising line endings to LF
    on text files so Windows autocrlf checkouts can't perturb bytes.
    """
    CONST_TIME = (1980, 1, 1, 0, 0, 0)
    entries: list[tuple[str, Path]] = []
    for root, dirs, files in os.walk(PLUGIN_SRC):
        dirs.sort()
        files.sort()
        for f in files:
            abs_p = Path(root) / f
            rel = abs_p.relative_to(PLUGIN_SRC).as_posix()
            entries.append((rel, abs_p))
    entries.sort(key=lambda t: t[0])

    with zipfile.ZipFile(out, "w", zipfile.ZIP_STORED) as zf:
        for rel, abs_p in entries:
            zi = zipfile.ZipInfo(filename=rel, date_time=CONST_TIME)
            zi.compress_type = zipfile.ZIP_STORED
            # Preserve executable bit for .sh hooks; else mode 0o644.
            zi.external_attr = (
                (0o755 if rel.endswith(".sh") else 0o644) << 16
            )
            zf.writestr(zi, read_normalised(abs_p))


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--clean", action="store_true", help="remove dist/ first")
    ap.add_argument(
        "--check",
        action="store_true",
        help=(
            "build to dist/ and compare against the committed harness.plugin; "
            "exit non-zero if they differ. Used by CI to catch stale artifacts."
        ),
    )
    args = ap.parse_args()

    validate_source()

    if args.clean and DIST_DIR.exists():
        shutil.rmtree(DIST_DIR)
    DIST_DIR.mkdir(exist_ok=True)

    zip_path = DIST_DIR / "harness.zip"
    plugin_path = DIST_DIR / "harness.plugin"

    build_zip(zip_path)
    shutil.copyfile(zip_path, plugin_path)

    print(f"wrote {zip_path} ({zip_path.stat().st_size} bytes)")
    print(f"wrote {plugin_path} ({plugin_path.stat().st_size} bytes)")
    print("archive contents:")
    with zipfile.ZipFile(zip_path) as zf:
        for name in zf.namelist():
            print(f"  {name}")

    if args.check:
        if not PUBLISHED_PLUGIN.is_file():
            print(
                f"error: {PUBLISHED_PLUGIN.name} is missing at the repo root. "
                f"Run `python scripts/build-plugin.py` and commit the result.",
                file=sys.stderr,
            )
            return 1
        if PUBLISHED_PLUGIN.read_bytes() != plugin_path.read_bytes():
            print(
                f"error: committed {PUBLISHED_PLUGIN.name} is stale. "
                f"Run `python scripts/build-plugin.py` and commit the updated file.",
                file=sys.stderr,
            )
            return 1
        print(f"ok: committed {PUBLISHED_PLUGIN.name} matches freshly-built archive")
    else:
        # Copy to the repo root so `git status` surfaces a stale artifact.
        shutil.copyfile(plugin_path, PUBLISHED_PLUGIN)
        print(f"wrote {PUBLISHED_PLUGIN} ({PUBLISHED_PLUGIN.stat().st_size} bytes)")

    return 0


if __name__ == "__main__":
    sys.exit(main())
