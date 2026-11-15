# florv

florv is a rig for validating a RISC-V processor on an FPGA. A small RV32I core
written in VHDL runs in the programmable logic of a Digilent Zybo (Zynq XC7Z010).
The same program runs in a C++ instruction-set simulator (ISS), and a bare-metal
C++ checker on the board's Cortex-A9 compares every instruction the core finishes
with the simulator's result. The first difference names the instruction where the
hardware went wrong.

![Block diagram of rv_core](docs/core_blocks.png)

The core, [`rtl/rv_core.vhd`](rtl/rv_core.vhd), is a multi-cycle processor with a
memory port on one side and a retire port on the other. The retire port reports
each finished instruction (pc, instruction word, register write, memory access),
and that record is what the checker compares with the ISS.

## The core on the board

![Block diagram of rv_rig: the ARM, the registers, the core and the program RAM](docs/mermaid-diagram.png)

On the FPGA the core sits inside `rv_rig`, a block the ARM reaches over AXI4-Lite.
Its registers are defined in [`docs/regmap.md`](docs/regmap.md):

- `CTRL` holds the core in reset or lets it run, and only the ARM can write it.
- `STATUS`, `LAST_PC` and `RETIRE_COUNT` come from
  [`rtl/core_status.vhd`](rtl/core_status.vhd), which watches the core's retire
  port. After a program ends they hold the same values the ISS reports.

The ARM and the core share one dual-port block RAM. The ARM loads the program
through port A while the core is held in reset; the core then fetches, loads and
stores through port B.

## Parts

| Folder | What it holds |
|---|---|
| `rtl/`, `tb/` | The core in VHDL-2008 and its self-checking testbenches |
| `ip_repo/` | `rv_rig`, the AXI4-Lite block that holds the core and its registers |
| `core/` | The ISS, decoder, memory and ELF loader in C++; the same code builds for the PC and the Cortex-A9 |
| `host/` | `florv`, a command-line tool that runs an ELF in the ISS and writes a trace |
| `arm/` | The bare-metal application for the Zynq processor, where the checker goes |
| `tests/`, `tools/` | RISC-V test programs, unit tests, and scripts that compare the ISS with Spike |

## Status

Work in progress.

- The ISS executes all 40 RV32I instructions and agrees with Spike on eight test
  programs (659 instructions).
- The core passes its testbenches in simulation. On all eight programs its retire
  trace equals the ISS trace byte for byte.
- `rv_rig` with the core inside passes its testbench in simulation: driven over
  AXI4-Lite, it runs a program and reports the retire count and last pc of the
  ISS. It is not built into a bitstream yet, so the core has not run on the board.
- The lockstep checker, random programs and the RISCOF architecture tests are not
  started.
