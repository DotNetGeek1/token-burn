#!/usr/bin/env python3
"""Inspect a Token Burn AAB for Play target API, arm64, and 16 KB alignment.

Usage:
    python tools/inspect_aab.py path/to/token_burn.aab
    python tools/inspect_aab.py path/to/token_burn.aab --bundletool path/to/bundletool.jar

Exit 0 on pass, 1 on any failure. Prints a short RC report either way.
"""

from __future__ import annotations

import argparse
import io
import struct
import subprocess
import sys
import zipfile
from pathlib import Path
from xml.etree import ElementTree as ET

PT_LOAD = 1
MIN_ALIGN = 0x4000
WANTED_ARCH = "arm64-v8a"
FORBIDDEN_ARCHES = ("armeabi-v7a", "x86", "x86_64")
PACKAGE = "com.tokenburn.game"
TARGET_SDK = "36"
MIN_SDK = "24"
NS = {"android": "http://schemas.android.com/apk/res/android"}


def _elf_load_alignments(data: bytes) -> list[int]:
    if len(data) < 64 or data[:4] != b"\x7fELF":
        raise ValueError("not an ELF")
    ei_class = data[4]
    ei_data = data[5]
    endian = "<" if ei_data == 1 else ">"
    if ei_class == 2:
        e_phoff = struct.unpack_from(endian + "Q", data, 32)[0]
        e_phentsize = struct.unpack_from(endian + "H", data, 54)[0]
        e_phnum = struct.unpack_from(endian + "H", data, 56)[0]
        aligns: list[int] = []
        for i in range(e_phnum):
            off = e_phoff + i * e_phentsize
            p_type = struct.unpack_from(endian + "I", data, off)[0]
            if p_type != PT_LOAD:
                continue
            p_align = struct.unpack_from(endian + "Q", data, off + 48)[0]
            aligns.append(p_align)
        return aligns
    if ei_class == 1:
        e_phoff = struct.unpack_from(endian + "I", data, 28)[0]
        e_phentsize = struct.unpack_from(endian + "H", data, 42)[0]
        e_phnum = struct.unpack_from(endian + "H", data, 44)[0]
        aligns = []
        for i in range(e_phnum):
            off = e_phoff + i * e_phentsize
            p_type = struct.unpack_from(endian + "I", data, off)[0]
            if p_type != PT_LOAD:
                continue
            p_align = struct.unpack_from(endian + "I", data, off + 28)[0]
            aligns.append(p_align)
        return aligns
    raise ValueError("unknown ELF class")


def _so_paths(archive: zipfile.ZipFile) -> list[str]:
    return [name for name in archive.namelist() if name.endswith(".so")]


def _arch_of(path: str) -> str | None:
    parts = path.replace("\\", "/").split("/")
    for marker in ("lib",):
        if marker in parts:
            idx = parts.index(marker)
            if idx + 1 < len(parts):
                return parts[idx + 1]
    return None


def _preset_version_code(repo: Path) -> str | None:
    preset = repo / "export" / "android_export_presets.cfg"
    if not preset.is_file():
        return None
    for line in preset.read_text(encoding="utf-8").splitlines():
        if line.startswith("version/code="):
            return line.split("=", 1)[1].strip()
    return None


def _dump_manifest(bundletool: Path, aab: Path) -> str:
    cmd = ["java", "-jar", str(bundletool), "dump", "manifest", f"--bundle={aab}"]
    result = subprocess.run(cmd, check=False, capture_output=True, text=True)
    if result.returncode != 0:
        raise RuntimeError(result.stderr.strip() or result.stdout.strip() or "bundletool dump failed")
    return result.stdout


def _attr(elem: ET.Element, name: str) -> str:
    return elem.attrib.get(f"{{{NS['android']}}}{name}", elem.attrib.get(name, ""))


def inspect(aab: Path, bundletool: Path | None) -> list[str]:
    failures: list[str] = []
    print(f"AAB: {aab}")
    if not aab.is_file():
        return [f"missing file {aab}"]

    with zipfile.ZipFile(aab) as archive:
        sos = _so_paths(archive)
        arches = sorted({_arch_of(path) or "?" for path in sos})
        print(f"native libraries: {len(sos)}")
        print(f"architectures: {', '.join(arches) if arches else '(none)'}")
        if not any(_arch_of(path) == WANTED_ARCH for path in sos):
            failures.append(f"no {WANTED_ARCH} .so files")
        for path in sos:
            arch = _arch_of(path)
            if arch in FORBIDDEN_ARCHES:
                failures.append(f"forbidden arch {arch} in {path}")
            data = archive.read(path)
            try:
                aligns = _elf_load_alignments(data)
            except ValueError as exc:
                failures.append(f"{path}: {exc}")
                continue
            if not aligns:
                failures.append(f"{path}: no PT_LOAD segments")
                continue
            bad = [align for align in aligns if align < MIN_ALIGN]
            if bad:
                failures.append(
                    f"{path}: PT_LOAD p_align {', '.join(hex(a) for a in bad)} < {hex(MIN_ALIGN)}"
                )
            else:
                print(f"  {path}: 16 KB aligned ({', '.join(hex(a) for a in aligns)})")

    if bundletool is not None:
        try:
            xml = _dump_manifest(bundletool, aab)
        except RuntimeError as exc:
            failures.append(f"bundletool: {exc}")
        else:
            print(xml.strip()[:800])
            root = ET.parse(io.StringIO(xml)).getroot()
            package = root.attrib.get("package", "")
            uses = root.find("uses-sdk")
            min_sdk = _attr(uses, "minSdkVersion") if uses is not None else ""
            target_sdk = _attr(uses, "targetSdkVersion") if uses is not None else ""
            version_code = _attr(root, "versionCode")
            print(f"package={package} minSdk={min_sdk} targetSdk={target_sdk} versionCode={version_code}")
            if package != PACKAGE:
                failures.append(f"package {package!r} != {PACKAGE!r}")
            if min_sdk != MIN_SDK:
                failures.append(f"minSdkVersion {min_sdk!r} != {MIN_SDK!r}")
            if target_sdk != TARGET_SDK:
                failures.append(f"targetSdkVersion {target_sdk!r} != {TARGET_SDK!r}")
            expected = _preset_version_code(Path(__file__).resolve().parents[1])
            if expected and version_code != expected:
                failures.append(f"versionCode {version_code!r} != preset {expected!r}")
    else:
        print("bundletool not supplied; skipped merged-manifest checks")

    return failures


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("aab", type=Path)
    parser.add_argument("--bundletool", type=Path, default=None)
    args = parser.parse_args()
    failures = inspect(args.aab, args.bundletool)
    if failures:
        print("FAIL")
        for item in failures:
            print(f"  - {item}")
        return 1
    print("PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
