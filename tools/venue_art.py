"""Normalises a generated venue backdrop to the shape the venue chassis expects.

Venue regions are authored as normalised rects against the art (the `venue_scenes`
block in presentation/asset_catalog.json), so the art has to be exactly the
design aspect or the painted panels drift away from the UI mounted into them.
Crops to 16:9 about a configurable vertical bias, then resamples to 1920x1080.

    python tools/venue_art.py <source.png> <destination.png> [bias]

`bias` is where the crop window sits vertically, 0.0 (keep the top) to 1.0 (keep
the bottom). Defaults to centred.
"""

import sys

from PIL import Image

TARGET = (1920, 1080)
ASPECT = TARGET[0] / TARGET[1]


def normalise(source: str, destination: str, bias: float = 0.5) -> None:
    image = Image.open(source).convert("RGB")
    width, height = image.size
    if width / height > ASPECT:
        crop_width = round(height * ASPECT)
        left = round((width - crop_width) * 0.5)
        box = (left, 0, left + crop_width, height)
    else:
        crop_height = round(width / ASPECT)
        top = round((height - crop_height) * bias)
        box = (0, top, width, top + crop_height)
    image.crop(box).resize(TARGET, Image.LANCZOS).save(destination, optimize=True)
    print(f"{source} {width}x{height} -> {destination} {TARGET[0]}x{TARGET[1]}")


if __name__ == "__main__":
    if len(sys.argv) < 3:
        raise SystemExit(__doc__)
    normalise(
        sys.argv[1],
        sys.argv[2],
        float(sys.argv[3]) if len(sys.argv) > 3 else 0.5,
    )
