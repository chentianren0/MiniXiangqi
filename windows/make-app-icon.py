#!/usr/bin/env python3
"""Build MiniXiangqi.App/MiniXiangqi.ico from the app icon's 1024 px export.

The icon's true source is the Apple side's Icon Composer document,
apple/AppIcon.icon. The owner exports a flat 1024x1024 PNG from it
(AppIcon-1024@1x.png), and this script turns that one image into the
multi-size Windows .ico the frontend ships. The chain is

    apple/AppIcon.icon  ->  AppIcon-1024@1x.png  ->  MiniXiangqi.ico

and only the last of the three is in this repository: the .icon document is the
Apple app's, and the 1024 px export is four megabytes of intermediate that this
script consumes rather than something anybody edits.

    python3 windows/make-app-icon.py <path to AppIcon-1024@1x.png>

WHY THIS RATHER THAN Pillow's OWN ICO WRITER

Pillow will write an .ico in one call, but it writes every entry the same way:
all PNG-compressed, or all BMP. A Windows icon conventionally carries
PNG compression only at 256x256 and uncompressed DIB entries below it, because
PNG entries at small sizes are handled by the modern shell and not by every
older path that may still ask for a 32x32 icon. So the container is written
here, one entry at a time, with each frame encoded the way that size wants.

Every frame is resized from the 1024 px original rather than from the next size
up, so no downscaling error compounds, and LANCZOS is the filter throughout.
"""

from __future__ import annotations

import struct
import sys
from io import BytesIO
from pathlib import Path

from PIL import Image

# The sizes Windows asks for. 16 is the title bar and the small shell views, 20
# and 24 are the scaled variants of it that a high-DPI machine picks up, 32 is
# the taskbar and the ordinary Explorer icon, 48 and 64 are the medium views,
# 128 and 256 the large and extra-large ones. 256 is where PNG compression
# starts, and is also the only entry whose stored width byte is 0 — the format
# has one byte for it, so 256 is written as "0 means 256".
SIZES = [16, 20, 24, 32, 48, 64, 128, 256]
PNG_FROM = 256


def dib_entry(frame: Image.Image) -> bytes:
    """A 32-bit BGRA icon entry: a BITMAPINFOHEADER whose height covers both
    the colour bitmap and the AND mask, the colour bitmap, and a zeroed mask.

    The doubled height is the icon format's own rule rather than a quirk of
    this script: an .ico DIB stores an XOR (colour) bitmap and an AND
    (transparency) mask in one image, and declares the height of the two
    together. The mask is all zeros because a 32-bit icon's transparency is its
    alpha channel; the mask is there because the format's readers expect the
    bytes to be present, not because anything reads them.
    """
    buffer = BytesIO()
    frame.save(buffer, "dib")
    dib = buffer.getvalue()

    width, height = frame.size
    header = dib[:8] + struct.pack("<I", height * 2) + dib[12:40]
    colours = dib[40:]

    # The mask is 1 bit per pixel, each row padded to a four-byte boundary.
    mask_stride = ((width + 31) // 32) * 4
    mask = b"\0" * (mask_stride * height)

    return header + colours + mask


def png_entry(frame: Image.Image) -> bytes:
    buffer = BytesIO()
    frame.save(buffer, "png", optimize=True)
    return buffer.getvalue()


def build(source: Path, destination: Path) -> None:
    original = Image.open(source).convert("RGBA")
    if original.size != (1024, 1024):
        raise SystemExit(f"expected a 1024x1024 source; {source} is {original.size[0]}x{original.size[1]}")

    entries = []
    for size in SIZES:
        frame = original.resize((size, size), Image.Resampling.LANCZOS)
        payload = png_entry(frame) if size >= PNG_FROM else dib_entry(frame)
        entries.append((size, payload))

    # ICONDIR: reserved, type 1 (icon), count.
    out = bytearray(struct.pack("<HHH", 0, 1, len(entries)))
    offset = len(out) + 16 * len(entries)
    directory = bytearray()
    data = bytearray()
    for size, payload in entries:
        stored = 0 if size >= 256 else size
        directory += struct.pack(
            "<BBBBHHII",
            stored,          # bWidth, 0 meaning 256
            stored,          # bHeight
            0,               # bColorCount, 0 for a true-colour entry
            0,               # bReserved
            1,               # wPlanes
            32,              # wBitCount
            len(payload),    # dwBytesInRes
            offset,          # dwImageOffset
        )
        data += payload
        offset += len(payload)

    destination.write_bytes(bytes(out + directory + data))


def describe(path: Path) -> None:
    """Read the file back the way a reader of the format would, and say what is
    in it. Re-opening with Pillow proves it parses; walking the directory
    proves each entry is the size and encoding it was meant to be."""
    raw = path.read_bytes()
    _, kind, count = struct.unpack_from("<HHH", raw, 0)
    print(f"{path}  {len(raw):,} bytes  type {kind}  {count} entries")
    for index in range(count):
        (width, height, colours, _reserved, planes, bits,
         length, offset) = struct.unpack_from("<BBBBHHII", raw, 6 + index * 16)
        width = width or 256
        height = height or 256
        payload = raw[offset:offset + length]
        encoding = "PNG" if payload[:8] == b"\x89PNG\r\n\x1a\n" else "DIB"
        print(f"  {width:>3}x{height:<3}  {bits} bit  {planes} plane  "
              f"{colours} colours  {encoding}  {length:,} bytes")

    with Image.open(path) as reopened:
        print(f"  Pillow re-opens it as {reopened.format} {reopened.mode}, "
              f"largest {reopened.size[0]}x{reopened.size[1]}, "
              f"sizes {sorted(reopened.info['sizes'])}")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit(f"usage: {sys.argv[0]} <path to AppIcon-1024@1x.png>")
    target = Path(__file__).resolve().parent / "MiniXiangqi.App" / "MiniXiangqi.ico"
    build(Path(sys.argv[1]), target)
    describe(target)
