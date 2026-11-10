/* Memory layout shared by every test program: 64 KiB of RAM at 0x80000000, the same
 * RAM the ISS, Spike (-m0x80000000:0x10000) and the block RAM on the board have.
 *
 * Link with tests/start.S first:
 *   riscv64-unknown-elf-gcc -march=rv32i -mabi=ilp32 -nostdlib -T tests/link.ld \
 *       tests/start.S tests/asm/NAME.S -o tests/build/NAME.elf
 */

OUTPUT_ARCH(riscv)
ENTRY(_start)

MEMORY
{
    RAM (rwx) : ORIGIN = 0x80000000, LENGTH = 64K
}

SECTIONS
{
    /* Code. .text.init is start.S and comes first, so _start is at 0x80000000 and
     * falls straight into the test's own .text. */
    .text :
    {
        *(.text.init)
        *(.text .text.*)
    } > RAM

    .rodata : ALIGN(4)
    {
        *(.rodata .rodata.*)
    } > RAM

    /* tohost and fromhost, defined in start.S. Spike finds them by name; the 64-byte
     * alignment keeps them in a block of their own, as the RISC-V tests do. */
    .tohost : ALIGN(64)
    {
        *(.tohost)
    } > RAM

    /* Initialised data. A test that produces a signature puts it in .signature. */
    .data : ALIGN(64)
    {
        *(.data .data.*)
        *(.sdata .sdata.*)
        . = ALIGN(4);
        begin_signature = .;
        *(.signature)
        . = ALIGN(4);
        end_signature = .;
    } > RAM

    /* Zero-initialised data: takes no room in the file, the loader clears it. */
    .bss (NOLOAD) : ALIGN(4)
    {
        *(.sbss .sbss.*)
        *(.bss .bss.*)
        *(COMMON)
        . = ALIGN(4);
    } > RAM

    PROVIDE(_end = .);

    /* The stack grows down from the last address of the RAM. */
    PROVIDE(_stack_top = ORIGIN(RAM) + LENGTH(RAM));

    /DISCARD/ :
    {
        *(.comment)
        *(.riscv.attributes)
        *(.note .note.*)
    }
}
