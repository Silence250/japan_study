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
import re

REPO_ROOT = Path(__file__).resolve().parents[1]  # .../flutter_app
sys.path.insert(0, str(REPO_ROOT))

import storage


def run(cmd, check=True, cwd=None):
    proc = subprocess.run(cmd, shell=False, cwd=cwd)
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


def find_flutter(override: str | None) -> str | None:
    if override:
        p = Path(override)
        if p.exists():
            return str(p)
    which = shutil.which("flutter")
    if which:
        return which
    candidates = []
    if os.name == "nt":
        candidates.extend(
            [
                Path("C:/src/flutter/bin/flutter.bat"),
                Path(os.environ.get("USERPROFILE", "")) / "flutter/bin/flutter.bat",
            ]
        )
    else:
        candidates.append(Path.home() / "flutter/bin/flutter")
    for c in candidates:
        if c.exists():
            return str(c)
    return None


def parse_application_id(build_gradle: Path) -> str | None:
    if not build_gradle.exists():
        return None
    text = build_gradle.read_text(encoding="utf-8", errors="ignore")
    for line in text.splitlines():
        if "applicationId" not in line:
            continue
        # applicationId "com.example.app"  OR applicationId = "com.example.app"
        m = re.search(r'applicationId\s*(=)?\s*\"([^\"]+)\"', line)
        if m:
            return m.group(2)
    return None


def parse_manifest_package(manifest: Path) -> str | None:
    if not manifest.exists():
        return None
    text = manifest.read_text(encoding="utf-8", errors="ignore")
    m = re.search(r'package="([^"]+)"', text)
    if m:
        return m.group(1)
    return None


def main():
    parser = argparse.ArgumentParser(description="Update seed incrementally.")
    parser.add_argument("--sessions", required=True)
    parser.add_argument("--seed", default="assets/questions_seed.json")
    parser.add_argument("--tmp", default="tmp_seed.json")
    parser.add_argument("--prefer-new", action="store_true")
    parser.add_argument("--install-android", action="store_true", help="Legacy flag; same as --run")
    parser.add_argument("--run", action="store_true", help="Install and launch on Android after update")
    parser.add_argument("--clear-data", action="store_true", help="adb pm clear <package> before launch (dev only)")
    parser.add_argument("--package", default=None, help="Override Android applicationId/package name")
    parser.add_argument("--flutter", default=None, help="Override flutter executable path")
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

    if not (args.run or args.install_android):
        return

    adb_path = find_adb(args.adb)
    if not adb_path:
        print("adb not found; skipping install")
        return
    if not adb_devices(adb_path):
        print("No android device detected; skipping install")
        return

    searched = []
    package_name = None
    if args.package:
        package_name = args.package
    else:
        for path in [
            REPO_ROOT / "android" / "app" / "build.gradle",
            REPO_ROOT / "android" / "app" / "build.gradle.kts",
        ]:
            searched.append(path)
            package_name = parse_application_id(path)
            if package_name:
                break
        if not package_name:
            manifest_path = REPO_ROOT / "android" / "app" / "src" / "main" / "AndroidManifest.xml"
            searched.append(manifest_path)
            package_name = parse_manifest_package(manifest_path)

    flutter_path = find_flutter(args.flutter)
    if not flutter_path:
        print(
            "flutter not found; install Flutter and ensure `flutter` is on PATH or pass --flutter. Skipping run."
        )
        return

    run([flutter_path, "build", "apk", "--debug"], cwd=str(REPO_ROOT))
    apk = Path("build/app/outputs/flutter-apk/app-debug.apk")
    if not apk.exists():
        print("APK not found after build; skipping install")
        return
    run([adb_path, "install", "-r", str(apk)], cwd=str(REPO_ROOT))
    if package_name:
        if args.clear_data:
            print(f"Clearing app data for {package_name}")
            run([adb_path, "shell", "pm", "clear", package_name], check=False)
        print(f"Force stopping {package_name}")
        run([adb_path, "shell", "am", "force-stop", package_name], check=False)
        launch_cmd = [
            adb_path,
            "shell",
            "monkey",
            "-p",
            package_name,
            "-c",
            "android.intent.category.LAUNCHER",
            "1",
        ]
        print(f"Launching {package_name} via: {' '.join(launch_cmd)}")
        run(launch_cmd, check=False)
    else:
        print("Could not determine package/applicationId; searched:")
        for p in searched:
            print(f" - {p}")
        print("Install finished; pass --package to launch automatically.")


if __name__ == "__main__":
    main()
