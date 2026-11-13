-- Self-checking testbench for rv_core. Run it with:  tools\sim.bat tb_rv_core_insns
-- It prints PASS when every check held and stops at the first one that did not.
--
-- tb_rv_core tests the state machine. This one tests the instructions:
--
--   Part 1  One program of 114 words runs each of the 40 RV32I instructions at
--           least once, and every load and store at every legal offset inside a
--           word. The testbench checks every field of every retire, the number
--           of clock cycles each instruction takes, and at the end every word
--           of the RAM, so a store that reached a byte it should not have is
--           seen too.
--   Part 2  21 programs of four words. The fourth word of each must trap: a
--           load or a store at an address that is not a multiple of its size,
--           or a jump or a taken branch to an address that is not a multiple
--           of 4. Three instructions retire, then the trap comes, and the only
--           memory accesses are the four fetches.
--
-- The words are from the assembler: tests/data/core_insns.S for part 1 and
-- tests/data/core_traps.S for part 2; each file says how to build and
-- disassemble it. The expected records are what the ISS (class Iss in core/)
-- gives for the same words when it is stepped until it traps. "florv iss
-- --trace" prints the same records up to the ecall, where it stops.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.rv32i_pkg.all;

entity tb_rv_core_insns is
    generic (
        READ_LATENCY : positive := 1
    );
end entity tb_rv_core_insns;

