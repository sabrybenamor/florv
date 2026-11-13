"""Draws the block diagram of rtl/rv_core.vhd into docs/core_blocks.png.

Run from the repo root:  python tools/draw_core_blocks.py

The drawing is in the hand-sketched style of docs/image.png: pastel boxes, black
wobbly outlines, a handwriting font, solid arrows for data and dashed arrows for
control. The boxes are the registers, the four blocks of task 3.1 and the
processes of the `rtl` architecture; the state diagram of the FSM box is
docs/core.png (tools/draw_core.py).

Not every wire is drawn. Left out: the control signals of `decode` to the ALU,
the next-pc logic and the multiplexers; pc + 4 into the write-back multiplexer
(shown as a stub); and most of the retire group.
Needs matplotlib. The font is "Ink Free", which Windows has; without it
matplotlib falls back to the next name in FONT.
"""

from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import Circle, Polygon, Rectangle

OUT = Path(__file__).resolve().parent.parent / "docs" / "core_blocks.png"

FONT = ["Ink Free", "Segoe Print", "Comic Sans MS", "DejaVu Sans"]
INK = "#111111"
SKETCH = (1.0, 110.0, 2.0)  # scale, length, randomness of the wobble

GREEN = "#cdefc9"   # the core
PINK = "#f7bfc6"    # the RAM outside
OLIVE = "#dce0a0"   # memory port
ORANGE = "#f7cb9c"  # retire port
AMBER = "#f2a93b"   # registers
BLUE = "#5a9be6"    # FSM
STEEL = "#6fa9de"   # ALU, next pc
CYAN = "#6fd3e6"    # decode, imm_gen
ROSE = "#c65383"    # register file
CREAM = "#fbe3b5"   # load, write-back
LILAC = "#d8b4f8"   # the checker outside

HEAD_LEN = 0.30
HEAD_HALF = 0.11


def text(ax, x, y, s, size=11, color=INK, ha="center", va="center", **kw):
    ax.text(x, y, s, fontsize=size, color=color, ha=ha, va=va, family=FONT, **kw)


def box(ax, x0, y0, x1, y1, fill, label="", size=14, color=INK, lw=1.7, z=2, **kw):
    r = Rectangle((x0, y0), x1 - x0, y1 - y0, facecolor=fill, edgecolor=INK,
                  linewidth=lw, zorder=z)
    r.set_sketch_params(*SKETCH)
    ax.add_patch(r)
    if label:
        text(ax, (x0 + x1) / 2, (y0 + y1) / 2, label, size=size, color=color,
             zorder=z + 1, **kw)


def head(ax, tip, back, color=INK):
    """A filled arrowhead at `tip`, pointing away from `back`."""
    dx, dy = tip[0] - back[0], tip[1] - back[1]
    n = (dx * dx + dy * dy) ** 0.5
    ux, uy = dx / n, dy / n
    bx, by = tip[0] - ux * HEAD_LEN, tip[1] - uy * HEAD_LEN
    tri = Polygon([tip, (bx - uy * HEAD_HALF, by + ux * HEAD_HALF),
                   (bx + uy * HEAD_HALF, by - ux * HEAD_HALF)],
                  closed=True, facecolor=color, edgecolor=color, linewidth=0.8, zorder=6)
    tri.set_sketch_params(None)
    ax.add_patch(tri)


def wire(ax, pts, heads="end", dashed=False, color=INK, slash=None, lw=1.5):
    """A line through `pts` with an arrowhead at the end, at both ends, or none.

    `slash` is a point on a horizontal part where a bus mark is drawn.
    """
    xs = [p[0] for p in pts]
    ys = [p[1] for p in pts]
    (line,) = ax.plot(xs, ys, color=color, linewidth=lw, zorder=5,
                      linestyle=(0, (3.5, 3)) if dashed else "-",
                      solid_capstyle="round", solid_joinstyle="round")
    line.set_sketch_params(*SKETCH)
    if heads in ("end", "both"):
        head(ax, pts[-1], pts[-2], color)
    if heads == "both":
        head(ax, pts[0], pts[1], color)
    if slash:
        (mark,) = ax.plot([slash[0] - 0.11, slash[0] + 0.11], [slash[1] - 0.2, slash[1] + 0.2],
                          color=color, linewidth=lw, zorder=5)
        mark.set_sketch_params(None)


