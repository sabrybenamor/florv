Code in core/ compiles unchanged for the PC (MSYS2 g++) and the bare-metal Cortex-A9 (arm-none-eabi-g++): no OS calls, no exceptions, no iostream, and no heap allocation in the per-instruction path.
