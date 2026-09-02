"""Write launcher PNG placeholders from a dark field and phosphor mark."""
from __future__ import annotations

import struct
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "presentation" / "android"
PHOSPHOR = (26, 214, 138, 255)
BG = (8, 18, 16, 255)
INK = (6, 12, 11, 255)


def png(width: int, height: int, rgba_rows: list[bytes]) -> bytes:
    def chunk(tag: bytes, data: bytes) -> bytes:
        return (
            struct.pack(">I", len(data))
            + tag
            + data
            + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
        )

    raw = b"".join(b"\x00" + row for row in rgba_rows)
    return b"".join(
        [
            b"\x89PNG\r\n\x1a\n",
            chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)),
            chunk(b"IDAT", zlib.compress(raw, 9)),
            chunk(b"IEND", b""),
        ]
    )


def fill(size: int, color: tuple[int, int, int, int]) -> list[bytes]:
    pixel = struct.pack("BBBB", *color)
    return [pixel * size for _ in range(size)]


def stamp_mark(rows: list[bytes], size: int, color: tuple[int, int, int, int]) -> list[bytes]:
    pixel = struct.pack("BBBB", *color)
    mutable = [bytearray(row) for row in rows]
    inset = size // 6
    thickness = max(2, size // 18)
    for y in range(inset, size - inset):
        for x in range(inset, size - inset):
            on_rect = (
                x < inset + thickness
                or x >= size - inset - thickness
                or y < inset + thickness
                or y >= size - inset - thickness
            )
            bar = abs(x - size // 2) < thickness and inset + thickness * 2 <= y <= size - inset - thickness * 2
            if on_rect or bar:
                mutable[y][x * 4 : x * 4 + 4] = pixel
    return [bytes(row) for row in mutable]


def write(name: str, size: int, background: tuple[int, int, int, int], mark: tuple[int, int, int, int] | None) -> None:
    rows = fill(size, background)
    if mark is not None:
        rows = stamp_mark(rows, size, mark)
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / name).write_bytes(png(size, size, rows))


def main() -> None:
    write("icon_192.png", 192, BG, PHOSPHOR)
    write("adaptive_foreground_432.png", 432, (0, 0, 0, 0), PHOSPHOR)
    write("adaptive_background_432.png", 432, BG, None)
    write("adaptive_monochrome_432.png", 432, (0, 0, 0, 0), INK)
    print(f"wrote icons in {OUT}")


if __name__ == "__main__":
    main()
