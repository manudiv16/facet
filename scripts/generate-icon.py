#!/usr/bin/env python3
"""Generate the Facet source icon (1024x1024 PNG) without external deps.

The icon is a rounded dark square with a light "facet" diamond in the middle.
It is only used as input to `cargo tauri icon`, which derives every platform
icon (.icns, .ico, PNG set).
"""

import struct
import sys
import zlib
from pathlib import Path

SIZE = 1024
CORNER = 200


def blend(bg, fg, alpha):
    return tuple(round(b + (f - b) * alpha) for b, f in zip(bg, fg))


def main(path: str) -> None:
    bg = (15, 20, 27)
    accent = (96, 165, 250)
    accent_light = (191, 219, 254)

    cx = cy = (SIZE - 1) / 2
    outer = SIZE * 0.34
    inner = SIZE * 0.15

    rows = bytearray()
    for y in range(SIZE):
        rows.append(0)  # filter type: none
        for x in range(SIZE):
            # Rounded-square alpha.
            dx = max(CORNER - x, x - (SIZE - 1 - CORNER), 0)
            dy = max(CORNER - y, y - (SIZE - 1 - CORNER), 0)
            if dx * dx + dy * dy > CORNER * CORNER:
                rows.extend((0, 0, 0, 0))
                continue

            manhattan = abs(x - cx) + abs(y - cy)
            if manhattan <= inner:
                pixel = accent_light
            elif manhattan <= outer:
                # Fade from accent to background towards the edge.
                t = (manhattan - inner) / max(outer - inner, 1)
                pixel = blend(accent, bg, t * 0.75)
            else:
                pixel = bg

            rows.extend((*pixel, 255))

    def chunk(tag: bytes, data: bytes) -> bytes:
        return (
            struct.pack(">I", len(data))
            + tag
            + data
            + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
        )

    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", SIZE, SIZE, 8, 6, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(bytes(rows), 9))
    png += chunk(b"IEND", b"")

    Path(path).write_bytes(png)
    print(f"wrote {path}")


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "icon-source.png")
