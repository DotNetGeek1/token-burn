#!/usr/bin/env python3
"""Merge export/android_export_presets.cfg into export_presets.cfg.

The Android template is the source of truth for the Android preset. An
existing Web (or other) preset is left in place.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
TEMPLATE = REPO / "export" / "android_export_presets.cfg"
DEST = REPO / "export_presets.cfg"


def _indices(text: str) -> list[int]:
    return [int(m.group(1)) for m in re.finditer(r"\[preset\.(\d+)\]", text)]


def _remap(template: str, index: int) -> str:
    if index == 0:
        return template
    return re.sub(r"preset\.0", f"preset.{index}", template)


def merge() -> None:
    template = TEMPLATE.read_text(encoding="utf-8")
    if not DEST.is_file():
        DEST.write_text(template, encoding="utf-8", newline="\n")
        print(f"Wrote {DEST} from the Android template.")
        return
    dest = DEST.read_text(encoding="utf-8")
    named = re.search(
        r'(?ms)^\[preset\.(\d+)\]\s*\n(?:(?!^\[preset\.\d+\]).)*?^name="Android"',
        dest,
    )
    if named is None:
        next_index = (max(_indices(dest)) + 1) if _indices(dest) else 0
        DEST.write_text(
            dest.rstrip() + "\n\n" + _remap(template, next_index).lstrip(),
            encoding="utf-8",
            newline="\n",
        )
        print(f"Appended Android preset as preset.{next_index}.")
        return
    index = int(named.group(1))
    block = re.compile(
        rf"(?ms)^\[preset\.{index}\]\n.*?(?=^\[preset\.(?!{index}\b)\d+\]|\Z)"
    )
    replacement = _remap(template, index).strip() + "\n"
    updated, count = block.subn(replacement, dest, count=1)
    if count != 1:
        raise SystemExit("Could not replace the existing Android preset block.")
    DEST.write_text(updated, encoding="utf-8", newline="\n")
    print(f"Replaced Android preset.{index} from the committed template.")


if __name__ == "__main__":
    try:
        merge()
    except OSError as exc:
        print(exc, file=sys.stderr)
        sys.exit(1)
