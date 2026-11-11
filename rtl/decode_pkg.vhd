library ieee;
use ieee.std_logic_1164.all;

use work.rv32i_pkg.all;

package decode_pkg is

    type a_sel_t  is (A_RS1, A_PC, A_ZERO);     
    type b_sel_t  is (B_RS2, B_IMM);            
    type wb_sel_t is (WB_ALU, WB_MEM, WB_PC4);  

    type decoded_t is record
        rd        : reg_addr_t;  
        rs1       : reg_addr_t;  
        rs2       : reg_addr_t;  
        funct3    : funct3_t;    
        alu_op    : alu_op_t;
        a_sel     : a_sel_t;
        b_sel     : b_sel_t;
        wb_sel    : wb_sel_t;
        reg_write : std_logic;   
        is_load   : std_logic;
        is_store  : std_logic;
        is_branch : std_logic;  
        is_jump   : std_logic;   
        is_halt   : std_logic;   
        illegal   : std_logic;   
    end record;

    -- An instruction that asks for nothing. decode gives this for fence, and for
    -- an illegal word with illegal set.
    constant DECODED_NONE : decoded_t := (
        rd        => (others => '0'),
        rs1       => (others => '0'),
        rs2       => (others => '0'),
        funct3    => (others => '0'),
        alu_op    => ALU_ADD,
        a_sel     => A_RS1,
        b_sel     => B_RS2,
        wb_sel    => WB_ALU,
        reg_write => '0',
        is_load   => '0',
        is_store  => '0',
        is_branch => '0',
        is_jump   => '0',
        is_halt   => '0',
        illegal   => '0'
    );

end package decode_pkg;
