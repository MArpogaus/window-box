#!/usr/bin/env python3
"""Pixel test for window-box on a graphic display.

Reads the frame that gui-test.el exported and checks the box: an edge
of `WIDTH' pixels down both sides of every boxed window, a bar of the
same thickness where the box draws one.  Needs pillow; run through
`make gui'.
"""
import sys

from PIL import Image

PNG = "/tmp/window-box-gui.png"
GEOMETRY = "/tmp/window-box-gui.txt"
ENCLOSES_PNG = "/tmp/window-box-encloses.png"
ENCLOSES_GEOMETRY = "/tmp/window-box-encloses.txt"
WIDTH = 1                      # window-box draws one pixel lines
BOX = (127, 127, 127)          # the `shadow' foreground of the default theme
PAPER = (255, 255, 255)        # the default background, where no line is
CELL = 12                      # the widest character cell the rig's font uses


def close(pixel, want, tolerance=40):
    return all(abs(a - b) <= tolerance for a, b in zip(pixel[:3], want))


def runs_of(values):
    """Group VALUES, a sorted list of integers, into consecutive runs."""
    runs, current = [], []
    for value in values:
        if current and value == current[-1] + 1:
            current.append(value)
        else:
            if current:
                runs.append(current)
            current = [value]
    if current:
        runs.append(current)
    return runs


def check(image, windows):
    """Return the failures and what was found, per boxed window."""
    failures, found = [], []
    for left, top, right, bottom in windows:
        body = range(top + int((bottom - top) * 0.3),
                     top + int((bottom - top) * 0.8))
        columns = runs_of([x for x in range(left, right)
                           if sum(1 for y in body
                                  if close(image.getpixel((x, y)), BOX))
                           > len(body) * 0.8])
        rows = runs_of([y for y in range(top, bottom)
                        if sum(1 for x in range(left, right)
                               if close(image.getpixel((x, y)), BOX))
                        > (right - left) * 0.9])
        found.append(((left, top), [c[0] for c in columns], [r[0] for r in rows]))
        if len(columns) != 2:
            failures.append(f"window at {left},{top}: want two side edges, "
                            f"found {[c[0] for c in columns]}")
        if columns:
            if columns[0][0] != left:
                failures.append(f"window at {left},{top}: left edge sits at "
                                f"x={columns[0][0]}, not at the window edge")
            if columns[-1][-1] != right - 1:
                failures.append(f"window at {left},{top}: right edge ends at "
                                f"x={columns[-1][-1]}, not at the window edge")
        if len(rows) < 2:
            failures.append(f"window at {left},{top}: want a top and a bottom "
                            f"edge, found {[r[0] for r in rows]}")
        for run in rows:
            if len(run) != WIDTH:
                failures.append(f"window at {left},{top}: a horizontal edge "
                                f"is {len(run)} pixels, want {WIDTH}")
        # A side is a character or a colored space in the outermost
        # column of the margin, so it is as wide as the font's cell at
        # most, and as narrow as a hairline at least.
        for run in columns:
            if not 1 <= len(run) <= CELL:
                failures.append(f"window at {left},{top}: a side is "
                                f"{len(run)} pixels, want 1 to {CELL}")
    return failures, found


def check_encloses(image, windows):
    """Check where the edges land for each `window-box-encloses' setting.

    WINDOWS carries the two rows the edges want, worked out from the
    row heights Emacs reports.  Between those rows the sides must run
    unbroken: the fringes down the text, the box's own ends on every
    row it takes in.
    """
    failures, found = [], []
    for left, top, right, bottom, want_top, want_bottom, sides in windows:
        edges = [y for y in range(top, bottom)
                 if sum(1 for x in range(left, right)
                        if close(image.getpixel((x, y)), BOX))
                 > (right - left) * 0.9]
        found.append(((left, top), edges, (want_top, want_bottom),
                      "no sides, the buffer keeps its margins" if not sides
                      else "both sides" if left == 0
                      else "right side only, the left one is Emacs's border"))
        if want_top not in edges:
            failures.append(f"window at {left},{top}: no top edge at "
                            f"y={want_top}, edges at {edges}")
        if want_bottom not in edges:
            failures.append(f"window at {left},{top}: no bottom edge at "
                            f"y={want_bottom}, edges at {edges}")
        # The sides are a character in the outermost column of the
        # margin, and how much of that cell the character covers is
        # the font's business.  So the check asks each side for a
        # pixel of the box's colour somewhere in that column.
        #
        # The first column of a window that has a neighbour on its
        # left belongs to Emacs: it draws its own border there, in the
        # frame's colour.  That column is not the box's to answer for.
        cells = [range(left, left + CELL)] if not left else []
        cells.append(range(right - CELL, right))
        gaps = [] if not sides else [
            y for y in range(want_top, want_bottom + 1)
            if not all(any(close(image.getpixel((x, y)), BOX) for x in cell)
                       for cell in cells)]
        if gaps:
            failures.append(f"window at {left},{top}: the sides break at "
                            f"y={gaps[:5]}{' and on' if len(gaps) > 5 else ''}")
    return failures, found


def main():
    image = Image.open(PNG).convert("RGB")
    with open(GEOMETRY, encoding="utf-8") as handle:
        windows = [tuple(int(n) for n in line.split())
                   for line in handle if line.strip()]
    if not windows:
        print("FAIL: no boxed window reported")
        return 1
    failures, found = check(image, windows)
    for corner, columns, rows in found:
        print(f"boxed window at {corner}: side edges x={columns}, "
              f"horizontal edges y={rows}")
    with open(ENCLOSES_GEOMETRY, encoding="utf-8") as handle:
        examples = [tuple(int(n) for n in line.split())
                    for line in handle if line.strip()]
    if not examples:
        print("FAIL: no window-box-encloses example reported")
        return 1
    more, shown = check_encloses(Image.open(ENCLOSES_PNG).convert("RGB"),
                                 examples)
    failures += more
    for corner, edges, wanted, sides in shown:
        print(f"encloses example at {corner}: edges y={edges}, "
              f"wanted {wanted}, {sides}")
    for failure in failures:
        print("FAIL:", failure)
    print("pixel box:", "BROKEN" if failures else "OK")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
