library ieee;
use ieee.std_logic_1164.all;

package rv32i_pkg is

    ---------------------------------------------------------------------------
    -- Types
    ---------------------------------------------------------------------------
    subtype word_t     is std_logic_vector(31 downto 0);  -- a register, an address, an instruction
    subtype reg_addr_t is std_logic_vector(4 downto 0);   -- a register number, x0 to x31
    subtype opcode_t   is std_logic_vector(6 downto 0);   -- instruction bits 6..0
    subtype funct3_t   is std_logic_vector(2 downto 0);   -- instruction bits 14..12

    ---------------------------------------------------------------------------
    -- Opcodes: instruction bits 6..0
    ---------------------------------------------------------------------------
    constant OPCODE_LUI      : opcode_t := "0110111";  -- 0x37
    constant OPCODE_AUIPC    : opcode_t := "0010111";  -- 0x17
    constant OPCODE_JAL      : opcode_t := "1101111";  -- 0x6F
    constant OPCODE_JALR     : opcode_t := "1100111";  -- 0x67
    constant OPCODE_BRANCH   : opcode_t := "1100011";  -- 0x63  beq bne blt bge bltu bgeu
    constant OPCODE_LOAD     : opcode_t := "0000011";  -- 0x03  lb lh lw lbu lhu
    constant OPCODE_STORE    : opcode_t := "0100011";  -- 0x23  sb sh sw
    constant OPCODE_OP_IMM   : opcode_t := "0010011";  -- 0x13  addi slti sltiu xori ori andi slli srli srai
    constant OPCODE_OP       : opcode_t := "0110011";  -- 0x33  add sub sll slt sltu xor srl sra or and
    constant OPCODE_MISC_MEM : opcode_t := "0001111";  -- 0x0F  fence
    constant OPCODE_SYSTEM   : opcode_t := "1110011";  -- 0x73  ecall ebreak

    ---------------------------------------------------------------------------
    -- funct3: instruction bits 14..12. The same three bits mean different things
    -- under different opcodes, so each name carries its group.
    ---------------------------------------------------------------------------
    -- OPCODE_BRANCH
    constant F3_BEQ  : funct3_t := "000";
    constant F3_BNE  : funct3_t := "001";
    constant F3_BLT  : funct3_t := "100";
    constant F3_BGE  : funct3_t := "101";
    constant F3_BLTU : funct3_t := "110";
    constant F3_BGEU : funct3_t := "111";

    -- OPCODE_LOAD
    constant F3_LB  : funct3_t := "000";
    constant F3_LH  : funct3_t := "001";
    constant F3_LW  : funct3_t := "010";
    constant F3_LBU : funct3_t := "100";
    constant F3_LHU : funct3_t := "101";

    -- OPCODE_STORE
    constant F3_SB : funct3_t := "000";
    constant F3_SH : funct3_t := "001";
    constant F3_SW : funct3_t := "010";

    -- OPCODE_OP and OPCODE_OP_IMM
    constant F3_ADD_SUB : funct3_t := "000";  -- sub when ALT_BIT is set (OPCODE_OP only)
    constant F3_SLL     : funct3_t := "001";
    constant F3_SLT     : funct3_t := "010";
    constant F3_SLTU    : funct3_t := "011";
    constant F3_XOR     : funct3_t := "100";
    constant F3_SRL_SRA : funct3_t := "101";  -- sra when ALT_BIT is set
    constant F3_OR      : funct3_t := "110";
    constant F3_AND     : funct3_t := "111";

    -- OPCODE_JALR and OPCODE_MISC_MEM use funct3 "000" only.
    constant F3_ZERO : funct3_t := "000";

    ---------------------------------------------------------------------------
    -- funct7: instruction bits 31..25. RV32I uses two values. They differ in one
    -- bit, instruction bit 30, which picks sub over add and sra over srl.
    ---------------------------------------------------------------------------
    constant F7_NORMAL : std_logic_vector(6 downto 0) := "0000000";
    constant F7_ALT    : std_logic_vector(6 downto 0) := "0100000";
    constant ALT_BIT   : natural := 30;

    ---------------------------------------------------------------------------
    -- The two SYSTEM instructions are whole words.
    ---------------------------------------------------------------------------
    constant INSN_ECALL  : word_t := x"00000073";
    constant INSN_EBREAK : word_t := x"00100073";

    ---------------------------------------------------------------------------
    -- ALU operations. An enumerated type, so a waveform shows the name and a case
    -- statement that forgets one does not compile. Synthesis chooses the encoding.
    ---------------------------------------------------------------------------
    type alu_op_t is (
        ALU_ADD,
        ALU_SUB,
        ALU_AND,
        ALU_OR,
        ALU_XOR,
        ALU_SLL,   
        ALU_SRL,   
        ALU_SRA,   
        ALU_SLT,   
        ALU_SLTU   
    );

end package rv32i_pkg;

