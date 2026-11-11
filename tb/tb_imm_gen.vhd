-- Self-checking testbench for imm_gen. Run it with:  tools\sim.bat tb_imm_gen
-- The words and the expected immediates are those of tests/unit/test_decoder.cpp:
-- the 37-instruction table and the cases around it (negative immediates, the ends
-- of the 12-bit range, far jumps).

library ieee;
use ieee.std_logic_1164.all;

use work.rv32i_pkg.all;

entity tb_imm_gen is
end entity tb_imm_gen;

architecture sim of tb_imm_gen is

    signal insn : word_t := (others => '0');
    signal imm  : word_t;

    type vector_t is record
        insn     : word_t;
        expected : word_t;
    end record;

    type vector_array_t is array (natural range <>) of vector_t;

    constant VECTORS : vector_array_t := (
        -- U: lui, auipc. The value is already shifted left by 12
        (x"123452B7", x"12345000"),  -- lui x5,0x12345
        (x"ABCDE897", x"ABCDE000"),  -- auipc x17,0xabcde
        (x"80000937", x"80000000"),  -- lui x18,0x80000
        (x"FFFFF997", x"FFFFF000"),  -- auipc x19,0xfffff
        (x"123450B7", x"12345000"),  -- lui x1,0x12345

        -- J: jal, forward and backward, near and far enough to use imm[19:12]
        (x"08C000EF", x"0000008C"),  -- 80000008: jal x1,80000094
        (x"F6DFF06F", x"FFFFFF6C"),  -- 80000094: jal x0,80000000
        (x"FD5FF0EF", x"FFFFFFD4"),  -- 8000002c: jal x1,80000000
        (x"FD1FE06F", x"FFFFEFD0"),  -- 80000030: jal x0,7ffff000
        (x"3C1000EF", x"00000BC0"),  -- 8000005c: jal x1,80000c1c

        -- I: jalr
        (x"123A04E7", x"00000123"),  -- jalr x9,291(x20)
        (x"FF4480E7", x"FFFFFFF4"),  -- jalr x1,-12(x9)

        -- B: the six branches, forward and backward
        (x"FF5308E3", x"FFFFFFF0"),  -- 80000010: beq x6,x21,80000000
        (x"087B1063", x"00000080"),  -- 80000014: bne x22,x7,80000094
        (x"FF7444E3", x"FFFFFFE8"),  -- 80000018: blt x8,x23,80000000
        (x"06AC5C63", x"00000078"),  -- 8000001c: bge x24,x10,80000094
        (x"FF95E0E3", x"FFFFFFE0"),  -- 80000020: bltu x11,x25,80000000
        (x"06CD7863", x"00000070"),  -- 80000024: bgeu x26,x12,80000094
        (x"FEF704E3", x"FFFFFFE8"),  -- 80000018: beq x14,x15,80000000
        (x"3C2082E3", x"00000BC4"),  -- 80000058: beq x1,x2,80000c1c

        -- I: the five loads
        (x"EDDD8683", x"FFFFFEDD"),  -- lb x13,-291(x27)
        (x"45671E03", x"00000456"),  -- lh x28,1110(x14)
        (x"BAAEA783", x"FFFFFBAA"),  -- lw x15,-1110(x29)
        (x"04D84F03", x"0000004D"),  -- lbu x30,77(x16)
        (x"FB3FD883", x"FFFFFFB3"),  -- lhu x17,-77(x31)
        (x"FFC42383", x"FFFFFFFC"),  -- lw x7,-4(x8)

        -- S: the three stores, and the two ends of the 12-bit range
        (x"132181A3", x"00000123"),  -- sb x18,291(x3)
        (x"EC499EA3", x"FFFFFEDD"),  -- sh x4,-291(x19)
        (x"4542AB23", x"00000456"),  -- sw x20,1110(x5)
        (x"FEA5AC23", x"FFFFFFF8"),  -- sw x10,-8(x11)
        (x"80C68023", x"FFFFF800"),  -- sb x12,-2048(x13)
        (x"7E532FA3", x"000007FF"),  -- sw x5,2047(x6)

        -- I: op-imm, and the two ends of the 12-bit range
        (x"B2EA8313", x"FFFFFB2E"),  -- addi x6,x21,-1234
        (x"4D23AB13", x"000004D2"),  -- slti x22,x7,1234
        (x"DC9BB413", x"FFFFFDC9"),  -- sltiu x8,x23,-567
        (x"2374CC13", x"00000237"),  -- xori x24,x9,567
        (x"FA7CE513", x"FFFFFFA7"),  -- ori x10,x25,-89
        (x"0595FD13", x"00000059"),  -- andi x26,x11,89
        (x"FFF10093", x"FFFFFFFF"),  -- addi x1,x2,-1
        (x"80030293", x"FFFFF800"),  -- addi x5,x6,-2048
        (x"7FF20193", x"000007FF"),  -- addi x3,x4,2047

        -- shifts by a constant: the shift amount alone, without srai's bit 30
        (x"013D9613", x"00000013"),  -- slli x12,x27,0x13
        (x"00D6DE13", x"0000000D"),  -- srli x28,x13,0xd
        (x"41BED713", x"0000001B"),  -- srai x14,x29,0x1b
        (x"01FA9A13", x"0000001F"),  -- slli x20,x21,0x1f
        (x"405BDB13", x"00000005"),  -- srai x22,x23,0x5

        -- no immediate: register-register, fence, ecall, ebreak, unknown opcodes
        (x"01078F33", x"00000000"),  -- add x30,x15,x16
        (x"402F88B3", x"00000000"),  -- sub x17,x31,x2
        (x"013911B3", x"00000000"),  -- sll x3,x18,x19
        (x"00522A33", x"00000000"),  -- slt x20,x4,x5
        (x"016AB333", x"00000000"),  -- sltu x6,x21,x22
        (x"0083CBB3", x"00000000"),  -- xor x23,x7,x8
        (x"019C54B3", x"00000000"),  -- srl x9,x24,x25
        (x"40B55D33", x"00000000"),  -- sra x26,x10,x11
        (x"01CDE633", x"00000000"),  -- or x12,x27,x28
        (x"00E6FEB3", x"00000000"),  -- and x29,x13,x14
        (x"0FF0000F", x"00000000"),  -- fence iorw,iorw
        (x"00000073", x"00000000"),  -- ecall
        (x"00100073", x"00000000"),  -- ebreak
        (x"00000000", x"00000000"),  -- all zeros
        (x"FFFFFFFF", x"00000000")   -- all ones
    );

begin

    dut : entity work.imm_gen
        port map (
            insn => insn,
            imm  => imm
        );

    stimulus : process
    begin
        for i in VECTORS'range loop
            insn <= VECTORS(i).insn;
            wait for 1 ns;
            assert imm = VECTORS(i).expected
                report "vector " & integer'image(i) &
                       ": insn=" & to_hstring(VECTORS(i).insn) &
                       " gave " & to_hstring(imm) &
                       ", expected " & to_hstring(VECTORS(i).expected)
                severity failure;
        end loop;

        report "tb_imm_gen: PASS (" & integer'image(VECTORS'length) & " vectors)";
        std.env.finish;
    end process stimulus;

end architecture sim;
