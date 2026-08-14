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
WIDTH = 1                      # window-box draws one pixel lines
BOX = (127, 127, 127)          # the `shadow' foreground of the default theme


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
        for run in columns + rows:
            if len(run) != WIDTH:
                failures.append(f"window at {left},{top}: an edge is "
                                f"{len(run)} pixels, want {WIDTH}")
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
    for failure in failures:
        print("FAIL:", failure)
    print("pixel box:", "BROKEN" if failures else "OK")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
