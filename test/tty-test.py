#!/usr/bin/env python3
"""Terminal test for window-box.

Runs Emacs in a pseudo terminal, feeds the byte stream into a pyte
screen, and asserts the box glyphs around the boxed window.  Needs
python3 and pyte; run through `make tty'.
"""
import os
import pty
import select
import sys
import time

import pyte

HERE = os.path.dirname(os.path.abspath(__file__))
COLS, ROWS = 80, 24

screen = pyte.Screen(COLS, ROWS)
stream = pyte.ByteStream(screen)
env = dict(os.environ, TERM="xterm-256color", COLUMNS=str(COLS), LINES=str(ROWS))
emacs = env.get("EMACS", "emacs")

pid, fd = pty.fork()
if pid == 0:
    os.execvpe(emacs, [emacs, "-nw", "-Q",
                       "-l", os.path.join(HERE, "tty-test.el")], env)

end = time.time() + 30
while time.time() < end:
    ready, _, _ = select.select([fd], [], [], 0.5)
    if ready:
        try:
            data = os.read(fd, 65536)
        except OSError:
            break
        if not data:
            break
        stream.feed(data)

lines = screen.display
failures = []
if not (lines[0].startswith("┌") and lines[0].rstrip().endswith("┐")
        and "─" in lines[0]):
    failures.append(f"top edge: {lines[0]!r}")
if not any(l.startswith("│") and l.rstrip().endswith("│") for l in lines[1:5]):
    failures.append("side edges missing on the text lines")
bottoms = [l for l in lines if l.startswith("└")]
if not (bottoms and bottoms[0].rstrip().endswith("┘")):
    failures.append("bottom edge missing")
# The sides run to the bottom edge, over the rows below the last line
# of text: an overlay stops at the end of the buffer, a line prefix
# does not.
for number, line in enumerate(lines):
    if line.startswith("└"):
        above = lines[number - 1]
        if not (above.startswith("│") and above.rstrip().endswith("│")):
            failures.append("the sides stop above the bottom edge: "
                            f"{above.rstrip()!r}")
        break
# Every top edge closes with a corner, the one beside a neighbour too.
for number, line in enumerate(lines):
    for start in (i for i, c in enumerate(line) if c == "┌"):
        rest = line[start:]
        end = rest.find("┐")
        if end < 0:
            failures.append(f"row {number}: an edge from column {start} "
                            f"never closes: {line!r}")
if "boxed in the terminal" not in "\n".join(lines):
    failures.append("buffer text missing")
# The window that keeps its own rows: the box takes them in, so its
# header line rides between the sides and its mode line closes the
# box, a terminal having no row below one.
# Two such windows side by side, so the one left of the divider is
# checked as well: a terminal spends a column of that window on the
# separator, and an end placed by the row's own right edge lands in it.
for name in ("*rows*", "*more rows*"):
    header = [l for l in lines if f"a header line in {name} " in l]
    mode = [l for l in lines if f"a mode line in {name} " in l]
    if not header or not mode:
        failures.append(f"{name}: no header or mode line on the screen")
        continue
    # A screen line holds both windows; the separator column splits it.
    def segment(line, wanted):
        return next((piece for piece in line.split("|") if wanted in piece),
                    line)
    piece = segment(header[0], name)
    # *rows* right-aligns a button in its header; the box keeps the
    # last column all the same.
    if name == "*rows*" and "[x]" not in piece:
        failures.append(f"{name}: the header lost its button: {piece!r}")
    if not (piece.startswith("│") and piece.rstrip().endswith("│")):
        failures.append(f"{name}: the header line is not inside the box: "
                        f"{piece!r}")
    piece = segment(mode[0], name)
    if not (piece.startswith("└") and piece.rstrip().endswith("┘")):
        failures.append(f"{name}: the mode line does not close the box: "
                        f"{piece!r}")
    column = header[0].index(segment(header[0], name))
    above = lines[lines.index(header[0]) - 1][column:].split("|")[0]
    if not (above.startswith("┌") and above.rstrip().endswith("┐")):
        failures.append(f"{name}: no top edge above the header line: "
                        f"{above!r}")

for number, line in enumerate(lines):
    if any(glyph in line for glyph in "┌┐└┘│"):
        print(f"{number:2d}|{line.rstrip()}")
for failure in failures:
    print("FAIL:", failure)
print("terminal box:", "BROKEN" if failures else "OK")
sys.exit(1 if failures else 0)