def dot(ax, x, y):
    c = Circle((x, y), 0.075, facecolor=INK, edgecolor=INK, zorder=6)
    c.set_sketch_params(None)
    ax.add_patch(c)


def main():
    fig, ax = plt.subplots(figsize=(17, 10.6), dpi=150)
    ax.set_xlim(-0.4, 25.2)
    ax.set_ylim(0.9, 15.6)
    ax.set_aspect("equal")
    ax.axis("off")

    # ---- the three big boxes ------------------------------------------------
    box(ax, 5.0, 2.0, 20.6, 13.8, GREEN, z=1)
    text(ax, 5.35, 13.25, "rv_core", size=19, ha="left")

    box(ax, 0.0, 5.4, 2.4, 9.9, PINK, "Program\nRAM", size=16)
    box(ax, 22.4, 5.2, 24.8, 9.2, LILAC, "Trace /\nchecker", size=15)

    # ---- the two ports on the edges ----------------------------------------
    box(ax, 5.4, 5.0, 6.3, 10.2, OLIVE, "M\nE\nM", size=17, linespacing=1.25)
    box(ax, 19.3, 3.6, 20.2, 10.2, ORANGE, "R\nE\nT\nI\nR\nE", size=16, linespacing=1.15)

    # ---- inside the core ---------------------------------------------------
    box(ax, 11.0, 11.8, 15.0, 13.0, BLUE)
    text(ax, 13.0, 12.62, "FSM", size=16, color="white", zorder=3)
    text(ax, 13.0, 12.12, "fetch, exec, mem, wb, trap", size=10.5, color="white", zorder=3)

    box(ax, 7.2, 9.0, 8.8, 10.0, AMBER, "pc")
    box(ax, 7.2, 7.1, 8.8, 8.1, AMBER, "ir")
    box(ax, 7.2, 4.5, 8.8, 5.7, CREAM, "load\nextend", size=11.5, linespacing=1.2)
    box(ax, 9.4, 4.3, 10.4, 5.9, CREAM, "wb\nmux", size=12, linespacing=1.2)

    box(ax, 11.0, 8.9, 13.0, 9.9, CYAN, "imm_gen")
    box(ax, 11.0, 6.9, 13.0, 8.1, CYAN, "decode")
    box(ax, 11.0, 4.2, 13.0, 6.0, ROSE, "regfile\nx0 .. x31", color="white", linespacing=1.1)

    box(ax, 14.6, 8.6, 16.2, 9.8, STEEL, "next pc", color="white")
    box(ax, 14.6, 4.2, 16.2, 6.9, STEEL)
    text(ax, 15.75, 5.55, "A\nL\nU", size=14, color="white", zorder=3, linespacing=1.05)
    for y, name in ((6.5, "pc"), (5.95, "imm"), (5.4, "rs1"), (4.7, "rs2")):
        text(ax, 14.72, y, name, size=9.5, color="white", ha="left", zorder=3)

    box(ax, 17.0, 8.6, 18.4, 9.8, AMBER, "next\npc reg", size=11, linespacing=1.1)
    box(ax, 17.0, 5.0, 18.4, 6.0, AMBER, "alu_out", size=12)

    # ---- memory port <-> RAM ----------------------------------------------
    for y, name, heads in ((9.3, "mem_addr", "end"), (8.4, "mem_wdata", "end"),
                           (7.5, "mem_be, we, en", "end")):
        wire(ax, [(5.4, y), (2.4, y)], heads, slash=(4.55, y))
        text(ax, 3.75, y + 0.27, name, size=10)
    wire(ax, [(2.4, 6.2), (5.4, 6.2)], slash=(3.3, 6.2))
    text(ax, 4.2, 6.47, "mem_rdata", size=10)

    # ---- fetch: pc -> port, port -> ir and load ------------------------------
    wire(ax, [(7.2, 9.5), (6.3, 9.5)])
    wire(ax, [(6.3, 6.4), (6.75, 6.4), (6.75, 7.6), (7.2, 7.6)])
    wire(ax, [(6.75, 6.4), (6.75, 5.1), (7.2, 5.1)])
    dot(ax, 6.75, 6.4)

    # ---- ir -> decode and imm_gen -----------------------------------------
    wire(ax, [(8.8, 7.6), (11.0, 7.6)])
    wire(ax, [(10.0, 7.6), (10.0, 9.4), (11.0, 9.4)])
    dot(ax, 10.0, 7.6)

    # ---- decode -> regfile -> ALU -----------------------------------------
    wire(ax, [(12.0, 6.9), (12.0, 6.0)])
    text(ax, 11.85, 6.45, "rs1, rs2, rd", size=9.5, ha="right")
    wire(ax, [(13.0, 5.4), (14.6, 5.4)])
    wire(ax, [(13.0, 4.7), (14.6, 4.7)])

    # ---- imm -> next pc and ALU -------------------------------------------
    wire(ax, [(13.0, 9.4), (14.6, 9.4)])
    wire(ax, [(14.0, 9.4), (14.0, 5.95), (14.6, 5.95)])
    dot(ax, 14.0, 9.4)

    # ---- pc -> next pc and ALU --------------------------------------------
    wire(ax, [(8.4, 10.0), (8.4, 10.5), (15.4, 10.5), (15.4, 9.8)])
    wire(ax, [(13.5, 10.5), (13.5, 6.5), (14.6, 6.5)])
    dot(ax, 13.5, 10.5)
    text(ax, 10.6, 10.72, "pc", size=10.5)

    # ---- ALU -> next pc, alu_out; next pc -> register -> pc ----------------
    wire(ax, [(15.0, 6.9), (15.0, 8.6)])
    text(ax, 15.15, 7.75, "target,\ncompare", size=9.5, ha="left", linespacing=1.25)
    wire(ax, [(16.2, 5.5), (17.0, 5.5)])
    wire(ax, [(16.2, 9.2), (17.0, 9.2)])
    wire(ax, [(17.7, 9.8), (17.7, 11.1), (7.6, 11.1), (7.6, 10.0)])
    text(ax, 10.6, 11.32, "next pc, taken in wb", size=10.5)

    # ---- alu_out -> address of a load or store, and write-back --------------
    wire(ax, [(17.7, 5.0), (17.7, 2.9), (5.65, 2.9), (5.65, 5.0)])
    text(ax, 14.2, 2.62, "address of a load or store", size=10.5)
    wire(ax, [(9.9, 2.9), (9.9, 4.3)])
    dot(ax, 9.9, 2.9)

    # ---- rs2 -> store data ------------------------------------------------
    wire(ax, [(13.8, 4.7), (13.8, 3.5), (6.05, 3.5), (6.05, 5.0)])
    dot(ax, 13.8, 4.7)
    text(ax, 7.9, 3.75, "store data", size=10.5)

    # ---- write-back -------------------------------------------------------
    wire(ax, [(8.8, 5.1), (9.4, 5.1)])
    wire(ax, [(10.4, 5.1), (11.0, 5.1)])
    wire(ax, [(9.9, 6.55), (9.9, 5.9)])
    text(ax, 9.9, 6.78, "pc + 4", size=9.5)

    # ---- retire port -------------------------------------------------------
    wire(ax, [(18.4, 9.2), (19.3, 9.2)])
    wire(ax, [(18.4, 5.5), (19.3, 5.5)])
    text(ax, 18.8, 7.35, "pc, ir,\nrd,\nvalue", size=9.5, linespacing=1.3)
    for y in (8.5, 7.9, 6.5, 5.9):
        wire(ax, [(20.2, y), (22.4, y)], slash=(21.5, y))
    text(ax, 21.3, 7.2, "- - - -", size=14)
    text(ax, 21.3, 9.55, "retire_*", size=11)

    # ---- control from the FSM (dashed) --------------------------------------
    wire(ax, [(11.0, 12.4), (5.85, 12.4), (5.85, 10.2)], dashed=True)
    text(ax, 8.4, 12.13, "read, write", size=10.5)
    wire(ax, [(15.0, 12.4), (19.75, 12.4), (19.75, 10.2)], dashed=True)
    text(ax, 17.4, 12.67, "retire_valid", size=10.5)

    for x, name in ((11.8, "clk"), (12.6, "rstn"), (13.4, "run")):
        wire(ax, [(x, 14.9), (x, 13.0)])
        text(ax, x, 15.15, name, size=11)
    wire(ax, [(14.3, 13.0), (14.3, 14.9)])
    text(ax, 14.3, 15.15, "trap", size=11)

    text(ax, 5.0, 1.45, "solid: data      dashed: control from the FSM      / : a bus",
         size=10.5, ha="left")

    fig.savefig(OUT, bbox_inches="tight", facecolor="white")
    print(f"wrote {OUT}")


if __name__ == "__main__":
    main()
