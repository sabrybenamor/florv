#!/usr/bin/env python3
"""Compare a florv ISS trace with a Spike commit log, instruction by instruction.

    python tools/cmp_spike.py <iss.csv> <spike.log>

<iss.csv> is the trace written by "florv iss prog.elf --trace" (the format is in
docs/trace-format.md). <spike.log> is what "spike --log-commits" prints for the same
program. tools/run_cmp_spike.py produces both files for the eight test programs.

Exit codes: 0 every instruction matches and both sides halted,
            1 a mismatch, reported with the three instructions before it,
            2 a file cannot be read or is not in the expected format.
"""

from __future__ import annotations

import argparse
import re
import sys
from dataclasses import dataclass
from typing import List, Optional

RAM_BASE = 0x80000000  # Spike's boot ROM runs below this and is skipped
CONTEXT = 3            # how many earlier instructions a report shows

CSV_HEADER = "order,pc,insn,next_pc,rd,rd_wdata,mem_addr,mem_mask,mem_wdata"
MASK_TO_BYTES = {"1": 1, "3": 2, "f": 4}


class TraceError(Exception):
    """A trace file that is not in the expected format."""


@dataclass(frozen=True)
class Record:
    """What one retired instruction did, in the form both sides are reduced to.

    None means "does not apply": no register written, no memory access, or (for
    store_data) a load. mem_bytes is None when the width is not known, which is the
    case for a load in a Spike log.
    """

    pc: int
    insn: int
    rd: Optional[int] = None
    rd_wdata: Optional[int] = None
    mem_addr: Optional[int] = None
    mem_bytes: Optional[int] = None
    store_data: Optional[int] = None


@dataclass(frozen=True)
class Mismatch:
    index: int                # position in the trace, 0 is the first instruction
    field: str                # which part differs
    iss: Optional[Record]     # None when the ISS trace has no such instruction
    spike: Optional[Record]   # None when the Spike log has no such instruction
    detail: str = ""


# --------------------------------------------------------------------------
# Spike commit log
# --------------------------------------------------------------------------

# core   0: 3 0x80000014 (0x00532023) mem 0x80000040 0x00000001
_SPIKE_LINE = re.compile(r"^core\s+\d+:\s+\d+\s+0x([0-9a-fA-F]+)\s+\(0x([0-9a-fA-F]+)\)(.*)$")
_REGISTER = re.compile(r"^x(\d+)$")


def parse_spike_line(line: str) -> Optional[Record]:
    """One log line as a Record, or None when the line is not a commit line."""
    match = _SPIKE_LINE.match(line.strip())
    if match is None:
        return None
    pc = int(match.group(1), 16)
    insn = int(match.group(2), 16)

    rd = rd_wdata = mem_addr = mem_bytes = store_data = None
    tokens = match.group(3).split()
    i = 0
    while i < len(tokens):
        token = tokens[i]
        register = _REGISTER.match(token)
        if register and i + 1 < len(tokens):
            # x5  0x00000001
            rd = int(register.group(1))
            rd_wdata = int(tokens[i + 1], 16)
            i += 2
        elif token == "mem" and i + 1 < len(tokens):
            # load:  mem 0x80000187          store: mem 0x80000195 0xdd
            mem_addr = int(tokens[i + 1], 16)
            i += 2
            if i < len(tokens) and tokens[i].startswith("0x"):
                digits = tokens[i][2:]
                store_data = int(digits, 16)
                mem_bytes = len(digits) // 2  # Spike prints the data at the access width
                i += 1
        else:
            i += 1  # something this tool does not compare, such as a CSR write

    if rd == 0:
        rd = rd_wdata = None  # a write to x0 changes nothing
    return Record(pc, insn, rd, rd_wdata, mem_addr, mem_bytes, store_data)


def parse_spike_log(text: str, base: int = RAM_BASE) -> List[Record]:
    """Every commit line with a pc at or above base, in order."""
    records = []
    for line in text.splitlines():
        record = parse_spike_line(line)
        if record is not None and record.pc >= base:
            records.append(record)
    return records


# --------------------------------------------------------------------------
# ISS trace (docs/trace-format.md)
# --------------------------------------------------------------------------

def _hex_or_none(text: str) -> Optional[int]:
    return None if text == "-" else int(text, 16)


def parse_iss_csv(text: str) -> List[Record]:
    lines = [line.rstrip("\r") for line in text.splitlines()]
    if not lines or lines[0] != CSV_HEADER:
        raise TraceError("the ISS trace does not start with the header line")

    records = []
    for number, line in enumerate(lines[1:], start=2):
        if line == "":
            continue
        fields = line.split(",")
        if len(fields) != 9:
            raise TraceError(f"ISS trace line {number}: expected 9 fields, found {len(fields)}")
        _order, pc, insn, _next_pc, rd, rd_wdata, mem_addr, mem_mask, mem_wdata = fields
        try:
            if mem_mask != "-" and mem_mask not in MASK_TO_BYTES:
                raise ValueError(f"mem_mask {mem_mask!r}")
            records.append(Record(
                pc=int(pc, 16),
                insn=int(insn, 16),
                rd=None if rd == "-" else int(rd),
                rd_wdata=_hex_or_none(rd_wdata),
                mem_addr=_hex_or_none(mem_addr),
                mem_bytes=None if mem_mask == "-" else MASK_TO_BYTES[mem_mask],
                store_data=_hex_or_none(mem_wdata),
            ))
        except ValueError as error:
            raise TraceError(f"ISS trace line {number}: {error}") from None
    return records


