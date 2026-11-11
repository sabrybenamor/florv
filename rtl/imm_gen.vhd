-- Immediate generator: picks the immediate out of an instruction word and extends
-- it to 32 bits. Combinational. The result follows the conventions of the C++
-- decoder (core/decoder.cpp), so both sides give the same value for one word:
--
--   I  op-imm, load, jalr   insn[31:20], sign-extended
--   S  store                insn[31:25] & insn[11:7], sign-extended
--   B  branch               an even offset from the pc, sign-extended
--   U  lui, auipc           insn[31:12] already shifted left by 12
--   J  jal                  an even offset from the pc, sign-extended
--
--   slli, srli, srai        the shift amount insn[24:20] alone. Bit 30, which tells
--                           srai from srli, is not part of the immediate.
--   every other word        zero (op, fence, ecall, ebreak, unknown opcodes)
--
-- Only the opcode and funct3 are looked at. Whether the word is a legal
-- instruction is for decode to say.

library ieee;
use ieee.std_logic_1164.all;

use work.rv32i_pkg.all;

entity imm_gen is
    port (
        insn : in  word_t;
        imm  : out word_t
    );
end entity imm_gen;

architecture rtl of imm_gen is

    alias opcode : opcode_t is insn(6 downto 0);
    alias funct3 : funct3_t is insn(14 downto 12);

begin

    generate_imm : process (all)
        variable sign : word_t;  
    begin
        sign := (others => insn(31));

        case opcode is
            when OPCODE_OP_IMM =>
                if funct3 = F3_SLL or funct3 = F3_SRL_SRA then
                    imm <= (others => '0');
                    imm(4 downto 0) <= insn(24 downto 20);
                else
                    imm <= sign(31 downto 11) & insn(30 downto 20);
                end if;

            when OPCODE_LOAD | OPCODE_JALR =>
                imm <= sign(31 downto 11) & insn(30 downto 20);

            when OPCODE_STORE =>
                imm <= sign(31 downto 11) & insn(30 downto 25) & insn(11 downto 7);

            when OPCODE_BRANCH =>
                imm <= sign(31 downto 12) & insn(7) & insn(30 downto 25) & insn(11 downto 8) & '0';

            when OPCODE_LUI | OPCODE_AUIPC =>
                imm <= insn(31 downto 12) & x"000";

            when OPCODE_JAL =>
                imm <= sign(31 downto 20) & insn(19 downto 12) & insn(20) & insn(30 downto 21) & '0';

            when others =>
                imm <= (others => '0');
        end case;
    end process generate_imm;

end architecture rtl;
