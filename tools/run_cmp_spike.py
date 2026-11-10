#!/usr/bin/env python3
"""Run the eight test programs in the ISS and in Spike and compare the traces.

    python tools/run_cmp_spike.py              all eight programs
    python tools/run_cmp_spike.py shifts       only the named ones

Before running it: build florv (cmake --build build) and the test programs
(tools\\build_tests.bat). Spike runs in WSL; see --spike for how it is started.

For each program it writes tests/build/NAME.csv (the ISS trace) and
tests/build/NAME.spike.txt (Spike's commit log) and compares them with cmp_spike.

Exit codes: 0 every program matches, 1 at least one does not, 2 something could not
be run.
"""

from __future__ import annotations

import argparse
import os
import shlex
import subprocess
import sys
from pathlib import Path

import cmp_spike

ROOT = Path(__file__).resolve().parent.parent

PROGRAMS = [
    "alu_basic",
    "shifts",
    "compare_signed_unsigned",
    "branches_all",
    "jal_jalr",
    "loads_stores_widths",
    "lui_auipc",
    "fib_loop",
]

# Spike is in ~/riscv/bin of the WSL Ubuntu user. $HOME is expanded inside WSL, so no
# user name is written here.
DEFAULT_SPIKE = "wsl -d Ubuntu -e sh -c 'exec \"$HOME/riscv/bin/spike\" \"$@\"' spike"
SPIKE_OPTIONS = ["--isa=rv32i", "-m0x80000000:0x10000", "--log-commits"]

MSYS2_BIN = r"C:\msys64\ucrt64\bin"  # florv.exe needs the compiler's DLLs from here


def run_one(name: str, florv: Path, spike_command: list, build_dir: Path) -> str:
    """Runs one program on both sides. Returns "" on a match, else what went wrong."""
    elf = build_dir / f"{name}.elf"
    csv = build_dir / f"{name}.csv"
    log = build_dir / f"{name}.spike.txt"
    if not elf.exists():
        return f"{elf} not found; run tools\\build_tests.bat"

    environment = dict(os.environ)
    if os.path.isdir(MSYS2_BIN):
        environment["PATH"] = MSYS2_BIN + os.pathsep + environment.get("PATH", "")

    iss = subprocess.run([str(florv), "iss", str(elf), "--trace", str(csv)],
                         capture_output=True, text=True, env=environment)
    if iss.returncode != 0:
        return f"florv iss exited with {iss.returncode}: {iss.stdout.strip()} {iss.stderr.strip()}"

    # The ELF path is given relative to the repo root with forward slashes: WSL starts
    # in the same folder, so the same relative path works there.
    relative_elf = elf.relative_to(ROOT).as_posix()
    try:
        spike = subprocess.run(spike_command + SPIKE_OPTIONS + [relative_elf],
                               capture_output=True, text=True, cwd=ROOT, timeout=120)
    except subprocess.TimeoutExpired:
        return "Spike did not exit within 120 s"
    except OSError as error:
        return f"Spike could not be started: {error}"
    if spike.returncode != 0:
        return f"Spike exited with {spike.returncode}: {spike.stderr.strip()[-200:]}"

    # Spike writes the commit log to standard error.
    log.write_text(spike.stderr, encoding="utf-8", newline="\n")

    try:
        mismatch, iss_records, spike_records = cmp_spike.compare_files(str(csv), str(log))
    except (OSError, cmp_spike.TraceError) as error:
        return str(error)
    if mismatch is not None:
        return cmp_spike.format_report(mismatch, iss_records, spike_records)

    print(f"  {name:<26} MATCH  {len(iss_records):>4} instructions")
    return ""


def main() -> int:
    parser = argparse.ArgumentParser(description="Compare the ISS with Spike on the test programs.")
    parser.add_argument("programs", nargs="*", default=PROGRAMS,
                        help="program names without extension (default: all eight)")
    parser.add_argument("--florv", default=str(ROOT / "build" / "florv.exe"),
                        help="the florv executable (default: build/florv.exe)")
    parser.add_argument("--build-dir", default=str(ROOT / "tests" / "build"),
                        help="where the ELFs are and the traces go (default: tests/build)")
    parser.add_argument("--spike", default=DEFAULT_SPIKE,
                        help="command that starts Spike (default: %(default)s)")
    arguments = parser.parse_args()

    florv = Path(arguments.florv)
    if not florv.exists():
        print(f"run_cmp_spike: {florv} not found; build it with cmake --build build",
              file=sys.stderr)
        return 2
    spike_command = shlex.split(arguments.spike)
    build_dir = Path(arguments.build_dir).resolve()

    failed = 0
    for name in arguments.programs:
        problem = run_one(name, florv, spike_command, build_dir)
        if problem:
            failed += 1
            print(f"  {name:<26} FAIL")
            for line in problem.splitlines():
                print(f"      {line}")

    total = len(arguments.programs)
    if failed:
        print(f"RESULT: FAIL ({total - failed}/{total} programs match Spike)")
        return 1
    print(f"RESULT: PASS ({total}/{total} programs match Spike)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