architecture sim of tb_rv_core_insns is

    constant CLK_PERIOD : time := 20 ns;  -- 50 MHz, the clock of the fabric

    constant RAM_BASE  : word_t  := x"80000000";
    constant RAM_WORDS : natural := 512;  -- 0x80000000 to 0x800007FF

    type word_array_t is array (natural range <>) of word_t;

    ---------------------------------------------------------------------------
    -- Part 1: the program of tests/data/core_insns.S
    ---------------------------------------------------------------------------
    constant PROGRAM : word_array_t := (
        x"123450B7",  -- 80000000  lui   x1,0x12345
        x"67808093",  -- 80000004  addi  x1,x1,1656
        x"FFF00113",  -- 80000008  addi  x2,x0,-1
        x"00500193",  -- 8000000c  addi  x3,x0,5
        x"80000237",  -- 80000010  lui   x4,0x80000
        x"00112513",  -- 80000014  slti  x10,x2,1
        x"FFF1B593",  -- 80000018  sltiu x11,x3,-1
        x"FFF0C613",  -- 8000001c  xori  x12,x1,-1
        x"7000E693",  -- 80000020  ori   x13,x1,1792
        x"0F00F713",  -- 80000024  andi  x14,x1,240
        x"00409793",  -- 80000028  slli  x15,x1,0x4
        x"00425813",  -- 8000002c  srli  x16,x4,0x4
        x"40425893",  -- 80000030  srai  x17,x4,0x4
        x"00208933",  -- 80000034  add   x18,x1,x2
        x"402089B3",  -- 80000038  sub   x19,x1,x2
        x"00309A33",  -- 8000003c  sll   x20,x1,x3
        x"00312AB3",  -- 80000040  slt   x21,x2,x3
        x"00313B33",  -- 80000044  sltu  x22,x2,x3
        x"0020CBB3",  -- 80000048  xor   x23,x1,x2
        x"00325C33",  -- 8000004c  srl   x24,x4,x3
        x"40325CB3",  -- 80000050  sra   x25,x4,x3
        x"0030ED33",  -- 80000054  or    x26,x1,x3
        x"0110FDB3",  -- 80000058  and   x27,x1,x17
        x"00219E33",  -- 8000005c  sll   x28,x3,x2
        x"00001E97",  -- 80000060  auipc x29,0x1
        x"0FF0000F",  -- 80000064  fence iorw,iorw
        x"00108013",  -- 80000068  addi  x0,x1,1
        x"00000F33",  -- 8000006c  add   x30,x0,x0
        x"800002B7",  -- 80000070  lui   x5,0x80000
        x"40028293",  -- 80000074  addi  x5,x5,1024
        x"E1A27337",  -- 80000078  lui   x6,0xe1a27
        x"38430313",  -- 8000007c  addi  x6,x6,900
        x"0062A023",  -- 80000080  sw    x6,0(x5)
        x"0002A503",  -- 80000084  lw    x10,0(x5)
        x"00028583",  -- 80000088  lb    x11,0(x5)
        x"00128603",  -- 8000008c  lb    x12,1(x5)
        x"00228683",  -- 80000090  lb    x13,2(x5)
        x"00328703",  -- 80000094  lb    x14,3(x5)
        x"0002C783",  -- 80000098  lbu   x15,0(x5)
        x"0012C803",  -- 8000009c  lbu   x16,1(x5)
        x"0022C883",  -- 800000a0  lbu   x17,2(x5)
        x"0032C903",  -- 800000a4  lbu   x18,3(x5)
        x"00029983",  -- 800000a8  lh    x19,0(x5)
        x"00229A03",  -- 800000ac  lh    x20,2(x5)
        x"0002DA83",  -- 800000b0  lhu   x21,0(x5)
        x"0022DB03",  -- 800000b4  lhu   x22,2(x5)
        x"0002A003",  -- 800000b8  lw    x0,0(x5)
        x"112233B7",  -- 800000bc  lui   x7,0x11223
        x"34438393",  -- 800000c0  addi  x7,x7,836
        x"0072A423",  -- 800000c4  sw    x7,8(x5)
        x"0072A623",  -- 800000c8  sw    x7,12(x5)
        x"0072A823",  -- 800000cc  sw    x7,16(x5)
        x"0072AA23",  -- 800000d0  sw    x7,20(x5)
        x"0072AC23",  -- 800000d4  sw    x7,24(x5)
        x"0072AE23",  -- 800000d8  sw    x7,28(x5)
        x"00628423",  -- 800000dc  sb    x6,8(x5)
        x"006286A3",  -- 800000e0  sb    x6,13(x5)
        x"00628923",  -- 800000e4  sb    x6,18(x5)
        x"00628BA3",  -- 800000e8  sb    x6,23(x5)
        x"00629C23",  -- 800000ec  sh    x6,24(x5)
        x"00629F23",  -- 800000f0  sh    x6,30(x5)
        x"0082AB83",  -- 800000f4  lw    x23,8(x5)
        x"00C2AC03",  -- 800000f8  lw    x24,12(x5)
        x"0102AC83",  -- 800000fc  lw    x25,16(x5)
        x"0142AD03",  -- 80000100  lw    x26,20(x5)
        x"0182AD83",  -- 80000104  lw    x27,24(x5)
        x"01C2AE03",  -- 80000108  lw    x28,28(x5)
        x"04028413",  -- 8000010c  addi  x8,x5,64
        x"FE142E23",  -- 80000110  sw    x1,-4(x8)
        x"FFC42483",  -- 80000114  lw    x9,-4(x8)
        x"FE340DA3",  -- 80000118  sb    x3,-5(x8)
        x"FFB44503",  -- 8000011c  lbu   x10,-5(x8)
        x"0A310263",  -- 80000120  beq   x2,x3,800001c4 <stop>
        x"0A319063",  -- 80000124  bne   x3,x3,800001c4 <stop>
        x"0821CE63",  -- 80000128  blt   x3,x2,800001c4 <stop>
        x"0831CC63",  -- 8000012c  blt   x3,x3,800001c4 <stop>
        x"08315A63",  -- 80000130  bge   x2,x3,800001c4 <stop>
        x"08316863",  -- 80000134  bltu  x2,x3,800001c4 <stop>
        x"0831E663",  -- 80000138  bltu  x3,x3,800001c4 <stop>
        x"0821F463",  -- 8000013c  bgeu  x3,x2,800001c4 <stop>
        x"00318463",  -- 80000140  beq   x3,x3,80000148
        x"0800006F",  -- 80000144  jal   x0,800001c4 <stop>
        x"00311463",  -- 80000148  bne   x2,x3,80000150
        x"0780006F",  -- 8000014c  jal   x0,800001c4 <stop>
        x"00314463",  -- 80000150  blt   x2,x3,80000158
        x"0700006F",  -- 80000154  jal   x0,800001c4 <stop>
        x"0021D463",  -- 80000158  bge   x3,x2,80000160
        x"0680006F",  -- 8000015c  jal   x0,800001c4 <stop>
        x"0031D463",  -- 80000160  bge   x3,x3,80000168
        x"0600006F",  -- 80000164  jal   x0,800001c4 <stop>
        x"0021E463",  -- 80000168  bltu  x3,x2,80000170
        x"0580006F",  -- 8000016c  jal   x0,800001c4 <stop>
        x"00317463",  -- 80000170  bgeu  x2,x3,80000178
        x"0500006F",  -- 80000174  jal   x0,800001c4 <stop>
        x"0031F463",  -- 80000178  bgeu  x3,x3,80000180
        x"0480006F",  -- 8000017c  jal   x0,800001c4 <stop>
        x"00300593",  -- 80000180  addi  x11,x0,3
        x"FFF58593",  -- 80000184  addi  x11,x11,-1
        x"FE059EE3",  -- 80000188  bne   x11,x0,80000184 <loop>
        x"00C0006F",  -- 8000018c  jal   x0,80000198 <forward>
        x"00160613",  -- 80000190  addi  x12,x12,1
        x"00008067",  -- 80000194  jalr  x0,0(x1)
        x"00A00613",  -- 80000198  addi  x12,x0,10
        x"FF5FF0EF",  -- 8000019c  jal   x1,80000190 <func>
        x"00000697",  -- 800001a0  auipc x13,0x0
        x"00D686E7",  -- 800001a4  jalr  x13,13(x13)
        x"01C0006F",  -- 800001a8  jal   x0,800001c4 <stop>
        x"00000717",  -- 800001ac  auipc x14,0x0
        x"01470713",  -- 800001b0  addi  x14,x14,20
        x"FFC707E7",  -- 800001b4  jalr  x15,-4(x14)
        x"00C0006F",  -- 800001b8  jal   x0,800001c4 <stop>
        x"00000073",  -- 800001bc  ecall
        x"00100073",  -- 800001c0  ebreak
        x"00000000"   -- 800001c4  illegal word: the core traps here
    );

    -- The illegal word that ends the program.
    constant STOP_PC   : word_t := x"800001C4";
    constant STOP_INSN : word_t := x"00000000";

    -- One expected retire, with the fields of the retire group.
    type retire_t is record
        pc        : word_t;
        insn      : word_t;
        next_pc   : word_t;
        rd        : natural range 0 to 31;
        rd_wdata  : word_t;
        mem_addr  : word_t;
        mem_mask  : std_logic_vector(3 downto 0);
        mem_wdata : word_t;
        is_load   : std_logic;
        is_store  : std_logic;
    end record;

    type retire_array_t is array (natural range <>) of retire_t;

    constant Z : word_t := x"00000000";

    -- In the order the instructions retire. The comment is the index and the
    -- instruction.
    constant EXPECTED : retire_array_t := (
        --  pc           insn         next_pc      rd  rd_wdata     mem_addr     mask  mem_wdata   load store
        (x"80000000", x"123450B7", x"80000004",  1, x"12345000", Z,           x"0", Z,           '0', '0'),  --   0  lui   x1,0x12345
        (x"80000004", x"67808093", x"80000008",  1, x"12345678", Z,           x"0", Z,           '0', '0'),  --   1  addi  x1,x1,1656
        (x"80000008", x"FFF00113", x"8000000C",  2, x"FFFFFFFF", Z,           x"0", Z,           '0', '0'),  --   2  addi  x2,x0,-1
        (x"8000000C", x"00500193", x"80000010",  3, x"00000005", Z,           x"0", Z,           '0', '0'),  --   3  addi  x3,x0,5
        (x"80000010", x"80000237", x"80000014",  4, x"80000000", Z,           x"0", Z,           '0', '0'),  --   4  lui   x4,0x80000
        (x"80000014", x"00112513", x"80000018", 10, x"00000001", Z,           x"0", Z,           '0', '0'),  --   5  slti  x10,x2,1
        (x"80000018", x"FFF1B593", x"8000001C", 11, x"00000001", Z,           x"0", Z,           '0', '0'),  --   6  sltiu x11,x3,-1
        (x"8000001C", x"FFF0C613", x"80000020", 12, x"EDCBA987", Z,           x"0", Z,           '0', '0'),  --   7  xori  x12,x1,-1
        (x"80000020", x"7000E693", x"80000024", 13, x"12345778", Z,           x"0", Z,           '0', '0'),  --   8  ori   x13,x1,1792
        (x"80000024", x"0F00F713", x"80000028", 14, x"00000070", Z,           x"0", Z,           '0', '0'),  --   9  andi  x14,x1,240
        (x"80000028", x"00409793", x"8000002C", 15, x"23456780", Z,           x"0", Z,           '0', '0'),  --  10  slli  x15,x1,0x4
        (x"8000002C", x"00425813", x"80000030", 16, x"08000000", Z,           x"0", Z,           '0', '0'),  --  11  srli  x16,x4,0x4
        (x"80000030", x"40425893", x"80000034", 17, x"F8000000", Z,           x"0", Z,           '0', '0'),  --  12  srai  x17,x4,0x4
        (x"80000034", x"00208933", x"80000038", 18, x"12345677", Z,           x"0", Z,           '0', '0'),  --  13  add   x18,x1,x2
        (x"80000038", x"402089B3", x"8000003C", 19, x"12345679", Z,           x"0", Z,           '0', '0'),  --  14  sub   x19,x1,x2
        (x"8000003C", x"00309A33", x"80000040", 20, x"468ACF00", Z,           x"0", Z,           '0', '0'),  --  15  sll   x20,x1,x3
        (x"80000040", x"00312AB3", x"80000044", 21, x"00000001", Z,           x"0", Z,           '0', '0'),  --  16  slt   x21,x2,x3
        (x"80000044", x"00313B33", x"80000048", 22, x"00000000", Z,           x"0", Z,           '0', '0'),  --  17  sltu  x22,x2,x3
        (x"80000048", x"0020CBB3", x"8000004C", 23, x"EDCBA987", Z,           x"0", Z,           '0', '0'),  --  18  xor   x23,x1,x2
        (x"8000004C", x"00325C33", x"80000050", 24, x"04000000", Z,           x"0", Z,           '0', '0'),  --  19  srl   x24,x4,x3
        (x"80000050", x"40325CB3", x"80000054", 25, x"FC000000", Z,           x"0", Z,           '0', '0'),  --  20  sra   x25,x4,x3
        (x"80000054", x"0030ED33", x"80000058", 26, x"1234567D", Z,           x"0", Z,           '0', '0'),  --  21  or    x26,x1,x3
        (x"80000058", x"0110FDB3", x"8000005C", 27, x"10000000", Z,           x"0", Z,           '0', '0'),  --  22  and   x27,x1,x17
        (x"8000005C", x"00219E33", x"80000060", 28, x"80000000", Z,           x"0", Z,           '0', '0'),  --  23  sll   x28,x3,x2
        (x"80000060", x"00001E97", x"80000064", 29, x"80001060", Z,           x"0", Z,           '0', '0'),  --  24  auipc x29,0x1
        (x"80000064", x"0FF0000F", x"80000068",  0, Z,           Z,           x"0", Z,           '0', '0'),  --  25  fence iorw,iorw
        (x"80000068", x"00108013", x"8000006C",  0, Z,           Z,           x"0", Z,           '0', '0'),  --  26  addi  x0,x1,1
        (x"8000006C", x"00000F33", x"80000070", 30, x"00000000", Z,           x"0", Z,           '0', '0'),  --  27  add   x30,x0,x0
        (x"80000070", x"800002B7", x"80000074",  5, x"80000000", Z,           x"0", Z,           '0', '0'),  --  28  lui   x5,0x80000
        (x"80000074", x"40028293", x"80000078",  5, x"80000400", Z,           x"0", Z,           '0', '0'),  --  29  addi  x5,x5,1024
        (x"80000078", x"E1A27337", x"8000007C",  6, x"E1A27000", Z,           x"0", Z,           '0', '0'),  --  30  lui   x6,0xe1a27
        (x"8000007C", x"38430313", x"80000080",  6, x"E1A27384", Z,           x"0", Z,           '0', '0'),  --  31  addi  x6,x6,900
        (x"80000080", x"0062A023", x"80000084",  0, Z,           x"80000400", x"F", x"E1A27384", '0', '1'),  --  32  sw    x6,0(x5)
        (x"80000084", x"0002A503", x"80000088", 10, x"E1A27384", x"80000400", x"F", Z,           '1', '0'),  --  33  lw    x10,0(x5)
        (x"80000088", x"00028583", x"8000008C", 11, x"FFFFFF84", x"80000400", x"1", Z,           '1', '0'),  --  34  lb    x11,0(x5)
        (x"8000008C", x"00128603", x"80000090", 12, x"00000073", x"80000401", x"1", Z,           '1', '0'),  --  35  lb    x12,1(x5)
        (x"80000090", x"00228683", x"80000094", 13, x"FFFFFFA2", x"80000402", x"1", Z,           '1', '0'),  --  36  lb    x13,2(x5)
        (x"80000094", x"00328703", x"80000098", 14, x"FFFFFFE1", x"80000403", x"1", Z,           '1', '0'),  --  37  lb    x14,3(x5)
        (x"80000098", x"0002C783", x"8000009C", 15, x"00000084", x"80000400", x"1", Z,           '1', '0'),  --  38  lbu   x15,0(x5)
        (x"8000009C", x"0012C803", x"800000A0", 16, x"00000073", x"80000401", x"1", Z,           '1', '0'),  --  39  lbu   x16,1(x5)
        (x"800000A0", x"0022C883", x"800000A4", 17, x"000000A2", x"80000402", x"1", Z,           '1', '0'),  --  40  lbu   x17,2(x5)
        (x"800000A4", x"0032C903", x"800000A8", 18, x"000000E1", x"80000403", x"1", Z,           '1', '0'),  --  41  lbu   x18,3(x5)
        (x"800000A8", x"00029983", x"800000AC", 19, x"00007384", x"80000400", x"3", Z,           '1', '0'),  --  42  lh    x19,0(x5)
        (x"800000AC", x"00229A03", x"800000B0", 20, x"FFFFE1A2", x"80000402", x"3", Z,           '1', '0'),  --  43  lh    x20,2(x5)
        (x"800000B0", x"0002DA83", x"800000B4", 21, x"00007384", x"80000400", x"3", Z,           '1', '0'),  --  44  lhu   x21,0(x5)
        (x"800000B4", x"0022DB03", x"800000B8", 22, x"0000E1A2", x"80000402", x"3", Z,           '1', '0'),  --  45  lhu   x22,2(x5)
        (x"800000B8", x"0002A003", x"800000BC",  0, Z,           x"80000400", x"F", Z,           '1', '0'),  --  46  lw    x0,0(x5)
        (x"800000BC", x"112233B7", x"800000C0",  7, x"11223000", Z,           x"0", Z,           '0', '0'),  --  47  lui   x7,0x11223
        (x"800000C0", x"34438393", x"800000C4",  7, x"11223344", Z,           x"0", Z,           '0', '0'),  --  48  addi  x7,x7,836
        (x"800000C4", x"0072A423", x"800000C8",  0, Z,           x"80000408", x"F", x"11223344", '0', '1'),  --  49  sw    x7,8(x5)
        (x"800000C8", x"0072A623", x"800000CC",  0, Z,           x"8000040C", x"F", x"11223344", '0', '1'),  --  50  sw    x7,12(x5)
        (x"800000CC", x"0072A823", x"800000D0",  0, Z,           x"80000410", x"F", x"11223344", '0', '1'),  --  51  sw    x7,16(x5)
        (x"800000D0", x"0072AA23", x"800000D4",  0, Z,           x"80000414", x"F", x"11223344", '0', '1'),  --  52  sw    x7,20(x5)
        (x"800000D4", x"0072AC23", x"800000D8",  0, Z,           x"80000418", x"F", x"11223344", '0', '1'),  --  53  sw    x7,24(x5)
        (x"800000D8", x"0072AE23", x"800000DC",  0, Z,           x"8000041C", x"F", x"11223344", '0', '1'),  --  54  sw    x7,28(x5)
        (x"800000DC", x"00628423", x"800000E0",  0, Z,           x"80000408", x"1", x"00000084", '0', '1'),  --  55  sb    x6,8(x5)
        (x"800000E0", x"006286A3", x"800000E4",  0, Z,           x"8000040D", x"1", x"00000084", '0', '1'),  --  56  sb    x6,13(x5)
        (x"800000E4", x"00628923", x"800000E8",  0, Z,           x"80000412", x"1", x"00000084", '0', '1'),  --  57  sb    x6,18(x5)
        (x"800000E8", x"00628BA3", x"800000EC",  0, Z,           x"80000417", x"1", x"00000084", '0', '1'),  --  58  sb    x6,23(x5)
        (x"800000EC", x"00629C23", x"800000F0",  0, Z,           x"80000418", x"3", x"00007384", '0', '1'),  --  59  sh    x6,24(x5)
        (x"800000F0", x"00629F23", x"800000F4",  0, Z,           x"8000041E", x"3", x"00007384", '0', '1'),  --  60  sh    x6,30(x5)
        (x"800000F4", x"0082AB83", x"800000F8", 23, x"11223384", x"80000408", x"F", Z,           '1', '0'),  --  61  lw    x23,8(x5)
        (x"800000F8", x"00C2AC03", x"800000FC", 24, x"11228444", x"8000040C", x"F", Z,           '1', '0'),  --  62  lw    x24,12(x5)
        (x"800000FC", x"0102AC83", x"80000100", 25, x"11843344", x"80000410", x"F", Z,           '1', '0'),  --  63  lw    x25,16(x5)
        (x"80000100", x"0142AD03", x"80000104", 26, x"84223344", x"80000414", x"F", Z,           '1', '0'),  --  64  lw    x26,20(x5)
        (x"80000104", x"0182AD83", x"80000108", 27, x"11227384", x"80000418", x"F", Z,           '1', '0'),  --  65  lw    x27,24(x5)
        (x"80000108", x"01C2AE03", x"8000010C", 28, x"73843344", x"8000041C", x"F", Z,           '1', '0'),  --  66  lw    x28,28(x5)
        (x"8000010C", x"04028413", x"80000110",  8, x"80000440", Z,           x"0", Z,           '0', '0'),  --  67  addi  x8,x5,64
        (x"80000110", x"FE142E23", x"80000114",  0, Z,           x"8000043C", x"F", x"12345678", '0', '1'),  --  68  sw    x1,-4(x8)
        (x"80000114", x"FFC42483", x"80000118",  9, x"12345678", x"8000043C", x"F", Z,           '1', '0'),  --  69  lw    x9,-4(x8)
        (x"80000118", x"FE340DA3", x"8000011C",  0, Z,           x"8000043B", x"1", x"00000005", '0', '1'),  --  70  sb    x3,-5(x8)
        (x"8000011C", x"FFB44503", x"80000120", 10, x"00000005", x"8000043B", x"1", Z,           '1', '0'),  --  71  lbu   x10,-5(x8)
        (x"80000120", x"0A310263", x"80000124",  0, Z,           Z,           x"0", Z,           '0', '0'),  --  72  beq   x2,x3,800001c4 <stop>
        (x"80000124", x"0A319063", x"80000128",  0, Z,           Z,           x"0", Z,           '0', '0'),  --  73  bne   x3,x3,800001c4 <stop>
        (x"80000128", x"0821CE63", x"8000012C",  0, Z,           Z,           x"0", Z,           '0', '0'),  --  74  blt   x3,x2,800001c4 <stop>
        (x"8000012C", x"0831CC63", x"80000130",  0, Z,           Z,           x"0", Z,           '0', '0'),  --  75  blt   x3,x3,800001c4 <stop>
        (x"80000130", x"08315A63", x"80000134",  0, Z,           Z,           x"0", Z,           '0', '0'),  --  76  bge   x2,x3,800001c4 <stop>
        (x"80000134", x"08316863", x"80000138",  0, Z,           Z,           x"0", Z,           '0', '0'),  --  77  bltu  x2,x3,800001c4 <stop>
        (x"80000138", x"0831E663", x"8000013C",  0, Z,           Z,           x"0", Z,           '0', '0'),  --  78  bltu  x3,x3,800001c4 <stop>
        (x"8000013C", x"0821F463", x"80000140",  0, Z,           Z,           x"0", Z,           '0', '0'),  --  79  bgeu  x3,x2,800001c4 <stop>
        (x"80000140", x"00318463", x"80000148",  0, Z,           Z,           x"0", Z,           '0', '0'),  --  80  beq   x3,x3,80000148
        (x"80000148", x"00311463", x"80000150",  0, Z,           Z,           x"0", Z,           '0', '0'),  --  81  bne   x2,x3,80000150
        (x"80000150", x"00314463", x"80000158",  0, Z,           Z,           x"0", Z,           '0', '0'),  --  82  blt   x2,x3,80000158
        (x"80000158", x"0021D463", x"80000160",  0, Z,           Z,           x"0", Z,           '0', '0'),  --  83  bge   x3,x2,80000160
        (x"80000160", x"0031D463", x"80000168",  0, Z,           Z,           x"0", Z,           '0', '0'),  --  84  bge   x3,x3,80000168
        (x"80000168", x"0021E463", x"80000170",  0, Z,           Z,           x"0", Z,           '0', '0'),  --  85  bltu  x3,x2,80000170
        (x"80000170", x"00317463", x"80000178",  0, Z,           Z,           x"0", Z,           '0', '0'),  --  86  bgeu  x2,x3,80000178
        (x"80000178", x"0031F463", x"80000180",  0, Z,           Z,           x"0", Z,           '0', '0'),  --  87  bgeu  x3,x3,80000180
        (x"80000180", x"00300593", x"80000184", 11, x"00000003", Z,           x"0", Z,           '0', '0'),  --  88  addi  x11,x0,3
        (x"80000184", x"FFF58593", x"80000188", 11, x"00000002", Z,           x"0", Z,           '0', '0'),  --  89  addi  x11,x11,-1
        (x"80000188", x"FE059EE3", x"80000184",  0, Z,           Z,           x"0", Z,           '0', '0'),  --  90  bne   x11,x0,80000184 <loop>
        (x"80000184", x"FFF58593", x"80000188", 11, x"00000001", Z,           x"0", Z,           '0', '0'),  --  91  addi  x11,x11,-1
        (x"80000188", x"FE059EE3", x"80000184",  0, Z,           Z,           x"0", Z,           '0', '0'),  --  92  bne   x11,x0,80000184 <loop>
        (x"80000184", x"FFF58593", x"80000188", 11, x"00000000", Z,           x"0", Z,           '0', '0'),  --  93  addi  x11,x11,-1
        (x"80000188", x"FE059EE3", x"8000018C",  0, Z,           Z,           x"0", Z,           '0', '0'),  --  94  bne   x11,x0,80000184 <loop>
        (x"8000018C", x"00C0006F", x"80000198",  0, Z,           Z,           x"0", Z,           '0', '0'),  --  95  jal   x0,80000198 <forward>
        (x"80000198", x"00A00613", x"8000019C", 12, x"0000000A", Z,           x"0", Z,           '0', '0'),  --  96  addi  x12,x0,10
        (x"8000019C", x"FF5FF0EF", x"80000190",  1, x"800001A0", Z,           x"0", Z,           '0', '0'),  --  97  jal   x1,80000190 <func>
        (x"80000190", x"00160613", x"80000194", 12, x"0000000B", Z,           x"0", Z,           '0', '0'),  --  98  addi  x12,x12,1
        (x"80000194", x"00008067", x"800001A0",  0, Z,           Z,           x"0", Z,           '0', '0'),  --  99  jalr  x0,0(x1)
        (x"800001A0", x"00000697", x"800001A4", 13, x"800001A0", Z,           x"0", Z,           '0', '0'),  -- 100  auipc x13,0x0
        (x"800001A4", x"00D686E7", x"800001AC", 13, x"800001A8", Z,           x"0", Z,           '0', '0'),  -- 101  jalr  x13,13(x13)
        (x"800001AC", x"00000717", x"800001B0", 14, x"800001AC", Z,           x"0", Z,           '0', '0'),  -- 102  auipc x14,0x0
        (x"800001B0", x"01470713", x"800001B4", 14, x"800001C0", Z,           x"0", Z,           '0', '0'),  -- 103  addi  x14,x14,20
        (x"800001B4", x"FFC707E7", x"800001BC", 15, x"800001B8", Z,           x"0", Z,           '0', '0'),  -- 104  jalr  x15,-4(x14)
        (x"800001BC", x"00000073", x"800001C0",  0, Z,           Z,           x"0", Z,           '0', '0'),  -- 105  ecall
        (x"800001C0", x"00100073", x"800001C4",  0, Z,           Z,           x"0", Z,           '0', '0')   -- 106  ebreak
    );

    -- The data words the program leaves behind. Every other word of the RAM
    -- above the program must still be zero at the end.
    type data_word_t is record
        index : natural;  -- of the word in the RAM
        value : word_t;
    end record;

    type data_array_t is array (natural range <>) of data_word_t;

    constant DATA : data_array_t := (
        (256, x"E1A27384"),  -- 80000400
        (258, x"11223384"),  -- 80000408
        (259, x"11228444"),  -- 8000040c
        (260, x"11843344"),  -- 80000410
        (261, x"84223344"),  -- 80000414
        (262, x"11227384"),  -- 80000418
        (263, x"73843344"),  -- 8000041c
        (270, x"05000000"),  -- 80000438
        (271, x"12345678")   -- 8000043c
    );

    ---------------------------------------------------------------------------
    -- Part 2: the cases of tests/data/core_traps.S, one program of four words
    -- in each line. Words 0 and 1 set x1 = 0x80000100. Word 2 is addi x2, x0, -1
    -- or a branch that is not taken. Word 3 must trap.
    ---------------------------------------------------------------------------
    subtype case_words_t is word_array_t(0 to 3);

    type case_array_t is array (natural range <>) of case_words_t;

    constant TRAP_CASES : case_array_t := (
        (x"800000B7", x"10008093", x"FFF00113", x"00109183"),  --  0  lh x3,1(x1)
        (x"800000B7", x"10008093", x"FFF00113", x"00309183"),  --  1  lh x3,3(x1)
        (x"800000B7", x"10008093", x"FFF00113", x"0010D183"),  --  2  lhu x3,1(x1)
        (x"800000B7", x"10008093", x"FFF00113", x"0030D183"),  --  3  lhu x3,3(x1)
        (x"800000B7", x"10008093", x"FFF00113", x"0010A183"),  --  4  lw x3,1(x1)
        (x"800000B7", x"10008093", x"FFF00113", x"0020A183"),  --  5  lw x3,2(x1)
        (x"800000B7", x"10008093", x"FFF00113", x"0030A183"),  --  6  lw x3,3(x1)
        (x"800000B7", x"10008093", x"FFF00113", x"002090A3"),  --  7  sh x2,1(x1)
        (x"800000B7", x"10008093", x"FFF00113", x"002091A3"),  --  8  sh x2,3(x1)
        (x"800000B7", x"10008093", x"FFF00113", x"0020A0A3"),  --  9  sw x2,1(x1)
        (x"800000B7", x"10008093", x"FFF00113", x"0020A123"),  -- 10  sw x2,2(x1)
        (x"800000B7", x"10008093", x"FFF00113", x"0020A1A3"),  -- 11  sw x2,3(x1)
        (x"800000B7", x"10008093", x"FFF00113", x"002001EF"),  -- 12  jal x3,. + 2
        (x"800000B7", x"10008093", x"FFF00113", x"002081E7"),  -- 13  jalr x3,2(x1)
        (x"800000B7", x"10008093", x"FFF00113", x"FFF081E7"),  -- 14  jalr x3,-1(x1)
        (x"800000B7", x"10008093", x"00008163", x"00000163"),  -- 15  beq x1,x0,. + 2 (not taken), then beq x0,x0,. + 2
        (x"800000B7", x"10008093", x"00001163", x"00009163"),  -- 16  bne x0,x0,. + 2 (not taken), then bne x1,x0,. + 2
        (x"800000B7", x"10008093", x"00104163", x"0000C163"),  -- 17  blt x0,x1,. + 2 (not taken), then blt x1,x0,. + 2
        (x"800000B7", x"10008093", x"0000D163", x"00105163"),  -- 18  bge x1,x0,. + 2 (not taken), then bge x0,x1,. + 2
        (x"800000B7", x"10008093", x"0000E163", x"00106163"),  -- 19  bltu x1,x0,. + 2 (not taken), then bltu x0,x1,. + 2
        (x"800000B7", x"10008093", x"00107163", x"0000F163")   -- 20  bgeu x0,x1,. + 2 (not taken), then bgeu x1,x0,. + 2
    );

    constant ADDI_X2_M1 : word_t := x"FFF00113";  -- word 2 when it is not a branch

    -- Clock cycles one instruction takes: fetch, S_EXEC, S_MEM for a load or a
    -- store, S_WB. A read takes READ_LATENCY + 1 cycles, a write one.
    function cycles_of(r : retire_t) return natural is
        variable n : natural := (READ_LATENCY + 1) + 1 + 1;
    begin
        if r.is_load = '1' then
            n := n + READ_LATENCY + 1;
        elsif r.is_store = '1' then
            n := n + 1;
        end if;
        return n;
    end function;

    -- From the retire before a trap to trap = '1': fetch, S_EXEC, and one more
    -- edge for the state to be S_TRAP.
    constant TRAP_CYCLES : natural := (READ_LATENCY + 1) + 1 + 1;

    -- The RAM at the start of a program: the part 1 program for which = -1,
    -- the four words of TRAP_CASES(which) otherwise, and zeros above.
    function image_of(which : integer) return word_array_t is
        variable r : word_array_t(0 to RAM_WORDS - 1) := (others => (others => '0'));
    begin
        if which < 0 then
            for i in PROGRAM'range loop
                r(i) := PROGRAM(i);
            end loop;
        else
            for i in case_words_t'range loop
                r(i) := TRAP_CASES(which)(i);
            end loop;
        end if;
        return r;
    end function;

    signal clk  : std_logic := '0';
    signal rstn : std_logic := '0';
    signal run  : std_logic := '0';

    signal mem_en    : std_logic;
    signal mem_we    : std_logic;
    signal mem_addr  : word_t;
    signal mem_be    : std_logic_vector(3 downto 0);
    signal mem_wdata : word_t;
    signal mem_rdata : word_t;

    signal retire_valid     : std_logic;
    signal retire_pc        : word_t;
    signal retire_insn      : word_t;
    signal retire_next_pc   : word_t;
    signal retire_rd        : reg_addr_t;
    signal retire_rd_wdata  : word_t;
    signal retire_mem_addr  : word_t;
    signal retire_mem_mask  : std_logic_vector(3 downto 0);
    signal retire_mem_wdata : word_t;
    signal retire_is_load   : std_logic;
    signal retire_is_store  : std_logic;
    signal trap             : std_logic;

    -- Which program the RAM takes while the core is in reset (see image_of).
    signal selected : integer := -1;

    signal ram : word_array_t(0 to RAM_WORDS - 1) := image_of(-1);

    -- Memory accesses and writes since the last reset.
    signal accesses : natural := 0;
    signal writes   : natural := 0;

    -- The read data on its way out: read_pipe(READ_LATENCY) is mem_rdata.
    signal read_pipe : word_array_t(1 to READ_LATENCY) := (others => (others => 'X'));

