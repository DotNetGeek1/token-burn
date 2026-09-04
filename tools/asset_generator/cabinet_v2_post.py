"""Post-processes generated Burn Cabinet v2 art into game-ready PNGs.

The generator returns opaque 1280x720 / 1024x1024 / 720x1280 frames with every
opening and every background painted pure black. This tool turns those into the
layers the cabinet mounts: openings knocked to alpha, state sheets sliced into
cells, tier rows sliced into square tiles, everything resized onto its final
canvas. It only ever reads from ``presentation/cabinet/v2/_raw`` (which carries
a ``.gdignore`` so Godot never imports the raws) and writes lossless PNGs next to
it.

Subcommands
-----------
knockout SRC DST (--rect x,y,w,h | --auto-black) [--threshold N] [--feather N]
    Alpha out near-black pixels. ``--auto-black`` seeds a flood fill from the
    canvas edges (backgrounds); ``--rect`` seeds it from inside that rectangle
    (openings). Both may be given. ``--feather`` softens the edge over N levels
    of brightness above the threshold so the cut does not alias.
slice-grid SRC OUT_DIR --cols C --rows R [--names a,b,..] [--trim | --trim-common]
           [--pad-to WxH] [--knockout] [--prefix P]
    Cut a sheet into equal cells. ``--trim`` crops each cell to the bounds of its
    largest solid body (thin frost / glow spill past a plate is ignored);
    ``--trim-common`` cuts every cell to the first cell's body size centred on
    its own body, so tier tiles share one mount scale. ``--pad-to`` scales each
    trimmed cell to fit the canvas and centres it. ``--knockout`` alphas the
    black background of each cell.
fit SRC DST --size WxH
    Cover-crop and resize to an exact canvas (centre anchored).
contact-sheet [--out PATH]
    Tile every final PNG with its name and size into one review sheet, written
    to ``_raw/contact_sheet.png`` by default (inside the .gdignore'd folder).
build
    Run the whole recorded pipeline from ``_raw`` to the final asset set. This
    is the command to rerun after regenerating any raw.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

try:  # scipy speeds the flood fill up; the numpy fallback is exact but slower.
    from scipy import ndimage as _ndimage
except ImportError:  # pragma: no cover - optional dependency
    _ndimage = None

ROOT = Path(__file__).resolve().parents[2]
V2_DIR = ROOT / "presentation" / "cabinet" / "v2"
RAW_DIR = V2_DIR / "_raw"
SYSTEMS_DIR = V2_DIR / "systems"

DEFAULT_THRESHOLD = 10  # #000000..#0a0a0a counts as "knocked out" black
DEFAULT_FEATHER = 24

COMMIT_STATES = ["idle", "armed", "danger", "busy"]
SYSTEMS = ["compute", "cooling", "power", "backplane", "control"]


# ---------------------------------------------------------------------------
# helpers


def _size(text: str) -> tuple[int, int]:
    width, height = text.lower().split("x")
    return int(width), int(height)


def _rect(text: str) -> tuple[int, int, int, int]:
    parts = [int(p) for p in text.split(",")]
    if len(parts) != 4:
        raise argparse.ArgumentTypeError("rect must be x,y,w,h")
    return parts[0], parts[1], parts[2], parts[3]


def _load_rgba(path: Path) -> Image.Image:
    return Image.open(path).convert("RGBA")


def _save(image: Image.Image, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path, format="PNG", optimize=True)
    print(f"wrote {path.relative_to(ROOT)} {image.size[0]}x{image.size[1]}")


def _near_black(rgba: np.ndarray, threshold: int) -> np.ndarray:
    return rgba[:, :, :3].max(axis=2) <= threshold


def _flood(mask: np.ndarray, seeds: np.ndarray) -> np.ndarray:
    """Every ``mask`` pixel connected (4-neighbour) to a ``seeds`` pixel."""
    seeds = seeds & mask
    if _ndimage is not None:
        labels, count = _ndimage.label(mask)
        if count == 0:
            return np.zeros_like(mask)
        hit = np.unique(labels[seeds])
        hit = hit[hit != 0]
        return np.isin(labels, hit)
    region = seeds.copy()
    while True:
        grown = region.copy()
        grown[1:, :] |= region[:-1, :]
        grown[:-1, :] |= region[1:, :]
        grown[:, 1:] |= region[:, :-1]
        grown[:, :-1] |= region[:, 1:]
        grown &= mask
        if np.array_equal(grown, region):
            return region
        region = grown


def _dilate(mask: np.ndarray, steps: int) -> np.ndarray:
    if _ndimage is not None:
        return _ndimage.binary_dilation(mask, iterations=steps)
    grown = mask.copy()
    for _ in range(steps):
        step = grown.copy()
        step[1:, :] |= grown[:-1, :]
        step[:-1, :] |= grown[1:, :]
        step[:, 1:] |= grown[:, :-1]
        step[:, :-1] |= grown[:, 1:]
        grown = step
    return grown


def knockout_array(
    rgba: np.ndarray,
    *,
    edges: bool,
    rects: list[tuple[int, int, int, int]],
    threshold: int = DEFAULT_THRESHOLD,
    feather: int = DEFAULT_FEATHER,
) -> np.ndarray:
    """Return a copy with connected near-black regions set to alpha 0."""
    height, width = rgba.shape[:2]
    black = _near_black(rgba, threshold)
    seeds = np.zeros((height, width), dtype=bool)
    if edges:
        seeds[0, :] = seeds[-1, :] = True
        seeds[:, 0] = seeds[:, -1] = True
    for x, y, w, h in rects:
        seeds[max(0, y) : min(height, y + h), max(0, x) : min(width, x + w)] = True
    if not seeds.any():
        raise SystemExit("knockout needs --auto-black and/or --rect")
    hole = _flood(black, seeds)
    out = rgba.copy()
    alpha = out[:, :, 3].astype(np.float32)
    alpha[hole] = 0.0
    if feather > 0:
        band = _dilate(hole, 2) & ~hole
        value = out[:, :, :3].max(axis=2).astype(np.float32)
        soft = np.clip((value - threshold) / float(feather), 0.0, 1.0)
        alpha[band] = np.minimum(alpha[band], soft[band] * 255.0)
    out[:, :, 3] = alpha.astype(np.uint8)
    return out


def _bbox_non_black(rgba: np.ndarray, threshold: int) -> tuple[int, int, int, int]:
    solid = ~_near_black(rgba, threshold)
    if rgba.shape[2] == 4:
        solid &= rgba[:, :, 3] > 0
    ys, xs = np.nonzero(solid)
    if ys.size == 0:
        return 0, 0, rgba.shape[1], rgba.shape[0]
    return int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1


def _solid_bbox(rgba: np.ndarray, threshold: int, erode: int = 6) -> tuple[int, int, int, int]:
    """Bounds of the largest solid body in the cell, ignoring thin spill.

    Frost wisps, glow bloom and sparks that leak past a mount plate are thinner
    than ``erode`` pixels, so opening the mask by that much and keeping the
    biggest connected piece finds the plate itself. The erosion is added back
    so the returned box hugs the plate's real edge.
    """
    if rgba.shape[2] == 4 and (rgba[:, :, 3] == 0).any():
        # Already knocked out: everything the flood fill left is the object,
        # including its own near-black scorching.
        solid = rgba[:, :, 3] > 0
    else:
        solid = ~_near_black(rgba, threshold)
    if _ndimage is None or erode <= 0:
        return _bbox_non_black(rgba, threshold)
    core = _ndimage.binary_erosion(_ndimage.binary_fill_holes(solid), iterations=erode)
    labels, count = _ndimage.label(core)
    if count == 0:
        return _bbox_non_black(rgba, threshold)
    sizes = np.asarray(_ndimage.sum(core, labels, index=range(1, count + 1)))
    # Keep every body that is a real part of the object (a handle's cap and its
    # shaft may be split by a black seam) and drop stray specks and spill.
    keep = np.nonzero(sizes >= sizes.max() * 0.1)[0] + 1
    body = np.isin(labels, keep)
    ys, xs = np.nonzero(body)
    height, width = solid.shape
    return (
        max(0, int(xs.min()) - erode),
        max(0, int(ys.min()) - erode),
        min(width, int(xs.max()) + 1 + erode),
        min(height, int(ys.max()) + 1 + erode),
    )


def fit_cover(image: Image.Image, size: tuple[int, int]) -> Image.Image:
    """Scale to cover ``size`` then centre-crop, like CSS ``object-fit: cover``."""
    target_w, target_h = size
    scale = max(target_w / image.width, target_h / image.height)
    scaled = image.resize(
        (max(1, round(image.width * scale)), max(1, round(image.height * scale))),
        Image.LANCZOS,
    )
    left = (scaled.width - target_w) // 2
    top = (scaled.height - target_h) // 2
    return scaled.crop((left, top, left + target_w, top + target_h))


def fit_contain(image: Image.Image, size: tuple[int, int]) -> Image.Image:
    """Scale to fit inside ``size`` and centre on a transparent canvas."""
    target_w, target_h = size
    scale = min(target_w / image.width, target_h / image.height)
    scaled = image.resize(
        (max(1, round(image.width * scale)), max(1, round(image.height * scale))),
        Image.LANCZOS,
    )
    canvas = Image.new("RGBA", size, (0, 0, 0, 0))
    canvas.paste(scaled, ((target_w - scaled.width) // 2, (target_h - scaled.height) // 2))
    return canvas


# ---------------------------------------------------------------------------
# subcommands


def cmd_knockout(args: argparse.Namespace) -> None:
    image = _load_rgba(Path(args.src))
    out = knockout_array(
        np.array(image),
        edges=args.auto_black,
        rects=args.rect or [],
        threshold=args.threshold,
        feather=args.feather,
    )
    _save(Image.fromarray(out, "RGBA"), Path(args.dst))


def slice_grid(
    src: Path,
    out_dir: Path,
    *,
    cols: int,
    rows: int,
    names: list[str] | None,
    trim: str | None,
    pad_to: tuple[int, int] | None,
    knockout: bool,
    prefix: str,
    threshold: int = DEFAULT_THRESHOLD,
    feather: int = DEFAULT_FEATHER,
) -> list[Path]:
    image = _load_rgba(src)
    cell_w = image.width // cols
    cell_h = image.height // rows
    cells: list[np.ndarray] = []
    for row in range(rows):
        for col in range(cols):
            box = (col * cell_w, row * cell_h, (col + 1) * cell_w, (row + 1) * cell_h)
            cells.append(np.array(image.crop(box)))
    if names is None:
        names = [f"{prefix}{index + 1}" for index in range(len(cells))]
    if len(names) != len(cells):
        raise SystemExit(f"{len(names)} names for {len(cells)} cells")

    common_size: tuple[int, int] | None = None
    if trim == "common":
        x0, y0, x1, y1 = _solid_bbox(cells[0], threshold)
        common_size = (x1 - x0, y1 - y0)
    written: list[Path] = []
    for cell, name in zip(cells, names):
        if knockout:
            cell = knockout_array(cell, edges=True, rects=[], threshold=threshold, feather=feather)
        if trim == "each":
            x0, y0, x1, y1 = _solid_bbox(cell, threshold)
            cell = cell[y0:y1, x0:x1]
        elif trim == "common" and common_size is not None:
            # Every cell is cut to the first cell's plate size, centred on its
            # own plate, so all tiers land at the same scale on the mount.
            x0, y0, x1, y1 = _solid_bbox(cell, threshold)
            cx, cy = (x0 + x1) // 2, (y0 + y1) // 2
            w, h = common_size
            left = min(max(0, cx - w // 2), max(0, cell.shape[1] - w))
            top = min(max(0, cy - h // 2), max(0, cell.shape[0] - h))
            cell = cell[top : top + h, left : left + w]
        tile = Image.fromarray(cell, "RGBA")
        if pad_to is not None:
            tile = fit_contain(tile, pad_to)
        path = out_dir / f"{name}.png"
        _save(tile, path)
        written.append(path)
    return written


def cmd_slice_grid(args: argparse.Namespace) -> None:
    trim = "common" if args.trim_common else ("each" if args.trim else None)
    slice_grid(
        Path(args.src),
        Path(args.out_dir),
        cols=args.cols,
        rows=args.rows,
        names=args.names.split(",") if args.names else None,
        trim=trim,
        pad_to=args.pad_to,
        knockout=args.knockout,
        prefix=args.prefix,
        threshold=args.threshold,
        feather=args.feather,
    )


def cmd_fit(args: argparse.Namespace) -> None:
    image = _load_rgba(Path(args.src))
    _save(fit_cover(image, args.size), Path(args.dst))


def contact_sheet(out_path: Path, cell: int = 256) -> None:
    files = sorted(p for p in V2_DIR.rglob("*.png") if "_raw" not in p.parts)
    if not files:
        raise SystemExit("no final assets to sheet")
    cols = 6
    rows = (len(files) + cols - 1) // cols
    label_h = 30
    sheet = Image.new("RGBA", (cols * cell, rows * (cell + label_h)), (40, 40, 44, 255))
    draw = ImageDraw.Draw(sheet)
    font = ImageFont.load_default()
    checker = Image.new("RGBA", (cell, cell), (70, 70, 74, 255))
    checker_draw = ImageDraw.Draw(checker)
    for y in range(0, cell, 16):
        for x in range(0, cell, 16):
            if ((x // 16) + (y // 16)) % 2 == 0:
                checker_draw.rectangle((x, y, x + 15, y + 15), fill=(95, 95, 100, 255))
    for index, path in enumerate(files):
        image = _load_rgba(path)
        thumb = fit_contain(image, (cell, cell))
        col, row = index % cols, index // cols
        x, y = col * cell, row * (cell + label_h)
        sheet.paste(checker, (x, y))
        sheet.alpha_composite(thumb, (x, y))
        label = f"{path.relative_to(V2_DIR).as_posix()}  {image.width}x{image.height}"
        draw.text((x + 4, y + cell + 6), label, fill=(230, 230, 230, 255), font=font)
    _save(sheet, out_path)


def cmd_contact_sheet(args: argparse.Namespace) -> None:
    contact_sheet(Path(args.out) if args.out else RAW_DIR / "contact_sheet.png")


# ---------------------------------------------------------------------------
# the recorded pipeline


def _frame(name: str, size: tuple[int, int], knock: bool) -> None:
    image = fit_cover(_load_rgba(RAW_DIR / f"{name}.png"), size)
    if knock:
        centre = (size[0] // 2 - 8, size[1] // 2 - 8, 16, 16)
        out = knockout_array(np.array(image), edges=False, rects=[centre])
        image = Image.fromarray(out, "RGBA")
    _save(image, V2_DIR / f"{name}.png")


def _single_tile(raw: Path, dst: Path, size: tuple[int, int]) -> None:
    rgba = knockout_array(np.array(_load_rgba(raw)), edges=True, rects=[])
    x0, y0, x1, y1 = _solid_bbox(rgba, DEFAULT_THRESHOLD)
    _save(fit_contain(Image.fromarray(rgba[y0:y1, x0:x1], "RGBA"), size), dst)


def build() -> None:
    # 1 + 11: full-bleed backdrops, cover-cropped to the design canvas.
    _frame("chassis_backdrop", (1920, 1080), knock=False)
    _frame("maintenance_wall", (1920, 1080), knock=False)
    # 2-6: 9-slice frames. Openings are flood-filled from the canvas centre so a
    # black interior becomes alpha while black paint on the frame itself stays.
    _frame("crt_bezel", (1536, 864), knock=True)
    _frame("telemetry_frame", (768, 1024), knock=True)
    _frame("deck_plate", (1536, 864), knock=False)
    _frame("backplane_rail", (1536, 864), knock=False)
    _frame("panel_9slice", (1024, 768), knock=False)
    # 7: commit button states, one 2x2 sheet -> four equal cells on one canvas.
    slice_grid(
        RAW_DIR / "commit_button_states.png",
        V2_DIR,
        cols=2,
        rows=2,
        names=[f"commit_{state}" for state in COMMIT_STATES],
        trim="each",
        pad_to=(960, 400),
        knockout=True,
        prefix="commit_",
    )
    # 8: abort lever. The channel keeps its 9:16 plate; the slot is knocked out.
    channel = fit_cover(_load_rgba(RAW_DIR / "abort_lever_channel.png"), (585, 1040))
    centre = (585 // 2 - 6, 1040 // 2 - 40, 12, 80)
    channel_out = knockout_array(np.array(channel), edges=False, rects=[centre])
    _save(Image.fromarray(channel_out, "RGBA"), V2_DIR / "abort_lever_channel.png")
    _single_tile(RAW_DIR / "abort_lever_handle.png", V2_DIR / "abort_lever_handle.png", (320, 320))
    # 9: locked bay shutter, opaque, same aspect as module_bay_frame.png.
    _frame("bay_shutter", (640, 382), knock=False)
    # 10: system tiers. Each row is sliced on the first plate's bounds so all
    # four tiers share one mount size; individually regenerated tiers override.
    for system in SYSTEMS:
        slice_grid(
            RAW_DIR / f"sys_{system}_row.png",
            SYSTEMS_DIR,
            cols=4,
            rows=1,
            names=[f"{system}_t{tier}" for tier in range(1, 5)],
            trim="common",
            pad_to=(480, 480),
            knockout=True,
            prefix=f"{system}_t",
        )
        for tier in range(1, 5):
            override = RAW_DIR / f"sys_{system}_t{tier}.png"
            if override.exists():
                _single_tile(override, SYSTEMS_DIR / f"{system}_t{tier}.png", (480, 480))
    contact_sheet(RAW_DIR / "contact_sheet.png")


def cmd_build(_args: argparse.Namespace) -> None:
    build()


# ---------------------------------------------------------------------------


def main(argv: list[str] | None = None) -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)

    knock = sub.add_parser("knockout", help="alpha out connected near-black regions")
    knock.add_argument("src")
    knock.add_argument("dst")
    knock.add_argument("--rect", type=_rect, action="append", help="x,y,w,h seed rectangle (repeatable)")
    knock.add_argument("--auto-black", action="store_true", help="seed from the canvas edges")
    knock.add_argument("--threshold", type=int, default=DEFAULT_THRESHOLD)
    knock.add_argument("--feather", type=int, default=DEFAULT_FEATHER)
    knock.set_defaults(func=cmd_knockout)

    grid = sub.add_parser("slice-grid", help="cut a sheet into equal cells")
    grid.add_argument("src")
    grid.add_argument("out_dir")
    grid.add_argument("--cols", type=int, required=True)
    grid.add_argument("--rows", type=int, required=True)
    grid.add_argument("--names", help="comma-separated cell names, row-major")
    grid.add_argument("--prefix", default="cell_")
    grid.add_argument("--trim", action="store_true", help="trim each cell to its own bounds")
    grid.add_argument("--trim-common", action="store_true", help="trim every cell to the first cell's bounds")
    grid.add_argument("--pad-to", type=_size, help="WxH canvas each cell is fitted onto")
    grid.add_argument("--knockout", action="store_true", help="alpha out each cell's black background")
    grid.add_argument("--threshold", type=int, default=DEFAULT_THRESHOLD)
    grid.add_argument("--feather", type=int, default=DEFAULT_FEATHER)
    grid.set_defaults(func=cmd_slice_grid)

    fit = sub.add_parser("fit", help="cover-crop to an exact canvas")
    fit.add_argument("src")
    fit.add_argument("dst")
    fit.add_argument("--size", type=_size, required=True)
    fit.set_defaults(func=cmd_fit)

    sheet = sub.add_parser("contact-sheet", help="review sheet of every final asset")
    sheet.add_argument("--out")
    sheet.set_defaults(func=cmd_contact_sheet)

    full = sub.add_parser("build", help="run the recorded _raw -> final pipeline")
    full.set_defaults(func=cmd_build)

    args = parser.parse_args(argv)
    args.func(args)


if __name__ == "__main__":
    main(sys.argv[1:])
