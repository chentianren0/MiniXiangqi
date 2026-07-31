#!/usr/bin/env python3
"""Build the frontend's icon assets from the app icon's 1024 px export.

The icon's true source is the Apple side's Icon Composer document,
apple/AppIcon.icon. The owner exports a flat 1024x1024 PNG from it
(AppIcon-1024@1x.png), and this script turns that one image into everything
Windows asks for. The chain is

    apple/AppIcon.icon  ->  AppIcon-1024@1x.png  ->  MiniXiangqi.ico
                                                 ->  MiniXiangqi.App/Images/

and only the last link is in this repository: the .icon document is the Apple
app's, and the 1024 px export is four megabytes of intermediate that this
script consumes rather than something anybody edits.

    python3 windows/make-app-icon.py <path to AppIcon-1024@1x.png>

TWO OUTPUTS, ONE SOURCE

MiniXiangqi.ico is what the *executable* carries: Explorer, a shortcut, a
pinned taskbar entry, and the window's own AppWindow.SetIcon. It is what an
unpackaged zip has and all it has.

MiniXiangqi.App/Images/ is what the *Store package* carries. An MSIX declares
its images in Package.appxmanifest and the shell resolves each one through the
package's resource index, picking the frame that matches the display's scale
or the size the caller asked for — so the package needs one PNG per qualifier
rather than one container holding them all. Nothing outside a packaged build
reads that directory (MiniXiangqi.App.csproj includes it only when
MxqPackaged is true), which is why regenerating it cannot disturb the zip.

Both are written by one script because both are derived from one image, and a
design change that reached one and not the other would leave the app wearing
two faces.

WHY THIS RATHER THAN Pillow's OWN ICO WRITER

Pillow will write an .ico in one call, but it writes every entry the same way:
all PNG-compressed, or all BMP. A Windows icon conventionally carries
PNG compression only at 256x256 and uncompressed DIB entries below it, because
PNG entries at small sizes are handled by the modern shell and not by every
older path that may still ask for a 32x32 icon. So the container is written
here, one entry at a time, with each frame encoded the way that size wants.

Every frame in either output is resized from the 1024 px original rather than
from the next size up, so no downscaling error compounds, and LANCZOS is the
filter throughout.
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

# ---------------------------------------------------------------------------
# The Store package's images
# ---------------------------------------------------------------------------
#
# Three logos are declared in Package.appxmanifest and each is emitted at the
# five display scales Windows defines, because a scale qualifier the package
# does not carry is one the shell satisfies by stretching the nearest frame it
# has. StoreLogo is the package's own face in the Store listing and in the
# installer; Square150x150Logo is the Start menu's medium tile; Square44x44Logo
# is the app list, the taskbar and the title bar.
#
# The base is the 100% size, and the qualifier's own arithmetic gives the rest.
SCALES = [100, 125, 150, 200, 400]
SCALED_LOGOS = {
    "StoreLogo": 50,
    "Square150x150Logo": 150,
    "Square44x44Logo": 44,
}

# The target-size frames, which are a different question from the scaled ones.
# A scale- frame answers "this display is at 150%"; a targetsize- frame answers
# "something asked for a 32-pixel icon", and the shell picks it for the taskbar,
# Alt-Tab and the app list irrespective of scale.
#
# These five sizes are MiniXiangqi.ico's own set minus the entries the .ico
# carries for older shell paths — the same argument windows/README.md § The icon
# makes about which sizes are worth having, applied to the package.
#
# Each is emitted three times. The plain frame is drawn on the system's accent
# plate; _altform-unplated is the same frame with no plate behind it, which is
# what the taskbar and Alt-Tab use; _altform-lightunplated is the unplated frame
# for a light-themed shell. This icon is a shaped disc on transparency and reads
# the same on any background, so the three are identical bytes — they are all
# emitted anyway, because a missing altform is not resolved to the plain frame,
# it is resolved to a plate the icon was never meant to sit on.
TARGET_SIZES = [16, 24, 32, 48, 256]
ALTFORMS = ["", "_altform-unplated", "_altform-lightunplated"]

# Store certification refuses any image asset of 200 KB or more. Only one frame
# in this set comes near it — Square150x150Logo.scale-400, which is 600 px of a
# grainy original — and _write_png says below what it does about that.
MAX_ASSET_BYTES = 204_800


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


def scaled_pixels(base: int, scale: int) -> int:
    """The pixel size a scale qualifier means, rounded half up.

    Windows defines a scale- frame as the 100% size times the percentage, and
    the only case in this set where that is not already an integer is 125% of
    an odd base: 50 -> 62.5 and 150 -> 187.5. The shell rounds those up, to 63
    and 188, and a frame that disagrees with its own qualifier by one pixel is
    a named certification failure rather than a rendering nuisance — so the
    arithmetic is integer and half-up here rather than whatever the platform's
    float rounding would give.
    """
    return (base * scale + 50) // 100


def _write_png(frame: Image.Image, destination: Path) -> tuple[int, str]:
    """Write one asset frame, and keep it under the certification limit.

    Full-colour first, because that is what the icon is. Every frame in this
    set but one comes out well under 200 KB that way.

    The exception is the 600 px Square150x150Logo.scale-400. The original is a
    grainy 1024 px render — nearly four megabytes of it — and at 600 px the
    grain that survives the downscale costs half a megabyte of PNG that no
    compression setting recovers, because the grain is the incompressible part.
    So that one frame falls back to a 256-colour adaptive palette, which is the
    largest a PNG can hold, and lands around 76 KB. FASTOCTREE is the quantizer
    because it is the one that keeps an alpha channel, and this icon is a
    shaped disc whose transparency is the shape.

    What is lost is the last of the grain on the one frame only a 400%-scale
    display ever asks for, where the tile is physically the same size as the
    150 px frame at 100%. What would be lost by not doing it is the submission.
    The return value names which path each file took, so the log says so rather
    than the reader having to know.
    """
    buffer = BytesIO()
    frame.save(buffer, "png", optimize=True)
    if len(buffer.getvalue()) < MAX_ASSET_BYTES:
        destination.write_bytes(buffer.getvalue())
        return len(buffer.getvalue()), "RGBA"

    for colours in (256, 192, 128, 96, 64):
        reduced = frame.quantize(colors=colours, method=Image.Quantize.FASTOCTREE)
        buffer = BytesIO()
        reduced.save(buffer, "png", optimize=True)
        if len(buffer.getvalue()) < MAX_ASSET_BYTES:
            destination.write_bytes(buffer.getvalue())
            return len(buffer.getvalue()), f"palette-{colours}"

    raise SystemExit(
        f"{destination.name} is {len(buffer.getvalue()):,} bytes even at 64 colours, and Store "
        f"certification refuses any image asset of {MAX_ASSET_BYTES:,} bytes or more. The source "
        f"image is carrying more detail than this size can hold; simplify it rather than "
        f"shipping a package that fails submission."
    )


def build_images(source: Path, directory: Path) -> list[tuple[str, int, int, str]]:
    """Write the Store package's image assets, and return what was written.

    Every frame comes from the 1024 px original by one LANCZOS resize. Resizing
    the 88 px frame from the 176 px one would be cheaper and would compound the
    filter's error twice over on the size a person looks at most.
    """
    original = Image.open(source).convert("RGBA")
    if original.size != (1024, 1024):
        raise SystemExit(
            f"expected a 1024x1024 source; {source} is {original.size[0]}x{original.size[1]}")

    directory.mkdir(parents=True, exist_ok=True)
    # Everything in here is derived, so a frame left behind by an earlier set of
    # rules would be indistinguishable from one this run wrote. The manifest
    # names three logos and the shell resolves what it finds, so a stale
    # qualifier is a frame that silently wins over the right one.
    for stale in directory.glob("*.png"):
        stale.unlink()

    written: list[tuple[str, int, int, str]] = []

    def emit(name: str, pixels: int) -> None:
        # A qualifier set is a comma-free grammar with one rule that catches
        # everybody: scale- and targetsize- are alternatives, never both. A file
        # named for both is indexed under neither and the shell falls back to
        # whatever else it has, which is the failure that looks like "the icon
        # is just wrong" rather than like a build error.
        if ".scale-" in name and ".targetsize-" in name:
            raise SystemExit(f"{name} carries both a scale- and a targetsize- qualifier.")
        frame = original.resize((pixels, pixels), Image.Resampling.LANCZOS)
        length, encoding = _write_png(frame, directory / name)
        written.append((name, pixels, length, encoding))

    for logo, base in SCALED_LOGOS.items():
        for scale in SCALES:
            emit(f"{logo}.scale-{scale}.png", scaled_pixels(base, scale))

    for size in TARGET_SIZES:
        for altform in ALTFORMS:
            emit(f"Square44x44Logo.targetsize-{size}{altform}.png", size)

    return written


def describe_images(directory: Path, written: list[tuple[str, int, int, str]]) -> None:
    """Read every frame back the way the packaging build will, and say what is
    in it. Writing a file is not evidence that it holds what it was meant to;
    reopening it and reading its dimensions off the decoded image is."""
    print(f"{directory}  {len(written)} images")
    total = 0
    for name, pixels, length, encoding in written:
        path = directory / name
        with Image.open(path) as frame:
            actual = frame.size
        if actual != (pixels, pixels):
            raise SystemExit(
                f"{name} decodes as {actual[0]}x{actual[1]}; its qualifier says {pixels}x{pixels}. "
                f"Store certification checks each asset against the size its own name declares.")
        if path.stat().st_size >= MAX_ASSET_BYTES:
            raise SystemExit(f"{name} is {path.stat().st_size:,} bytes, at or over the "
                             f"{MAX_ASSET_BYTES:,}-byte limit.")
        total += length
        print(f"  {name:<48} {pixels:>4}x{pixels:<4} {length:>9,} bytes  {encoding}")
    print(f"  {'total':<48} {'':>9} {total:>9,} bytes")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit(f"usage: {sys.argv[0]} <path to AppIcon-1024@1x.png>")
    source = Path(sys.argv[1])
    app = Path(__file__).resolve().parent / "MiniXiangqi.App"

    target = app / "MiniXiangqi.ico"
    build(source, target)
    describe(target)

    print()
    images = app / "Images"
    describe_images(images, build_images(source, images))