# --------------------------------------------------------------------------
# Comparison
# --------------------------------------------------------------------------

def _first_difference(iss: Record, spike: Record) -> Optional[str]:
    """The name of the first field in which two records differ, or None."""
    if iss.pc != spike.pc:
        return "pc"
    if iss.insn != spike.insn:
        return "insn"
    if iss.rd != spike.rd:
        return "rd"
    if iss.rd_wdata != spike.rd_wdata:
        return "rd_wdata"
    if (iss.mem_addr is None) != (spike.mem_addr is None):
        return "memory access"
    if iss.mem_addr != spike.mem_addr:
        return "mem_addr"
    if (iss.store_data is None) != (spike.store_data is None):
        return "load or store"
    # The width is compared only where Spike shows it, which is for stores.
    if iss.mem_bytes is not None and spike.mem_bytes is not None:
        if iss.mem_bytes != spike.mem_bytes:
            return "store width"
    if iss.store_data is not None and spike.store_data is not None:
        mask = (1 << (8 * (iss.mem_bytes or 4))) - 1
        if (iss.store_data & mask) != (spike.store_data & mask):
            return "store data"
    return None


def compare(iss: List[Record], spike: List[Record]) -> Optional[Mismatch]:
    """The first mismatch between the two traces, or None when they agree.

    They agree when every ISS instruction equals the Spike instruction at the same
    position, the ISS trace ends with the store that halts the program, and Spike did
    nothing after that store except sit in the program's final loop.
    """
    for index, iss_record in enumerate(iss):
        if index >= len(spike):
            return Mismatch(index, "length", iss_record, None,
                            "the Spike log ends before the ISS trace does")
        field = _first_difference(iss_record, spike[index])
        if field is not None:
            return Mismatch(index, field, iss_record, spike[index])

    if not iss:
        return Mismatch(0, "halt", None, spike[0] if spike else None,
                        "the ISS trace is empty")

    # The ISS halts on a word store of a non-zero value to tohost, so that is what
    # the last line of a complete trace must be. Anything else means the step limit
    # or a trap ended the run.
    last = iss[-1]
    if last.store_data is None or last.mem_bytes != 4 or last.store_data == 0:
        return Mismatch(len(iss) - 1, "halt", last, spike[len(iss) - 1],
                        "the ISS trace does not end with a store to tohost")

    # After the store Spike keeps running until its host interface notices. A test
    # program sits in a one-instruction loop there. If Spike does anything else, the
    # ISS stopped too early.
    tail = spike[len(iss):]
    for offset, record in enumerate(tail):
        if record.pc != tail[0].pc or record.insn != tail[0].insn:
            return Mismatch(len(iss) + offset, "halt", None, record,
                            "Spike went on executing after the ISS halted")
    return None


# --------------------------------------------------------------------------
# Report
# --------------------------------------------------------------------------

def format_record(record: Optional[Record]) -> str:
    """A record as one line of text, the same way for both sides."""
    if record is None:
        return "(nothing)"
    text = f"pc={record.pc:08x} insn={record.insn:08x}"
    if record.rd is not None:
        text += f" x{record.rd}={record.rd_wdata:08x}"
    if record.mem_addr is not None:
        if record.store_data is None:
            text += f" load addr={record.mem_addr:08x}"
        else:
            digits = 2 * (record.mem_bytes or 4)
            text += f" store addr={record.mem_addr:08x} data={record.store_data:0{digits}x}"
    return text


def format_report(mismatch: Mismatch, iss: List[Record], spike: List[Record]) -> str:
    lines = [f"MISMATCH at instruction {mismatch.index}: {mismatch.field}"]
    if mismatch.detail:
        lines.append(f"  {mismatch.detail}")
    lines.append(f"  iss  : {format_record(mismatch.iss)}")
    lines.append(f"  spike: {format_record(mismatch.spike)}")

    first = max(0, mismatch.index - CONTEXT)
    if first < mismatch.index:
        lines.append("before it (the two sides agree here):")
        for index in range(first, mismatch.index):
            # Up to the mismatch both sides hold the same record; show whichever exists.
            record = iss[index] if index < len(iss) else spike[index]
            lines.append(f"  {index:>5}: {format_record(record)}")
    return "\n".join(lines)


# --------------------------------------------------------------------------
# Command line
# --------------------------------------------------------------------------

def compare_files(csv_path: str, log_path: str, base: int = RAM_BASE):
    """Returns (mismatch or None, iss records, spike records)."""
    with open(csv_path, "r", encoding="ascii", errors="replace", newline="") as file:
        iss = parse_iss_csv(file.read())
    with open(log_path, "r", encoding="utf-8", errors="replace") as file:
        spike = parse_spike_log(file.read(), base)
    return compare(iss, spike), iss, spike


def main(argv: Optional[List[str]] = None) -> int:
    parser = argparse.ArgumentParser(
        description="Compare a florv ISS trace with a Spike commit log.")
    parser.add_argument("csv", help="trace written by 'florv iss --trace'")
    parser.add_argument("log", help="output of 'spike --log-commits'")
    arguments = parser.parse_args(argv)

    try:
        mismatch, iss, spike = compare_files(arguments.csv, arguments.log)
    except (OSError, TraceError) as error:
        print(f"cmp_spike: {error}", file=sys.stderr)
        return 2

    if mismatch is not None:
        print(format_report(mismatch, iss, spike))
        return 1
    print(f"MATCH: {len(iss)} instructions")
    return 0


if __name__ == "__main__":
    sys.exit(main())
