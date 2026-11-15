# Register map of `rv_rig`

This document is the only place the registers of `rv_rig` are defined. The VHDL in
`ip_repo/rv_rig_1_0` and the C++ in `arm/` are both written from it and do not
repeat the rules.

It describes revision 2 of the block (ID `0x52560002`), the first one that holds
the RISC-V core. Revision 1 had the ID and seven scratch registers.

## The block

| Item | Value |
|---|---|
| Bus | AXI4-Lite slave, 32-bit data |
| Base address | `0x43C00000` |
| Registers | 8, each 32 bits, at offset = register number × 4 |
| Clock | `FCLK_CLK0`, 50 MHz, shared with the core |

Only address bits 4:2 are decoded, so the eight registers repeat every `0x20`
bytes through the 64 KiB range. Software uses offsets `0x00` to `0x1C` only.

## Registers

| Offset | Name | Access | After power-up | Purpose |
|---|---|---|---|---|
| `0x00` | `ID` | read-only | `0x52560002` | Identifies the block and its revision |
| `0x04` | `SCRATCH` | read/write | `0x00000000` | Holds what was written; used by the loopback test |
| `0x08` | `CTRL` | read/write | `0x00000002` | Controls the core |
| `0x0C` | `STATUS` | read-only | `0x00000000` | State of the core |
| `0x10` | `LAST_PC` | read-only | `0x00000000` | Address of the last instruction counted |
| `0x14` | `RETIRE_COUNT` | read-only | `0x00000000` | Number of instructions counted |
| `0x18` | `TRACE_HEAD` | reserved | `0x00000000` | Arrives with the trace RAM (revision 3) |
| `0x1C` | `TRACE_TAIL` | reserved | `0x00000000` | Arrives with the trace RAM (revision 3) |

### `ID` (`0x00`)

`0x5256` is "RV" in ASCII; the low 16 bits are the revision.

| Revision | ID | Content |
|---|---|---|
| 1 | `0x52560001` | ID and seven scratch registers |
| 2 | `0x52560002` | This document: the core, `CTRL`, `STATUS`, `LAST_PC`, `RETIRE_COUNT` |
| 3 | `0x52560003` | Adds the trace RAM, `TRACE_HEAD` and `TRACE_TAIL` |

The application reads `ID` before anything else and stops with a message when it
is not the revision it was built for. Vitis will run new software on an old
bitstream without complaint; this check is what catches it.

### `SCRATCH` (`0x04`)

A plain register. All 32 bits are stored and read back. It is not connected to the
core.

### `CTRL` (`0x08`)

| Bit | Name | 0 | 1 |
|---|---|---|---|
| 0 | `RUN` | The core stops between two instructions | The core executes |
| 1 | `RESET` | The core is out of reset | The core is held in reset |
| 31:2 | | Write 0; read as 0 | |

- After power-up `CTRL` is `0x00000002`: the core is held in reset and does not
  run, so it never executes a RAM that has not been loaded.
- `RESET` wins over `RUN`: with both set, the core is in reset.
- The core's reset is `RESET` or the reset of the AXI bus, whichever is active.
- `RUN` = 0 pauses the core after the instruction it is executing. Setting `RUN`
  again continues with the next instruction; nothing is lost.
- Only the ARM writes this register. The core cannot change it.

### `STATUS` (`0x0C`)

| Bit | Name | Meaning when 1 |
|---|---|---|
| 0 | `RUNNING` | The core is executing: `RUN` is 1, `RESET` is 0 and `TRAPPED` is 0 |
| 1 | `STALLED` | The core has retired an instruction that jumps to itself |
| 2 | `TRAPPED` | The core's `trap` output is 1 |
| 31:3 | | Read as 0 |

- `STALLED` is set by the first retire whose next pc equals its own pc, and stays
  set until the core is reset. Such an instruction repeats for ever (RV32I has no
  interrupt that could end it), and it is how every test program ends: `1: j 1b`
  after the store to `tohost`. `RUNNING` stays 1 while the core spins there.
