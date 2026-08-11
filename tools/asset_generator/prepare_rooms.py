"""Crops generated room art to the 16:9 viewport and writes it into presentation/board.

The generator returns 3:2 frames whatever aspect it is asked for, and the game
stretches the desk art across a 16:9 window, so an uncropped frame would squash
every object in the room by a fifth. Cropping to the target aspect keeps the
laptop looking like a laptop and keeps the prop fractions honest.
"""

from pathlib import Path
import sys

from PIL import Image

TARGET = (1920, 1080)
ASPECT = TARGET[0] / TARGET[1]

ROOMS = [
    "bedroom",
    "garage",
    "office_unit",
    "warehouse",
    "datacentre_campus",
    "private_power_grid",
    "moon_facility",
]


def main() -> None:
    source_dir = Path(sys.argv[1])
    prefix = sys.argv[2] if len(sys.argv) > 2 else "room"
    out_dir = Path(__file__).resolve().parents[2] / "presentation" / "board"
    out_dir.mkdir(parents=True, exist_ok=True)
    for room in ROOMS:
        source = source_dir / f"{prefix}_{room}.png"
        image = Image.open(source).convert("RGB")
        width, height = image.size
        wanted_height = int(round(width / ASPECT))
        if wanted_height <= height:
            excess = height - wanted_height
            top = excess // 2
            image = image.crop((0, top, width, top + wanted_height))
        else:
            wanted_width = int(round(height * ASPECT))
            left = (width - wanted_width) // 2
            image = image.crop((left, 0, left + wanted_width, height))
        image = image.resize(TARGET, Image.LANCZOS)
        destination = out_dir / f"room_{room}.png"
        image.save(destination)
        print(f"{room}: {width}x{height} -> {destination.name}")


if __name__ == "__main__":
    main()
