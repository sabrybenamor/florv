-- Self-checking testbench for decode. Run it with:  tools\sim.bat tb_decode
-- The legal words and their register numbers are those of
-- tests/unit/test_decoder.cpp. The illegal words are legal ones with one field
-- changed, plus the all-zero and all-ones words.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.rv32i_pkg.all;
use work.decode_pkg.all;

entity tb_decode is
end entity tb_decode;

architecture sim of tb_decode is

    signal insn : word_t := (others => '0');
    signal d    : decoded_t;

    -- The seven flags of decoded_t in one vector:
    -- reg_write, is_load, is_store, is_branch, is_jump, is_halt, illegal.
    subtype kind_t is std_logic_vector(6 downto 0);
    constant K_NONE    : kind_t := "0000000";
    constant K_WRITE   : kind_t := "1000000";
    constant K_LOAD    : kind_t := "1100000";
    constant K_STORE   : kind_t := "0010000";
    constant K_BRANCH  : kind_t := "0001000";
    constant K_JUMP    : kind_t := "1000100";
    constant K_HALT    : kind_t := "0000010";
    constant K_ILLEGAL : kind_t := "0000001";

    type vector_t is record
        insn   : word_t;
        rd     : natural range 0 to 31;
        rs1    : natural range 0 to 31;
        rs2    : natural range 0 to 31;
        funct3 : funct3_t;
        alu_op : alu_op_t;
        a_sel  : a_sel_t;
        b_sel  : b_sel_t;
        wb_sel : wb_sel_t;
        kind   : kind_t;
    end record;

    type vector_array_t is array (natural range <>) of vector_t;

    constant VECTORS : vector_array_t := (
        -- The 37 instructions of tests/unit/test_decoder.cpp, in its order
        (x"123452B7",  5,  0,  0, "000", ALU_ADD,  A_ZERO, B_IMM, WB_ALU, K_WRITE),  -- lui x5,0x12345
        (x"ABCDE897", 17,  0,  0, "000", ALU_ADD,  A_PC,   B_IMM, WB_ALU, K_WRITE),  -- auipc x17,0xabcde
        (x"08C000EF",  1,  0,  0, "000", ALU_ADD,  A_PC,   B_IMM, WB_PC4, K_JUMP),  -- jal x1,80000094
        (x"123A04E7",  9, 20,  0, "000", ALU_ADD,  A_RS1,  B_IMM, WB_PC4, K_JUMP),  -- jalr x9,291(x20)
        (x"FF5308E3",  0,  6, 21, "000", ALU_SUB,  A_RS1,  B_RS2, WB_ALU, K_BRANCH),  -- beq x6,x21,80000000
        (x"087B1063",  0, 22,  7, "001", ALU_SUB,  A_RS1,  B_RS2, WB_ALU, K_BRANCH),  -- bne x22,x7,80000094
        (x"FF7444E3",  0,  8, 23, "100", ALU_SLT,  A_RS1,  B_RS2, WB_ALU, K_BRANCH),  -- blt x8,x23,80000000
        (x"06AC5C63",  0, 24, 10, "101", ALU_SLT,  A_RS1,  B_RS2, WB_ALU, K_BRANCH),  -- bge x24,x10,80000094
        (x"FF95E0E3",  0, 11, 25, "110", ALU_SLTU, A_RS1,  B_RS2, WB_ALU, K_BRANCH),  -- bltu x11,x25,80000000
        (x"06CD7863",  0, 26, 12, "111", ALU_SLTU, A_RS1,  B_RS2, WB_ALU, K_BRANCH),  -- bgeu x26,x12,80000094
        (x"EDDD8683", 13, 27,  0, "000", ALU_ADD,  A_RS1,  B_IMM, WB_MEM, K_LOAD),  -- lb x13,-291(x27)
        (x"45671E03", 28, 14,  0, "001", ALU_ADD,  A_RS1,  B_IMM, WB_MEM, K_LOAD),  -- lh x28,1110(x14)
        (x"BAAEA783", 15, 29,  0, "010", ALU_ADD,  A_RS1,  B_IMM, WB_MEM, K_LOAD),  -- lw x15,-1110(x29)
        (x"04D84F03", 30, 16,  0, "100", ALU_ADD,  A_RS1,  B_IMM, WB_MEM, K_LOAD),  -- lbu x30,77(x16)
        (x"FB3FD883", 17, 31,  0, "101", ALU_ADD,  A_RS1,  B_IMM, WB_MEM, K_LOAD),  -- lhu x17,-77(x31)
        (x"132181A3",  0,  3, 18, "000", ALU_ADD,  A_RS1,  B_IMM, WB_ALU, K_STORE),  -- sb x18,291(x3)
        (x"EC499EA3",  0, 19,  4, "001", ALU_ADD,  A_RS1,  B_IMM, WB_ALU, K_STORE),  -- sh x4,-291(x19)
        (x"4542AB23",  0,  5, 20, "010", ALU_ADD,  A_RS1,  B_IMM, WB_ALU, K_STORE),  -- sw x20,1110(x5)
        (x"B2EA8313",  6, 21,  0, "000", ALU_ADD,  A_RS1,  B_IMM, WB_ALU, K_WRITE),  -- addi x6,x21,-1234
        (x"4D23AB13", 22,  7,  0, "000", ALU_SLT,  A_RS1,  B_IMM, WB_ALU, K_WRITE),  -- slti x22,x7,1234
        (x"DC9BB413",  8, 23,  0, "000", ALU_SLTU, A_RS1,  B_IMM, WB_ALU, K_WRITE),  -- sltiu x8,x23,-567
        (x"2374CC13", 24,  9,  0, "000", ALU_XOR,  A_RS1,  B_IMM, WB_ALU, K_WRITE),  -- xori x24,x9,567
        (x"FA7CE513", 10, 25,  0, "000", ALU_OR,   A_RS1,  B_IMM, WB_ALU, K_WRITE),  -- ori x10,x25,-89
        (x"0595FD13", 26, 11,  0, "000", ALU_AND,  A_RS1,  B_IMM, WB_ALU, K_WRITE),  -- andi x26,x11,89
        (x"013D9613", 12, 27,  0, "000", ALU_SLL,  A_RS1,  B_IMM, WB_ALU, K_WRITE),  -- slli x12,x27,0x13
        (x"00D6DE13", 28, 13,  0, "000", ALU_SRL,  A_RS1,  B_IMM, WB_ALU, K_WRITE),  -- srli x28,x13,0xd
        (x"41BED713", 14, 29,  0, "000", ALU_SRA,  A_RS1,  B_IMM, WB_ALU, K_WRITE),  -- srai x14,x29,0x1b
        (x"01078F33", 30, 15, 16, "000", ALU_ADD,  A_RS1,  B_RS2, WB_ALU, K_WRITE),  -- add x30,x15,x16
        (x"402F88B3", 17, 31,  2, "000", ALU_SUB,  A_RS1,  B_RS2, WB_ALU, K_WRITE),  -- sub x17,x31,x2
        (x"013911B3",  3, 18, 19, "000", ALU_SLL,  A_RS1,  B_RS2, WB_ALU, K_WRITE),  -- sll x3,x18,x19
        (x"00522A33", 20,  4,  5, "000", ALU_SLT,  A_RS1,  B_RS2, WB_ALU, K_WRITE),  -- slt x20,x4,x5
        (x"016AB333",  6, 21, 22, "000", ALU_SLTU, A_RS1,  B_RS2, WB_ALU, K_WRITE),  -- sltu x6,x21,x22
        (x"0083CBB3", 23,  7,  8, "000", ALU_XOR,  A_RS1,  B_RS2, WB_ALU, K_WRITE),  -- xor x23,x7,x8
        (x"019C54B3",  9, 24, 25, "000", ALU_SRL,  A_RS1,  B_RS2, WB_ALU, K_WRITE),  -- srl x9,x24,x25
        (x"40B55D33", 26, 10, 11, "000", ALU_SRA,  A_RS1,  B_RS2, WB_ALU, K_WRITE),  -- sra x26,x10,x11
        (x"01CDE633", 12, 27, 28, "000", ALU_OR,   A_RS1,  B_RS2, WB_ALU, K_WRITE),  -- or x12,x27,x28
        (x"00E6FEB3", 29, 13, 14, "000", ALU_AND,  A_RS1,  B_RS2, WB_ALU, K_WRITE),  -- and x29,x13,x14

        -- Bit 30 set in an op-imm immediate: still add, never sub. The first has exactly sub's funct7
        (x"40020193",  3,  4,  0, "000", ALU_ADD,  A_RS1,  B_IMM, WB_ALU, K_WRITE),  -- addi x3,x4,1024
        (x"7FF20193",  3,  4,  0, "000", ALU_ADD,  A_RS1,  B_IMM, WB_ALU, K_WRITE),  -- addi x3,x4,2047
        (x"FFF10093",  1,  2,  0, "000", ALU_ADD,  A_RS1,  B_IMM, WB_ALU, K_WRITE),  -- addi x1,x2,-1

        -- A destination of x0 is still a destination; the register file drops the write
        (x"F6DFF06F",  0,  0,  0, "000", ALU_ADD,  A_PC,   B_IMM, WB_PC4, K_JUMP),  -- jal x0,80000000

        -- No register, no memory, no jump
        (x"0FF0000F",  0,  0,  0, "000", ALU_ADD,  A_RS1,  B_RS2, WB_ALU, K_NONE),  -- fence iorw,iorw
        (x"00000073",  0,  0,  0, "000", ALU_ADD,  A_RS1,  B_RS2, WB_ALU, K_HALT),  -- ecall
        (x"00100073",  0,  0,  0, "000", ALU_ADD,  A_RS1,  B_RS2, WB_ALU, K_HALT),  -- ebreak

        -- Illegal: nothing is set but the flag
        (x"00000000",  0,  0,  0, "000", ALU_ADD,  A_RS1,  B_RS2, WB_ALU, K_ILLEGAL),  -- all zeros
        (x"FFFFFFFF",  0,  0,  0, "000", ALU_ADD,  A_RS1,  B_RS2, WB_ALU, K_ILLEGAL),  -- all ones
        (x"0000007F",  0,  0,  0, "000", ALU_ADD,  A_RS1,  B_RS2, WB_ALU, K_ILLEGAL),  -- unknown opcode 1111111
        (x"01078F32",  0,  0,  0, "000", ALU_ADD,  A_RS1,  B_RS2, WB_ALU, K_ILLEGAL),  -- add with opcode bit 0 cleared
        (x"413D9613",  0,  0,  0, "000", ALU_ADD,  A_RS1,  B_RS2, WB_ALU, K_ILLEGAL),  -- slli with funct7 0100000
        (x"02D6DE13",  0,  0,  0, "000", ALU_ADD,  A_RS1,  B_RS2, WB_ALU, K_ILLEGAL),  -- srli with funct7 0000001
        (x"C1BED713",  0,  0,  0, "000", ALU_ADD,  A_RS1,  B_RS2, WB_ALU, K_ILLEGAL),  -- srai with funct7 1100000
        (x"03078F33",  0,  0,  0, "000", ALU_ADD,  A_RS1,  B_RS2, WB_ALU, K_ILLEGAL),  -- add with funct7 0000001 (mul)
        (x"4083CBB3",  0,  0,  0, "000", ALU_ADD,  A_RS1,  B_RS2, WB_ALU, K_ILLEGAL),  -- xor with funct7 0100000
        (x"413911B3",  0,  0,  0, "000", ALU_ADD,  A_RS1,  B_RS2, WB_ALU, K_ILLEGAL),  -- sll with funct7 0100000
        (x"FF5328E3",  0,  0,  0, "000", ALU_ADD,  A_RS1,  B_RS2, WB_ALU, K_ILLEGAL),  -- branch with funct3 010
        (x"FF5338E3",  0,  0,  0, "000", ALU_ADD,  A_RS1,  B_RS2, WB_ALU, K_ILLEGAL),  -- branch with funct3 011
        (x"EDDDB683",  0,  0,  0, "000", ALU_ADD,  A_RS1,  B_RS2, WB_ALU, K_ILLEGAL),  -- load with funct3 011
        (x"EDDDE683",  0,  0,  0, "000", ALU_ADD,  A_RS1,  B_RS2, WB_ALU, K_ILLEGAL),  -- load with funct3 110
        (x"EDDDF683",  0,  0,  0, "000", ALU_ADD,  A_RS1,  B_RS2, WB_ALU, K_ILLEGAL),  -- load with funct3 111
        (x"1321B1A3",  0,  0,  0, "000", ALU_ADD,  A_RS1,  B_RS2, WB_ALU, K_ILLEGAL),  -- store with funct3 011
        (x"1321C1A3",  0,  0,  0, "000", ALU_ADD,  A_RS1,  B_RS2, WB_ALU, K_ILLEGAL),  -- store with funct3 100
        (x"123A14E7",  0,  0,  0, "000", ALU_ADD,  A_RS1,  B_RS2, WB_ALU, K_ILLEGAL),  -- jalr with funct3 001
        (x"0FF0100F",  0,  0,  0, "000", ALU_ADD,  A_RS1,  B_RS2, WB_ALU, K_ILLEGAL),  -- misc-mem with funct3 001 (fence.i)
        (x"00200073",  0,  0,  0, "000", ALU_ADD,  A_RS1,  B_RS2, WB_ALU, K_ILLEGAL),  -- system with immediate 2
        (x"000000F3",  0,  0,  0, "000", ALU_ADD,  A_RS1,  B_RS2, WB_ALU, K_ILLEGAL),  -- ecall with rd 1
        (x"00001073",  0,  0,  0, "000", ALU_ADD,  A_RS1,  B_RS2, WB_ALU, K_ILLEGAL)   -- system with funct3 001 (csrrw)
    );

