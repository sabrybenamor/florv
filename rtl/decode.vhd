library ieee;
use ieee.std_logic_1164.all;

use work.rv32i_pkg.all;
use work.decode_pkg.all;

entity decode is
    port (
        insn : in  word_t;
        d    : out decoded_t
    );
end entity decode;

architecture rtl of decode is

    alias opcode : opcode_t                     is insn(6 downto 0);
    alias rd     : reg_addr_t                   is insn(11 downto 7);
    alias funct3 : funct3_t                     is insn(14 downto 12);
    alias rs1    : reg_addr_t                   is insn(19 downto 15);
    alias rs2    : reg_addr_t                   is insn(24 downto 20);
    alias funct7 : std_logic_vector(6 downto 0) is insn(31 downto 25);

    -- The ALU operation of an op or op-imm instruction. alt is bit 30 where it
    -- counts: it turns add into sub and srl into sra.
    function arith_op (f3 : funct3_t; alt : boolean) return alu_op_t is
    begin
        case f3 is
            when F3_ADD_SUB =>
                if alt then return ALU_SUB; else return ALU_ADD; end if;
            when F3_SLL     => return ALU_SLL;
            when F3_SLT     => return ALU_SLT;
            when F3_SLTU    => return ALU_SLTU;
            when F3_XOR     => return ALU_XOR;
            when F3_SRL_SRA =>
                if alt then return ALU_SRA; else return ALU_SRL; end if;
            when F3_OR      => return ALU_OR;
            when F3_AND     => return ALU_AND;
            when others     => return ALU_ADD;
        end case;
    end function arith_op;

begin

    decode_insn : process (all)
        variable v     : decoded_t;
        variable legal : boolean;
        variable alt   : boolean;  -- funct7 is 0100000
    begin
        v     := DECODED_NONE;
        legal := false;
        alt   := funct7 = F7_ALT;

        case opcode is
            when OPCODE_LUI =>
                legal       := true;
                v.rd        := rd;
                v.a_sel     := A_ZERO;
                v.b_sel     := B_IMM;
                v.reg_write := '1';

            when OPCODE_AUIPC =>
                legal       := true;
                v.rd        := rd;
                v.a_sel     := A_PC;
                v.b_sel     := B_IMM;
                v.reg_write := '1';

            when OPCODE_JAL =>
                legal       := true;
                v.rd        := rd;
                v.a_sel     := A_PC;
                v.b_sel     := B_IMM;
                v.wb_sel    := WB_PC4;
                v.reg_write := '1';
                v.is_jump   := '1';

            when OPCODE_JALR =>
                legal       := funct3 = F3_ZERO;
                v.rd        := rd;
                v.rs1       := rs1;
                v.b_sel     := B_IMM;
                v.wb_sel    := WB_PC4;
                v.reg_write := '1';
                v.is_jump   := '1';

            when OPCODE_BRANCH =>
                case funct3 is
                    when F3_BEQ  | F3_BNE  => legal := true; v.alu_op := ALU_SUB;
                    when F3_BLT  | F3_BGE  => legal := true; v.alu_op := ALU_SLT;
                    when F3_BLTU | F3_BGEU => legal := true; v.alu_op := ALU_SLTU;
                    when others            => null;
                end case;
                v.rs1       := rs1;
                v.rs2       := rs2;
                v.funct3    := funct3;
                v.is_branch := '1';

            when OPCODE_LOAD =>
                case funct3 is
                    when F3_LB | F3_LH | F3_LW | F3_LBU | F3_LHU => legal := true;
                    when others                                  => null;
                end case;
                v.rd        := rd;
                v.rs1       := rs1;
                v.funct3    := funct3;
                v.b_sel     := B_IMM;
                v.wb_sel    := WB_MEM;
                v.reg_write := '1';
                v.is_load   := '1';

            when OPCODE_STORE =>
                case funct3 is
                    when F3_SB | F3_SH | F3_SW => legal := true;
                    when others                => null;
                end case;
                v.rs1      := rs1;
                v.rs2      := rs2;
                v.funct3   := funct3;
                v.b_sel    := B_IMM;
                v.is_store := '1';

            when OPCODE_OP_IMM =>
                -- Only the two shifts have a funct7; elsewhere those bits are immediate.
                if funct3 = F3_SLL then
                    legal    := funct7 = F7_NORMAL;
                    v.alu_op := ALU_SLL;
                elsif funct3 = F3_SRL_SRA then
                    legal    := funct7 = F7_NORMAL or alt;
                    v.alu_op := arith_op(funct3, alt);
                else
                    legal    := true;
                    v.alu_op := arith_op(funct3, false);
                end if;
                v.rd        := rd;
                v.rs1       := rs1;
                v.b_sel     := B_IMM;
                v.reg_write := '1';

            when OPCODE_OP =>
                legal := funct7 = F7_NORMAL or
                         (alt and (funct3 = F3_ADD_SUB or funct3 = F3_SRL_SRA));
                v.alu_op    := arith_op(funct3, alt);
                v.rd        := rd;
                v.rs1       := rs1;
                v.rs2       := rs2;
                v.reg_write := '1';

            when OPCODE_MISC_MEM =>
                -- fence: retires and does nothing. Only funct3 is checked.
                legal := funct3 = F3_ZERO;

            when OPCODE_SYSTEM =>
                legal     := insn = INSN_ECALL or insn = INSN_EBREAK;
                v.is_halt := '1';

            when others =>
                null;
        end case;

        if not legal then
            v         := DECODED_NONE;
            v.illegal := '1';
        end if;

        d <= v;
    end process decode_insn;

end architecture rtl;
