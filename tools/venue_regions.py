"""Draws a venue's authored regions over its artwork, so the rects in
presentation/asset_catalog.json can be checked against the panels the picture
actually painted without booting the game.

    python tools/venue_regions.py            # every venue with art
    python tools/venue_regions.py market     # just one

Writes tools/shots/regions_<venue>.png. A grid at 10% intervals is drawn behind
the rects so a rect that has drifted can be re-measured off the same image.
"""

import json
import sys
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
CATALOG = ROOT / "presentation" / "asset_catalog.json"
OUT = ROOT / "tools" / "shots"

GRID = (70, 70, 70)
RECT = (0, 255, 120)
LABEL = (255, 255, 0)


def load_venues() -> dict:
    data = json.loads(CATALOG.read_text(encoding="utf-8"))
    return data.get("venue_scenes", {}), data.get("venue_defaults", {})


def resolve(entry: dict, defaults: dict) -> dict:
    regions = dict(defaults.get("regions", {}))
    regions.update(entry.get("regions", {}))
    return regions


def preview(name: str, entry: dict, defaults: dict) -> None:
    art = entry.get("art", "")
    path = ROOT / art.removeprefix("res://")
    if not art or not path.exists():
        print(f"{name}: no art at {art}")
        return
    image = Image.open(path).convert("RGB")
    width, height = image.size
    draw = ImageDraw.Draw(image)

    for step in range(1, 10):
        x = width * step / 10
        y = height * step / 10
        draw.line([(x, 0), (x, height)], fill=GRID)
        draw.line([(0, y), (width, y)], fill=GRID)

    for key, rect in resolve(entry, defaults).items():
        left, top, box_w, box_h = (float(v) for v in rect)
        box = (left * width, top * height, (left + box_w) * width, (top + box_h) * height)
        draw.rectangle(box, outline=RECT, width=3)
        draw.text((box[0] + 6, box[1] + 6), key.upper(), fill=LABEL)

    OUT.mkdir(parents=True, exist_ok=True)
    destination = OUT / f"regions_{name}.png"
    image.save(destination)
    print(f"{name} -> {destination}")


def main() -> None:
    venues, defaults = load_venues()
    wanted = sys.argv[1:] or list(venues)
    for name in wanted:
        if name not in venues:
            print(f"{name}: not in venue_scenes")
            continue
        preview(name, venues[name], defaults)


if __name__ == "__main__":
    main()