begin

    dut : entity work.decode
        port map (
            insn => insn,
            d    => d
        );

    stimulus : process
        variable v    : vector_t;
        variable kind : kind_t;

        -- Stops the run, naming the vector, its word and the field that is wrong.
        procedure check (ok : boolean; index : natural; field : string; got : string) is
        begin
            assert ok
                report "vector " & integer'image(index) &
                       ": insn=" & to_hstring(VECTORS(index).insn) &
                       " " & field & " is " & got
                severity failure;
        end procedure check;
    begin
        for i in VECTORS'range loop
            v    := VECTORS(i);
            insn <= v.insn;
            wait for 1 ns;

            kind := d.reg_write & d.is_load & d.is_store & d.is_branch &
                    d.is_jump & d.is_halt & d.illegal;

            check(kind = v.kind, i, "flags (write load store branch jump halt illegal)", to_string(kind));
            check(to_integer(unsigned(d.rd)) = v.rd, i, "rd", integer'image(to_integer(unsigned(d.rd))));
            check(to_integer(unsigned(d.rs1)) = v.rs1, i, "rs1", integer'image(to_integer(unsigned(d.rs1))));
            check(to_integer(unsigned(d.rs2)) = v.rs2, i, "rs2", integer'image(to_integer(unsigned(d.rs2))));
            check(d.funct3 = v.funct3, i, "funct3", to_string(d.funct3));
            check(d.alu_op = v.alu_op, i, "alu_op", alu_op_t'image(d.alu_op));
            check(d.a_sel = v.a_sel, i, "a_sel", a_sel_t'image(d.a_sel));
            check(d.b_sel = v.b_sel, i, "b_sel", b_sel_t'image(d.b_sel));
            check(d.wb_sel = v.wb_sel, i, "wb_sel", wb_sel_t'image(d.wb_sel));
        end loop;

        report "tb_decode: PASS (" & integer'image(VECTORS'length) & " vectors)";
        std.env.finish;
    end process stimulus;

end architecture sim;
