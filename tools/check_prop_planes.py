"""Draw every room's declared prop planes over its artwork, so they can be checked.

A prop lying flat on the desk — the phone — has its readout laid into the
surface the picture drew rather than pasted upright over it, which means the
catalog carries four measured corners per room. Corners measured by eye are
easy to get subtly wrong and impossible to check by reading the numbers, so
this prints them back onto the art: if the outline does not sit on the glass,
the entry is wrong.

Writes one crop per room to shots/plane_<room>.png.

Usage: python tools/check_prop_planes.py
"""

import json
import pathlib

from PIL import Image, ImageDraw

CATALOG = pathlib.Path("presentation/asset_catalog.json")
OUT = pathlib.Path("shots")
MARGIN = 0.05


def main() -> None:
    catalog = json.loads(CATALOG.read_text())
    OUT.mkdir(exist_ok=True)
    for room, scene in catalog["board_scenes"].items():
        planes = scene.get("prop_planes")
        if not planes:
            continue
        art = pathlib.Path(scene["art"].replace("res://", ""))
        if not art.exists():
            print("%-20s no art at %s" % (room, art))
            continue
        image = Image.open(art).convert("RGB")
        width, height = image.size
        draw = ImageDraw.Draw(image)
        left, top, right, bottom = 1.0, 1.0, 0.0, 0.0
        for key, quad in planes.items():
            points = [(x * width, y * height) for x, y in quad]
            draw.polygon(points, outline=(255, 70, 70))
            rect = scene["props"].get(key)
            if rect:
                draw.rectangle(
                    [rect[0] * width, rect[1] * height,
                     (rect[0] + rect[2]) * width, (rect[1] + rect[3]) * height],
                    outline=(70, 160, 255),
                )
            left = min(left, min(x for x, _ in quad))
            top = min(top, min(y for _, y in quad))
            right = max(right, max(x for x, _ in quad))
            bottom = max(bottom, max(y for _, y in quad))
        box = (
            max(0, int((left - MARGIN) * width)),
            max(0, int((top - MARGIN) * height)),
            min(width, int((right + MARGIN) * width)),
            min(height, int((bottom + MARGIN) * height)),
        )
        crop = image.crop(box)
        crop = crop.resize((crop.width * 3, crop.height * 3), Image.LANCZOS)
        crop.save(OUT / ("plane_%s.png" % room))
        print("%-20s %s" % (room, OUT / ("plane_%s.png" % room)))


if __name__ == "__main__":
    main()