- `TRAPPED` stays 1 until the core is reset, because the core stays in its trap
  state until then. The causes are those of the core: an illegal word, a
  misaligned load or store, a jump or taken branch to an address that is not a
  multiple of 4.
- The block does not know the `tohost` address. Whether the program passed is
  read from the `tohost` word in the RAM, not from this register.

### `LAST_PC` (`0x10`) and `RETIRE_COUNT` (`0x14`)

`RETIRE_COUNT` is the number of instructions the core has retired since its reset,
and `LAST_PC` is the address of the last of them.

**An instruction that jumps to itself is not counted** and does not change
`LAST_PC`. This is what makes the two registers comparable with the ISS:
`florv iss` stops at the store to `tohost`, while the core goes on into the final
loop and retires its `j` again and again. With this rule the registers stop moving
at the store, so after a program that ended normally:

- `RETIRE_COUNT` equals the `retired:` line of `florv iss`;
- `LAST_PC` is the address of the store to `tohost`.

Other rules:

- Both are 0 while the core is in reset, and start from 0 after it.
- `RETIRE_COUNT` wraps to 0 after `0xFFFFFFFF`.
- After a trap, `LAST_PC` is the last instruction that retired, not the one that
  trapped: an instruction that traps does not retire.
- They keep their values while `RUN` is 0.

### `TRACE_HEAD` (`0x18`) and `TRACE_TAIL` (`0x1C`)

Reserved for revision 3. In revision 2 they read as 0 and writes are ignored.

## Writes to read-only and reserved registers

A write to `ID`, `STATUS`, `LAST_PC`, `RETIRE_COUNT`, `TRACE_HEAD` or `TRACE_TAIL`
changes nothing. The bus still answers `OKAY`, for reads and writes of every
register; the block never reports a bus error.

`SCRATCH` and `CTRL` honour the byte strobes of the bus: only the bytes that are
written change.

## What the core's reset does not do

- It does not clear the RAM. The ARM writes the whole RAM when it loads a program.
- It does not clear registers `x1` to `x31` of the core: the register file has no
  reset. They are 0 after the bitstream is loaded and keep the values of the last
  program after that, where the ISS always starts from 0. A program must therefore
  give every register a value before it reads it, as the test programs do.

## How the ARM runs a program

| Step | Action | Register |
|---|---|---|
| 1 | Check the revision | read `ID`, expect `0x52560002` |
| 2 | Hold the core in reset | write `CTRL` = `0x00000002` |
| 3 | Load the program into the RAM at `0x40000000` | (not in this block) |
| 4 | Release the reset and start | write `CTRL` = `0x00000001` |
| 5 | Wait until the `tohost` word in the RAM is not 0, or `TRAPPED` is 1, or a timeout | read `STATUS` |
| 6 | Wait until `STALLED` is 1 | read `STATUS` |
| 7 | Read the result | read `LAST_PC`, `RETIRE_COUNT` |
| 8 | Stop the core | write `CTRL` = `0x00000002` |

Step 6 is there because the ARM can see the `tohost` word change before the store
has retired; once `STALLED` is 1 the two counters are final. Step 8 clears
`LAST_PC` and `RETIRE_COUNT`, so it comes after step 7.

## C++ names

| Name | Value |
|---|---|
| `kRegId` | `0x00` |
| `kRegScratch` | `0x04` |
| `kRegCtrl` | `0x08` |
| `kRegStatus` | `0x0C` |
| `kRegLastPc` | `0x10` |
| `kRegRetireCount` | `0x14` |
| `kCtrlRun` | `1u << 0` |
| `kCtrlReset` | `1u << 1` |
| `kStatusRunning` | `1u << 0` |
| `kStatusStalled` | `1u << 1` |
| `kStatusTrapped` | `1u << 2` |
| `kExpectedId` | `0x52560002` |
