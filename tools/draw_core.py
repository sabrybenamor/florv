"""Draws the state diagram of rtl/rv_core.vhd into docs/core.png.

Run from the repo root:  python tools/draw_core.py

The state names and the conditions on the arrows are those of the `fsm` process
in rtl/rv_core.vhd. When that process changes, change this file and run it again.
Needs matplotlib.
"""

from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import FancyArrowPatch, FancyBboxPatch

OUT = Path(__file__).resolve().parent.parent / "docs" / "core.png"

BOX_W = 3.0
BOX_H = 1.3

INK = "#1f2933"
LINE = "#52606d"
FILL = "#eef2f7"
TRAP_FILL = "#fde8e8"
TRAP_LINE = "#b42318"

# name: (centre x, centre y, what the state does)
STATES = {
    "S_FETCH": (2.0, 4.0, "read the word at pc\ninto ir"),
    "S_EXEC": (7.0, 4.0, "decode, ALU, branch\ndecision, next pc"),
    "S_MEM": (12.0, 4.0, "load: read a word\nstore: write bytes"),
    "S_WB": (7.0, 0.9, "write rd, pc := next pc,\nretire_valid = '1'"),
    "S_TRAP": (7.0, 7.1, "stopped, trap = '1'"),
}


def box(ax, name):
    x, y, text = STATES[name]
    trap = name == "S_TRAP"
    ax.add_patch(FancyBboxPatch(
        (x - BOX_W / 2, y - BOX_H / 2), BOX_W, BOX_H,
        boxstyle="round,pad=0.02,rounding_size=0.18",
        facecolor=TRAP_FILL if trap else FILL,
        edgecolor=TRAP_LINE if trap else LINE, linewidth=1.6))
    ax.text(x, y + 0.30, name, ha="center", va="center", fontsize=13,
            fontweight="bold", family="monospace", color=INK)
    ax.text(x, y - 0.25, text, ha="center", va="center", fontsize=9.5, color=INK)


def arrow(ax, start, end, label, label_at, rad=0.0, color=LINE, align="center"):
    ax.add_patch(FancyArrowPatch(
        start, end, arrowstyle="-|>", mutation_scale=16, linewidth=1.5,
        color=color, connectionstyle=f"arc3,rad={rad}", shrinkA=0, shrinkB=0))
    ax.text(label_at[0], label_at[1], label, ha=align, va="center", fontsize=9.5,
            color=INK, linespacing=1.3)


def loop(ax, name, label, side):
    """A self-loop on the top (side = 1) or the bottom (side = -1) of a box."""
    x, y, _ = STATES[name]
    edge = y + side * BOX_H / 2
    ax.add_patch(FancyArrowPatch(
        (x - 0.55, edge), (x + 0.55, edge), arrowstyle="-|>", mutation_scale=16,
        linewidth=1.5, color=LINE, connectionstyle=f"arc3,rad={-1.5 * side}",
        shrinkA=0, shrinkB=0))
    ax.text(x, edge + side * 1.4, label, ha="center", va="center", fontsize=9.5,
            color=INK, linespacing=1.3)


def main():
    fig, ax = plt.subplots(figsize=(12.5, 7.6), dpi=150)
    ax.set_xlim(-2.4, 14.4)
    ax.set_ylim(-0.6, 8.6)
    ax.set_aspect("equal")
    ax.axis("off")

    for name in STATES:
        box(ax, name)

    fx, fy, _ = STATES["S_FETCH"]
    ex, ey, _ = STATES["S_EXEC"]
    mx, my, _ = STATES["S_MEM"]
    wx, wy, _ = STATES["S_WB"]
    tx, ty, _ = STATES["S_TRAP"]
    hw, hh = BOX_W / 2, BOX_H / 2

    # Reset comes from every state, so it is drawn as an arrow from nowhere.
    arrow(ax, (fx - hw - 2.2, fy), (fx - hw, fy), "rstn = '0'\n(from any state)\npc := RESET_PC",
          (fx - hw - 1.25, fy + 0.85))

    arrow(ax, (fx + hw, fy), (ex - hw, ey), "the word\nhas arrived", ((fx + ex) / 2, fy + 0.5))
    arrow(ax, (ex + hw, ey), (mx - hw, my), "load or store", ((ex + mx) / 2, ey + 0.3))
    arrow(ax, (ex, ey + hh), (tx, ty - hh),
          "illegal word,\nmisaligned load or store,\nmisaligned jump or branch target",
          (ex + 0.25, (ey + ty) / 2), color=TRAP_LINE, align="left")
    arrow(ax, (ex, ey - hh), (wx, wy + hh), "every other\ninstruction", (ex + 0.25, (ey + wy) / 2),
          align="left")
    arrow(ax, (mx, my - hh), (wx + hw, wy), "store: after one cycle\nload: the word has arrived",
          (mx - 0.4, wy + 0.75), rad=-0.25, align="left")
    arrow(ax, (wx - hw, wy), (fx, fy - hh), "always", (fx + 0.9, wy + 0.75), rad=-0.25)

    loop(ax, "S_FETCH", "run = '0',\nor waiting for the word", 1)
    loop(ax, "S_MEM", "load: waiting\nfor the word", 1)
    loop(ax, "S_TRAP", "until reset", 1)

    ax.text(-2.3, -0.35,
            "A read takes READ_LATENCY + 1 clock cycles: one to present the address, "
            "READ_LATENCY to wait for the word.\n"
            "With READ_LATENCY = 1: a store takes 5 cycles, a load 6, every other instruction 4.",
            ha="left", va="center", fontsize=9, color=LINE, linespacing=1.4)

    fig.savefig(OUT, bbox_inches="tight", facecolor="white")
    print(f"wrote {OUT}")


if __name__ == "__main__":
    main()
