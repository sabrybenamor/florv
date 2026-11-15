#!/usr/bin/env python3
"""Compare two retire traces in the CSV format of docs/trace-format.md.

    python tools/diff_trace.py <rtl.csv> <iss.csv>

<rtl.csv> is the trace tb_core writes with the generic TRACE_FILE (through
tb/trace_logger.vhd). <iss.csv> is the trace of "florv iss prog.elf --trace" for
the same program. The two must be equal byte for byte.

The files are compared as bytes, line by line, so a carriage return or a missing
line feed at the end is a difference too. The first line that differs is printed
with its line number (the header is line 1), both versions of it, and the columns
that differ. When one file is shorter, the first line it lacks is the mismatch.

Exit codes: 0 the files are identical,
            1 a mismatch,
            2 a file cannot be read or is empty (a trace has at least its header).
"""

from __future__ import annotations

import argparse
import sys
from dataclasses import dataclass
from typing import List, Optional

COLUMNS = "order,pc,insn,next_pc,rd,rd_wdata,mem_addr,mem_mask,mem_wdata".split(",")


class TraceError(Exception):
    """A file that cannot be a trace."""


@dataclass(frozen=True)
class Mismatch:
    """The first difference. A line is None when that file has ended."""

    line_number: int  # counted from 1; the header is line 1
    rtl: Optional[bytes]
    iss: Optional[bytes]


def split_lines(data: bytes) -> List[bytes]:
    """Splits at line feeds only and keeps them, so "a\\r\\n" and "a\\n" differ.

    A last line without a line feed is kept as it is, without one.
    """
    lines = data.split(b"\n")
    last = lines.pop()
    lines = [line + b"\n" for line in lines]
    if last:
        lines.append(last)
    return lines


def first_mismatch(rtl: bytes, iss: bytes) -> Optional[Mismatch]:
    """The first line on which the two files differ, or None when they are equal."""
    rtl_lines = split_lines(rtl)
    iss_lines = split_lines(iss)
    for index in range(max(len(rtl_lines), len(iss_lines))):
        rtl_line = rtl_lines[index] if index < len(rtl_lines) else None
        iss_line = iss_lines[index] if index < len(iss_lines) else None
        if rtl_line != iss_line:
            return Mismatch(index + 1, rtl_line, iss_line)
    return None


def show(line: Optional[bytes]) -> str:
    """One line as it is printed in a report, with what the eye would miss."""
    if line is None:
        return "(the file ends before this line)"
    text = line.decode("ascii", "backslashreplace")
    note = ""
    if text.endswith("\n"):
        text = text[:-1]
    else:
        note = "   (no line feed at the end)"
    return text.replace("\r", "\\r") + note


def differing_columns(mismatch: Mismatch) -> List[str]:
    """Names of the columns that differ, when both lines have the nine fields."""
    if mismatch.rtl is None or mismatch.iss is None:
        return []
    rtl_fields = mismatch.rtl.rstrip(b"\n").split(b",")
    iss_fields = mismatch.iss.rstrip(b"\n").split(b",")
    if len(rtl_fields) != len(COLUMNS) or len(iss_fields) != len(COLUMNS):
        return []
    return [name for name, a, b in zip(COLUMNS, rtl_fields, iss_fields) if a != b]


def format_report(mismatch: Mismatch) -> str:
    where = f"line {mismatch.line_number}"
    if mismatch.line_number == 1:
        where += " (the header)"
    else:
        # Line 2 holds instruction 0.
        where += f" (instruction {mismatch.line_number - 2})"
    report = [
        f"MISMATCH at {where}",
        f"  rtl: {show(mismatch.rtl)}",
        f"  iss: {show(mismatch.iss)}",
    ]
    columns = differing_columns(mismatch)
    if columns:
        report.append(f"  differs in: {', '.join(columns)}")
    return "\n".join(report)


def read_trace(path: str) -> bytes:
    with open(path, "rb") as file:
        data = file.read()
    if not data:
        raise TraceError(f"{path} is empty; a trace has at least its header line")
    return data


def main(argv: Optional[List[str]] = None) -> int:
    parser = argparse.ArgumentParser(
        description="Compare two retire traces byte for byte.")
    parser.add_argument("rtl", help="trace written by tb_core (TRACE_FILE)")
    parser.add_argument("iss", help="trace written by 'florv iss --trace'")
    arguments = parser.parse_args(argv)

    try:
        rtl = read_trace(arguments.rtl)
        iss = read_trace(arguments.iss)
    except (OSError, TraceError) as error:
        print(f"diff_trace: {error}", file=sys.stderr)
        return 2

    mismatch = first_mismatch(rtl, iss)
    if mismatch is not None:
        print(format_report(mismatch))
        return 1
    print(f"MATCH: {len(split_lines(rtl)) - 1} instructions")
    return 0


if __name__ == "__main__":
    sys.exit(main())
