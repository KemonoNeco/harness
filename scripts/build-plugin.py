#!/usr/bin/env python3
"""Package plugin/ into dist/harness.plugin and dist/harness.zip.

The Claude webapp accepts only .plugin or .zip uploads. Both files are the
same archive with different extensions; the webapp treats them identically.

The archive places the plugin manifest (.claude-plugin/plugin.json) and all
component directories (hooks/, skills/, CLAUDE.md) at the archive root — NOT
under a plugin/ wrapper directory. This matches what `claude plugin validate`
and the webapp's installer both expect.

Usage:
    python scripts/build-plugin.py           # writes dist/harness.{plugin,zip}
    python scripts/build-plugin.py --clean   # removes dist/ first
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


def validate_source() -> None:
    manifest = PLUGIN_SRC / ".claude-plugin" / "plugin.json"
    if not manifest.is_file():
        sys.exit(f"error: manifest not found at {manifest}")
    hooks_json = PLUGIN_SRC / "hooks" / "hooks.json"
    if not hooks_json.is_file():
        sys.exit(f"error: hooks config not found at {hooks_json}")


def build_zip(out: Path) -> None:
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as zf:
        for root, dirs, files in os.walk(PLUGIN_SRC):
            dirs.sort()
            files.sort()
            for f in files:
                abs_p = Path(root) / f
                rel = abs_p.relative_to(PLUGIN_SRC).as_posix()
                zf.write(abs_p, rel)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--clean", action="store_true", help="remove dist/ first")
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
    return 0


if __name__ == "__main__":
    sys.exit(main())