begin

    clk <= not clk after CLK_PERIOD / 2;

    dut : entity work.rv_core
        generic map (
            RESET_PC     => RAM_BASE,
            READ_LATENCY => READ_LATENCY
        )
        port map (
            clk              => clk,
            rstn             => rstn,
            run              => run,
            mem_en           => mem_en,
            mem_we           => mem_we,
            mem_addr         => mem_addr,
            mem_be           => mem_be,
            mem_wdata        => mem_wdata,
            mem_rdata        => mem_rdata,
            retire_valid     => retire_valid,
            retire_pc        => retire_pc,
            retire_insn      => retire_insn,
            retire_next_pc   => retire_next_pc,
            retire_rd        => retire_rd,
            retire_rd_wdata  => retire_rd_wdata,
            retire_mem_addr  => retire_mem_addr,
            retire_mem_mask  => retire_mem_mask,
            retire_mem_wdata => retire_mem_wdata,
            retire_is_load   => retire_is_load,
            retire_is_store  => retire_is_store,
            trap             => trap
        );

    -- The RAM, the same model as in tb_rv_core: the word read is on mem_rdata for
    -- one cycle only, READ_LATENCY edges after the access, and mem_rdata is 'X'
    -- at every other time. It also checks how the core drives the port, and it
    -- counts the accesses. While the core is in reset, the RAM is filled with
    -- the selected program and the counts go back to zero.
    ram_model : process (clk)
        variable index : natural range 0 to RAM_WORDS - 1;
    begin
        if rising_edge(clk) then
            for i in READ_LATENCY downto 2 loop
                read_pipe(i) <= read_pipe(i - 1);
            end loop;
            read_pipe(1) <= (others => 'X');

            if rstn = '0' then
                assert mem_en = '0'
                    report "memory port: an access while the core is in reset"
                    severity failure;
                ram      <= image_of(selected);
                accesses <= 0;
                writes   <= 0;

            elsif mem_en = '1' then
                assert mem_addr(31 downto 11) = RAM_BASE(31 downto 11)
                    report "memory port: address " & to_hstring(mem_addr) & " is outside the RAM"
                    severity failure;
                assert mem_addr(1 downto 0) = "00"
                    report "memory port: address " & to_hstring(mem_addr) & " is not a word address"
                    severity failure;

                accesses <= accesses + 1;
                index    := to_integer(unsigned(mem_addr(10 downto 2)));
                if mem_we = '1' then
                    writes <= writes + 1;
                    for lane in 0 to 3 loop
                        if mem_be(lane) = '1' then
                            ram(index)(8 * lane + 7 downto 8 * lane) <=
                                mem_wdata(8 * lane + 7 downto 8 * lane);
                        end if;
                    end loop;
                else
                    assert mem_be = "0000"
                        report "memory port: mem_be is " & to_hstring(mem_be) & " on a read"
                        severity failure;
                    read_pipe(1) <= ram(index);
                end if;
            end if;
        end if;
    end process ram_model;

    mem_rdata <= read_pipe(READ_LATENCY);

    stimulus : process

        variable checks : natural := 0;
        variable cycles : natural;

        -- "what" says where the check is, for the message: "retire 12", or
        -- "trap case 3, retire 1".

        procedure check_word(what : string; field : string; got : word_t; want : word_t) is
        begin
            assert got = want
                report what & ": " & field & " is " & to_hstring(got) &
                       ", expected " & to_hstring(want)
                severity failure;
            checks := checks + 1;
        end procedure;

        procedure check_bit(what : string; field : string; got : std_logic; want : std_logic) is
        begin
            assert got = want
                report what & ": " & field & " is " & std_logic'image(got) &
                       ", expected " & std_logic'image(want)
                severity failure;
            checks := checks + 1;
        end procedure;

        procedure check_count(what : string; field : string; got : natural; want : natural) is
        begin
            assert got = want
                report what & ": " & field & " is " & integer'image(got) &
                       ", expected " & integer'image(want)
                severity failure;
            checks := checks + 1;
        end procedure;

        -- Puts the core in reset for one clock edge, with the RAM taking the
        -- program "which" (see image_of), and lets it run.
        procedure start_program(which : integer) is
        begin
            wait until falling_edge(clk);
            selected <= which;
            rstn     <= '0';
            run      <= '1';
            wait until falling_edge(clk);
            rstn     <= '1';
        end procedure;

        -- Waits for the next retire and compares it with e. With timed, the
        -- retire must come exactly cycles_of clock cycles after the one before.
        procedure expect_retire(what : string; e : retire_t; timed : boolean) is
            variable n : natural := 0;
        begin
            loop
                wait until rising_edge(clk);
                n := n + 1;
                exit when retire_valid = '1';
                assert trap = '0'
                    report what & ": the core trapped instead"
                    severity failure;
                assert n < 50
                    report what & ": nothing retired in 50 cycles"
                    severity failure;
            end loop;

            check_word(what, "pc", retire_pc, e.pc);
            check_word(what, "insn", retire_insn, e.insn);
            check_word(what, "next_pc", retire_next_pc, e.next_pc);
            check_count(what, "rd", to_integer(unsigned(retire_rd)), e.rd);
            check_word(what, "rd_wdata", retire_rd_wdata, e.rd_wdata);
            check_word(what, "mem_addr", retire_mem_addr, e.mem_addr);
            assert retire_mem_mask = e.mem_mask
                report what & ": mem_mask is " & to_hstring(retire_mem_mask) &
                       ", expected " & to_hstring(e.mem_mask)
                severity failure;
            checks := checks + 1;
            check_word(what, "mem_wdata", retire_mem_wdata, e.mem_wdata);
            check_bit(what, "is_load", retire_is_load, e.is_load);
            check_bit(what, "is_store", retire_is_store, e.is_store);
            check_bit(what, "trap", trap, '0');

            if timed then
                check_count(what, "the number of cycles", n, cycles_of(e));
            end if;
        end procedure;

        -- The instruction after the last retire must trap: nothing retires,
        -- trap comes after TRAP_CYCLES clock cycles with the pc and the word of
        -- that instruction, and the core then stays stopped.
        procedure expect_trap(what : string; pc : word_t; insn : word_t) is
            variable n : natural := 0;
        begin
            loop
                wait until rising_edge(clk);
                n := n + 1;
                assert retire_valid = '0'
                    report what & ": the instruction retired instead of trapping"
                    severity failure;
                exit when trap = '1';
                assert n < 50
                    report what & ": no trap in 50 cycles"
                    severity failure;
            end loop;
            check_word(what, "pc of the trap", retire_pc, pc);
            check_word(what, "insn of the trap", retire_insn, insn);
            check_count(what, "the number of cycles to the trap", n, TRAP_CYCLES);

            for i in 1 to 5 loop
                wait until rising_edge(clk);
                assert mem_en = '0'
                    report what & ": a memory access after the trap" severity failure;
                assert retire_valid = '0'
                    report what & ": an instruction retired after the trap" severity failure;
                assert trap = '1'
                    report what & ": trap went low without a reset" severity failure;
                checks := checks + 3;
            end loop;
        end procedure;

        -- Part 2, one case.
        procedure run_trap_case(c : natural) is
            constant words : case_words_t := TRAP_CASES(c);
            constant name  : string       := "trap case " & integer'image(c);
            variable e     : retire_t;
            variable pc    : word_t;
        begin
            start_program(c);

            for i in 0 to 2 loop
                pc := std_logic_vector(unsigned(RAM_BASE) + 4 * i);
                e  := (pc        => pc,
                       insn      => words(i),
                       next_pc   => std_logic_vector(unsigned(pc) + 4),
                       rd        => 0,
                       rd_wdata  => Z,
                       mem_addr  => Z,
                       mem_mask  => x"0",
                       mem_wdata => Z,
                       is_load   => '0',
                       is_store  => '0');
                if i = 0 then                      -- lui x1, 0x80000
                    e.rd       := 1;
                    e.rd_wdata := x"80000000";
                elsif i = 1 then                   -- addi x1, x1, 0x100
                    e.rd       := 1;
                    e.rd_wdata := x"80000100";
                elsif words(2) = ADDI_X2_M1 then   -- addi x2, x0, -1
                    e.rd       := 2;
                    e.rd_wdata := x"FFFFFFFF";
                end if;                            -- else a branch, not taken
                expect_retire(name & ", retire " & integer'image(i), e, i > 0);
            end loop;

            expect_trap(name, std_logic_vector(unsigned(RAM_BASE) + 12), words(3));

            -- Four fetches and nothing else: the access that would have been
            -- misaligned was never made.
            check_count(name, "the number of memory accesses", accesses, 4);
            check_count(name, "the number of memory writes", writes, 0);
        end procedure;

        variable want : word_t;

    begin
        -----------------------------------------------------------------------
        -- Part 1
        -----------------------------------------------------------------------
        start_program(-1);

        expect_retire("retire 0", EXPECTED(0), false);
        for i in 1 to EXPECTED'high loop
            expect_retire("retire " & integer'image(i), EXPECTED(i), true);
        end loop;

        expect_trap("the illegal word at the end", STOP_PC, STOP_INSN);

        -- Every word of the RAM: the program unchanged, the data as the stores
        -- left it, zero everywhere else.
        for i in ram'range loop
            want := (others => '0');
            if i <= PROGRAM'high then
                want := PROGRAM(i);
            end if;
            for k in DATA'range loop
                if DATA(k).index = i then
                    want := DATA(k).value;
                end if;
            end loop;
            check_word("RAM word " & integer'image(i), "the value", ram(i), want);
        end loop;

        -----------------------------------------------------------------------
        -- Part 2
        -----------------------------------------------------------------------
        for c in TRAP_CASES'range loop
            run_trap_case(c);
        end loop;

        report "tb_rv_core_insns: PASS (" & integer'image(EXPECTED'length) & " retires, " &
               integer'image(TRAP_CASES'length) & " trap cases, " &
               integer'image(checks) & " checks)";
        std.env.finish;
    end process stimulus;

end architecture sim;
