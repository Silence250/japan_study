#!/usr/bin/env python3
"""
Cross-platform seed updater.
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]  # .../flutter_app
sys.path.insert(0, str(REPO_ROOT))

import storage


def run(cmd, check=True):
    proc = subprocess.run(cmd, shell=False)
    if check and proc.returncode != 0:
        sys.exit(proc.returncode)
    return proc.returncode


def find_adb(override: str | None) -> str | None:
    if override:
        p = Path(override)
        if p.exists():
            return str(p)
    which = shutil.which("adb")
    if which:
        return which
    candidates = []
    home = Path.home()
    candidates.append(home / "Library/Android/sdk/platform-tools/adb")
    candidates.append(home / "Android/Sdk/platform-tools/adb")
    if os.name == "nt":
        local = os.environ.get("LOCALAPPDATA")
        if local:
            candidates.append(Path(local) / "Android/Sdk/platform-tools/adb.exe")
    for c in candidates:
        if c.exists():
            return str(c)
    return None


def adb_devices(adb_path: str) -> bool:
    try:
        out = subprocess.check_output([adb_path, "devices"], text=True)
    except Exception:
        return False
    for line in out.splitlines():
        if "\tdevice" in line:
            return True
    return False


def main():
    parser = argparse.ArgumentParser(description="Update seed incrementally.")
    parser.add_argument("--sessions", required=True)
    parser.add_argument("--seed", default="assets/questions_seed.json")
    parser.add_argument("--tmp", default="tmp_seed.json")
    parser.add_argument("--prefer-new", action="store_true")
    parser.add_argument("--install-android", action="store_true")
    parser.add_argument("--adb", default=None)
    args = parser.parse_args()

    seed_path = Path(args.seed)
    tmp_path = Path(args.tmp)

    # Run scraper
    run([sys.executable, "scrape.py", "--sessions", args.sessions, "--out", str(tmp_path)])

    # Merge
    added, replaced, merged = storage.merge_seed_files(
        seed_path, tmp_path, seed_path, prefer_new=args.prefer_new
    )
    summary = storage.summarize(merged)
    print(f"Added: {added}, Replaced: {replaced}, Total: {summary['total']}")
    print(f"Per-year: {summary['per_year']}")
    print(f"Per-category: {summary['per_category']}")

    if not args.install_android:
        return

    adb_path = find_adb(args.adb)
    if not adb_path:
        print("adb not found; skipping install")
        return
    if not adb_devices(adb_path):
        print("No android device detected; skipping install")
        return

    run(["flutter", "build", "apk", "--debug"])
    apk = Path("build/app/outputs/flutter-apk/app-debug.apk")
    if not apk.exists():
        print("APK not found after build; skipping install")
        return
    run([adb_path, "install", "-r", str(apk)])


if __name__ == "__main__":
    main()
