# Trace format

This document is the only place the retire trace is defined. Code and scripts that
write or read a trace point here and do not repeat the rules.

A trace has one entry for each instruction that retired, in the order they retired.
The fields are those of `RetireRecord` in `core/retire_record.hpp`.

## CSV trace

A text file with one header line and then one line per retired instruction.
`florv iss` writes it; the Spike converter, the VHDL testbench and the board output
will write the same format, so any two traces can be compared with `diff`.

### Columns

```
order,pc,insn,next_pc,rd,rd_wdata,mem_addr,mem_mask,mem_wdata
```

| Column | Written as | Meaning |
|---|---|---|
| `order` | decimal, no leading zeros | Retire count. The first instruction is 0 and each line adds 1. |
| `pc` | 8 hex digits | Address of the instruction. |
| `insn` | 8 hex digits | The instruction word. |
| `next_pc` | 8 hex digits | Address of the instruction that runs next. |
| `rd` | decimal 1 to 31, or `-` | Register written. `-` when no register was written. |
| `rd_wdata` | 8 hex digits, or `-` | Value written to `rd`. `-` when `rd` is `-`. |
| `mem_addr` | 8 hex digits, or `-` | Address of the load or store. `-` when there is no memory access. |
| `mem_mask` | 1 hex digit, or `-` | Bytes accessed, one bit per byte counted from `mem_addr`: `1` byte, `3` half word, `f` word. `-` when there is no memory access. |
| `mem_wdata` | 8 hex digits, or `-` | Value stored, in the low bits, upper bits 0. `-` for a load and when there is no memory access. |

### Rules

- Hex is lower case, without `0x`, and always the full width given above.
- Fields are separated by a single comma. There are no spaces, no quotes and no
  comma at the end of the line.
- Every line, the header and the last line included, ends with one line feed
  (`\n`). There is no carriage return, on Windows too.
- The header line is always present and is exactly the line under "Columns".
- A write to `x0` changes nothing, so it is written as no register write: `rd` and
  `rd_wdata` are both `-`. This is why `rd` is never `0`.
- A load and a store are told apart by `mem_wdata`: a store has a value there, a
  load has `-`. The value a load read is in `rd_wdata`.
- A load into `x0` still accesses memory: `mem_addr` and `mem_mask` are filled, and
  `rd`, `rd_wdata` and `mem_wdata` are `-`.
- Only retired instructions have a line. An instruction that traps does not retire
  and is not in the trace.
- The instruction that halts the program retires, so it is the last line of the
  trace: the store to `tohost`, or an `ecall` or `ebreak`.

### Example

The complete trace of `tests/data/minimal.elf`, which stores 1 to `tohost` with its
fourth instruction:

```
order,pc,insn,next_pc,rd,rd_wdata,mem_addr,mem_mask,mem_wdata
0,80000000,00100513,80000004,10,00000001,-,-,-
1,80000004,00001597,80000008,11,80001004,-,-,-
2,80000008,01858593,8000000c,11,8000101c,-,-,-
3,8000000c,00a5a023,80000010,-,-,8000101c,f,00000001
```

The lines are `addi x10,x0,1`, `auipc x11,0x1`, `addi x11,x11,24` and
`sw x10,0(x11)`.

A load looks like this (`lbu x10,12(x2)` reading the byte `0x80`; not part of the
program above):

```
9,80000018,00c14503,8000001c,10,00000080,8000100c,1,-
```
