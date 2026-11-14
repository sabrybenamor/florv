# Register dump format

The register dump is a text file with the 32 registers as they are when a run ends. Two programs write it, and the two files must be equal byte for byte:

- `florv iss prog.elf --regs FILE` writes it from the ISS, however the run ended (halt, trap or step limit);
- `tb/tb_core.vhd` writes it from the VHDL core's register file when the generic `REGS_FILE` is set and the run passed.

## The file

- Exactly 32 lines, `x0` first and `x31` last.
- A line is `x`, the register number in decimal with no leading zero, one space, and the value as 8 lower-case hex digits with no `0x`.
- Every line, the last one too, ends in a line feed alone (no carriage return).
- `x0` is always `00000000`.

```
x0 00000000
x1 00000000
x2 80010000
...
x31 00000000
```

## When the registers are read

Both sides read the registers after the instruction that stores to `tohost` has retired. That instruction is a store and writes no register, so the values are those left by the instructions before it.
