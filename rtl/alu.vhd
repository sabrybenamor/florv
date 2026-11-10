library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.rv32i_pkg.all;

entity alu is
    port (
        op     : in  alu_op_t;
        a      : in  word_t;
        b      : in  word_t;
        result : out word_t
    );
end entity alu;

architecture rtl of alu is

    constant ONE  : word_t := x"00000001";
    constant ZERO : word_t := x"00000000";

begin

    compute : process (all)
        variable shamt : natural range 0 to 31;
    begin
        shamt := to_integer(unsigned(b(4 downto 0)));

        case op is
            when ALU_ADD  => result <= std_logic_vector(unsigned(a) + unsigned(b));
            when ALU_SUB  => result <= std_logic_vector(unsigned(a) - unsigned(b));
            when ALU_AND  => result <= a and b;
            when ALU_OR   => result <= a or b;
            when ALU_XOR  => result <= a xor b;
            when ALU_SLL  => result <= std_logic_vector(shift_left(unsigned(a), shamt));
            when ALU_SRL  => result <= std_logic_vector(shift_right(unsigned(a), shamt));
            when ALU_SRA  => result <= std_logic_vector(shift_right(signed(a), shamt));
            when ALU_SLT  =>
                if signed(a) < signed(b) then
                    result <= ONE;
                else
                    result <= ZERO;
                end if;
            when ALU_SLTU =>
                if unsigned(a) < unsigned(b) then
                    result <= ONE;
                else
                    result <= ZERO;
                end if;
        end case;
    end process compute;

end architecture rtl;
