-- Self-checking testbench for alu. Run it with:  tools\sim.bat tb_alu
-- The vectors are the operand values of kValueCases in tests/unit/test_iss.cpp.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.rv32i_pkg.all;

entity tb_alu is
end entity tb_alu;

architecture sim of tb_alu is

    signal op     : alu_op_t := ALU_ADD;
    signal a      : word_t   := (others => '0');
    signal b      : word_t   := (others => '0');
    signal result : word_t;

    type vector_t is record
        op       : alu_op_t;
        a        : word_t;
        b        : word_t;
        expected : word_t;
    end record;

    type vector_array_t is array (natural range <>) of vector_t;

    constant VECTORS : vector_array_t := (
        -- add: plain, wrap-around, a negative operand (addi 1000, -1234), zero
        (ALU_ADD,  x"00000003", x"00000005", x"00000008"),
        (ALU_ADD,  x"FFFFFFFF", x"00000002", x"00000001"),
        (ALU_ADD,  x"000003E8", x"FFFFFB2E", x"FFFFFF16"),
        (ALU_ADD,  x"7FFFFFFF", x"00000001", x"80000000"),
        (ALU_ADD,  x"00000000", x"00000000", x"00000000"),

        -- sub: negative result, plain, the order of the operands, equal operands
        (ALU_SUB,  x"00000003", x"00000005", x"FFFFFFFE"),
        (ALU_SUB,  x"00000005", x"00000003", x"00000002"),
        (ALU_SUB,  x"00000000", x"00000001", x"FFFFFFFF"),
        (ALU_SUB,  x"80000000", x"00000001", x"7FFFFFFF"),
        (ALU_SUB,  x"12345678", x"12345678", x"00000000"),

        -- and, or, xor: values on which the three give different results
        (ALU_AND,  x"000000FF", x"0000003C", x"0000003C"),
        (ALU_AND,  x"FFFFFFFF", x"00000059", x"00000059"),
        (ALU_AND,  x"FF00FF00", x"0FF00FF0", x"0F000F00"),
        (ALU_OR,   x"000000F0", x"0000000F", x"000000FF"),
        (ALU_OR,   x"00000012", x"FFFFFFA7", x"FFFFFFB7"),
        (ALU_OR,   x"FF00FF00", x"0FF00FF0", x"FFF0FFF0"),
        (ALU_XOR,  x"FF00FF00", x"0FF00FF0", x"F0F0F0F0"),
        (ALU_XOR,  x"FFFF0000", x"00000237", x"FFFF0237"),
        (ALU_XOR,  x"A5A5A5A5", x"A5A5A5A5", x"00000000"),

        -- sll: only the low five bits of b count, so 32 is 0 and 33 is 1
        (ALU_SLL,  x"00000001", x"0000001F", x"80000000"),
        (ALU_SLL,  x"00000001", x"00000000", x"00000001"),
        (ALU_SLL,  x"00000001", x"00000020", x"00000001"),
        (ALU_SLL,  x"00000001", x"00000021", x"00000002"),
        (ALU_SLL,  x"00001234", x"00000013", x"91A00000"),
        (ALU_SLL,  x"FFFFFFFF", x"FFFFFFE4", x"FFFFFFF0"),

        -- srl: zeros come in at the top
        (ALU_SRL,  x"80000000", x"00000004", x"08000000"),
        (ALU_SRL,  x"80000000", x"00000024", x"08000000"),
        (ALU_SRL,  x"80000000", x"0000000D", x"00040000"),
        (ALU_SRL,  x"80000000", x"0000001F", x"00000001"),
        (ALU_SRL,  x"80000001", x"00000000", x"80000001"),

        -- sra: copies of the sign bit come in at the top
        (ALU_SRA,  x"80000000", x"00000004", x"F8000000"),
        (ALU_SRA,  x"80000000", x"00000024", x"F8000000"),
        (ALU_SRA,  x"80000000", x"0000001B", x"FFFFFFF0"),
        (ALU_SRA,  x"80000000", x"0000001F", x"FFFFFFFF"),
        (ALU_SRA,  x"40000000", x"00000004", x"04000000"),
        (ALU_SRA,  x"40000000", x"0000001B", x"00000008"),
        (ALU_SRA,  x"80000001", x"00000000", x"80000001"),

        -- slt and sltu: the same pair gives opposite answers
        (ALU_SLT,  x"FFFFFFFF", x"00000001", x"00000001"),
        (ALU_SLTU, x"FFFFFFFF", x"00000001", x"00000000"),
        (ALU_SLT,  x"00000001", x"FFFFFFFF", x"00000000"),
        (ALU_SLTU, x"00000001", x"FFFFFFFF", x"00000001"),

        -- slt: around the immediate 1234, the two extremes, equal operands
        (ALU_SLT,  x"FFFFFFFB", x"000004D2", x"00000001"),
        (ALU_SLT,  x"000004D1", x"000004D2", x"00000001"),
        (ALU_SLT,  x"000004D2", x"000004D2", x"00000000"),
        (ALU_SLT,  x"80000000", x"7FFFFFFF", x"00000001"),
        (ALU_SLT,  x"7FFFFFFF", x"80000000", x"00000000"),
        (ALU_SLT,  x"FFFFFFFE", x"FFFFFFFF", x"00000001"),

        -- sltu: against the sign-extended immediate -567, the two extremes, equal
        (ALU_SLTU, x"00000005", x"FFFFFDC9", x"00000001"),
        (ALU_SLTU, x"FFFFFFFF", x"FFFFFDC9", x"00000000"),
        (ALU_SLTU, x"7FFFFFFF", x"80000000", x"00000001"),
        (ALU_SLTU, x"80000000", x"7FFFFFFF", x"00000000"),
        (ALU_SLTU, x"00000000", x"00000000", x"00000000")
    );

begin

    dut : entity work.alu
        port map (
            op     => op,
            a      => a,
            b      => b,
            result => result
        );

    stimulus : process
        variable seen : boolean;
    begin
        for i in VECTORS'range loop
            op <= VECTORS(i).op;
            a  <= VECTORS(i).a;
            b  <= VECTORS(i).b;
            wait for 1 ns;
            assert result = VECTORS(i).expected
                report "vector " & integer'image(i) & ": " &
                       alu_op_t'image(VECTORS(i).op) &
                       " a=" & to_hstring(VECTORS(i).a) &
                       " b=" & to_hstring(VECTORS(i).b) &
                       " gave " & to_hstring(result) &
                       ", expected " & to_hstring(VECTORS(i).expected)
                severity failure;
        end loop;

        -- Every operation has at least one vector.
        for o in alu_op_t loop
            seen := false;
            for i in VECTORS'range loop
                if VECTORS(i).op = o then
                    seen := true;
                end if;
            end loop;
            assert seen
                report "no vector for " & alu_op_t'image(o)
                severity failure;
        end loop;

        report "tb_alu: PASS (" & integer'image(VECTORS'length) & " vectors)";
        std.env.finish;
    end process stimulus;

end architecture sim;
