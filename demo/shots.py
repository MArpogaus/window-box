#!/usr/bin/env python3
"""Draw the terminal screenshot for the README.

Runs Emacs in a pseudo terminal, feeds the byte stream into a pyte
screen — the same way `make tty' checks the terminal box — and paints
the screen it reports into a PNG.  The image is therefore what a
terminal shows, cell by cell, and not a photograph of one.

Usage: python3 demo/shots.py demo/shots-tty.el img/encloses-tty.png
"""
import os
import pty
import select
import subprocess
import sys
import time

import pyte
from PIL import Image, ImageDraw, ImageFont

COLS, ROWS = 84, 26
# In order of preference, among the fonts that have the box drawing
# characters — a font without them draws the box as nothing at all.
FONTS = ["Source Code Pro", "DejaVu Sans Mono", "Liberation Mono"]
SIZE = 15
PAD = 10
BACKGROUND = (28, 31, 38)
FOREGROUND = (216, 222, 233)
NAMED = {
    "black": (28, 31, 38), "red": (191, 97, 106), "green": (163, 190, 140),
    "brown": (235, 203, 139), "blue": (94, 129, 172),
    "magenta": (180, 142, 173), "cyan": (136, 192, 208),
    "white": (216, 222, 233), "default": None,
}


def find_font():
    """Return a font file with the box drawing characters in it."""
    listing = subprocess.run(["fc-list", ":charset=2500:style=Regular",
                              "file", "family"],
                             capture_output=True, text=True, check=True).stdout
    files = {}
    for line in listing.splitlines():
        path, _, families = line.partition(": ")
        for family in families.split(","):
            files.setdefault(family.strip(), path.rstrip(":"))
    for name in FONTS + sorted(f for f in files if "Mono" in f):
        if name in files:
            return files[name]
    raise SystemExit("no font with box drawing characters found")


def capture(script):
    """Return the pyte screen after Emacs has drawn SCRIPT's session."""
    screen = pyte.Screen(COLS, ROWS)
    stream = pyte.ByteStream(screen)
    env = dict(os.environ, TERM="xterm-256color",
               COLUMNS=str(COLS), LINES=str(ROWS))
    emacs = env.get("EMACS", "emacs")
    pid, handle = pty.fork()
    if pid == 0:
        os.execvpe(emacs, [emacs, "-nw", "-Q", "-l", script], env)
    end = time.time() + 30
    while time.time() < end:
        ready, _, _ = select.select([handle], [], [], 0.5)
        if not ready:
            continue
        try:
            data = os.read(handle, 65536)
        except OSError:
            break
        if not data:
            break
        stream.feed(data)
    return screen


def color(name, fallback):
    """Return the RGB of pyte's NAME, or FALLBACK where it has none."""
    if name in NAMED:
        return NAMED[name] or fallback
    try:
        return tuple(int(name[i:i + 2], 16) for i in (0, 2, 4))
    except ValueError:
        return fallback


def paint(screen, path):
    """Draw SCREEN into PATH."""
    font = ImageFont.truetype(find_font(), SIZE)
    ascent, descent = font.getmetrics()
    width = font.getlength("M")
    height = ascent + descent
    image = Image.new("RGB", (int(width * COLS) + 2 * PAD,
                              height * ROWS + 2 * PAD), BACKGROUND)
    draw = ImageDraw.Draw(image)
    for row in range(ROWS):
        for column in range(COLS):
            cell = screen.buffer[row][column]
            foreground = color(cell.fg, FOREGROUND)
            background = color(cell.bg, BACKGROUND)
            if cell.reverse:
                foreground, background = background, foreground
            x, y = PAD + column * width, PAD + row * height
            if background != BACKGROUND:
                draw.rectangle([x, y, x + width, y + height], fill=background)
            if cell.data.strip():
                draw.text((x, y), cell.data, font=font, fill=foreground,
                          anchor="la")
    image.save(path)


def main():
    script, target = sys.argv[1], sys.argv[2]
    paint(capture(script), target)
    print(f"wrote {target}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
