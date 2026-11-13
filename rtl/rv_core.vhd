library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.rv32i_pkg.all;
use work.decode_pkg.all;

entity rv_core is
    generic (
        RESET_PC     : word_t   := x"80000000";
        READ_LATENCY : positive := 1
    );
    port (

        -- Processor control
        clk  : in  std_logic;
        rstn : in  std_logic;
        run  : in  std_logic;

        -- Memory interface
        mem_en    : out std_logic;
        mem_we    : out std_logic;
        mem_addr  : out word_t;
        mem_be    : out std_logic_vector(3 downto 0);
        mem_wdata : out word_t;
        mem_rdata : in  word_t;

        --Retirement interface
        retire_valid     : out std_logic;
        retire_pc        : out word_t;
        retire_insn      : out word_t;
        retire_next_pc   : out word_t;
        retire_rd        : out reg_addr_t;
        retire_rd_wdata  : out word_t;
        retire_mem_addr  : out word_t;
        retire_mem_mask  : out std_logic_vector(3 downto 0);
        retire_mem_wdata : out word_t;
        retire_is_load   : out std_logic;
        retire_is_store  : out std_logic;


        -- Trap output
        trap : out std_logic
    );
end entity rv_core;

architecture rtl of rv_core is

    type state_t is (S_FETCH, S_EXEC, S_MEM, S_WB, S_TRAP);

    signal state       : state_t := S_FETCH;
    signal pc          : word_t  := RESET_PC;         
    signal ir          : word_t  := (others => '0');  
    signal alu_out     : word_t  := (others => '0');  
    signal next_pc_reg : word_t  := (others => '0');  
    signal load_word   : word_t  := (others => '0');  

    signal wait_cnt : natural range 0 to READ_LATENCY := 0;

  
    signal d          : decoded_t;
    signal imm        : word_t;
    signal rs1_data   : word_t;
    signal rs2_data   : word_t;
    signal alu_a      : word_t;
    signal alu_b      : word_t;
    signal alu_result : word_t;

    signal pc_plus4  : word_t;
    signal taken     : std_logic;  
    signal next_pc   : word_t;
    signal exec_trap : std_logic;  

    signal is_mem      : std_logic;                     
    signal access_mask : std_logic_vector(3 downto 0);  
    signal store_value : word_t;                        
    signal load_value  : word_t;                        

    signal wb_data    : word_t;     
    signal writes_reg : std_logic;  
    signal retiring   : std_logic;  
    signal reg_we     : std_logic;  

begin

    u_decode : entity work.decode
        port map (
            insn => ir,
            d    => d
        );

    u_imm_gen : entity work.imm_gen
        port map (
            insn => ir,
            imm  => imm
        );

    u_regfile : entity work.regfile
        port map (
            clk    => clk,
            we     => reg_we,
            waddr  => d.rd,
            wdata  => wb_data,
            raddr1 => d.rs1,
            rdata1 => rs1_data,
            raddr2 => d.rs2,
            rdata2 => rs2_data
        );

    u_alu : entity work.alu
        port map (
            op     => d.alu_op,
            a      => alu_a,
            b      => alu_b,
            result => alu_result
        );

    ---------------------------------------------------------------------------
    -- The state machine
    ---------------------------------------------------------------------------
    fsm : process (clk)
    begin
        if rising_edge(clk) then
            if rstn = '0' then
                state    <= S_FETCH;
                pc       <= RESET_PC;
                wait_cnt <= 0;
            else
                case state is
                    when S_FETCH =>
                        if wait_cnt = 0 then
                            if run = '1' then
                                wait_cnt <= 1;
                            end if;
                        elsif wait_cnt = READ_LATENCY then
                            ir       <= mem_rdata;
                            wait_cnt <= 0;
                            state    <= S_EXEC;
                        else
                            wait_cnt <= wait_cnt + 1;
                        end if;

                    when S_EXEC =>
                        alu_out     <= alu_result;
                        next_pc_reg <= next_pc;
                        if exec_trap = '1' then
                            state <= S_TRAP;
                        elsif is_mem = '1' then
                            state <= S_MEM;
                        else
                            state <= S_WB;
                        end if;

                    when S_MEM =>
                        if d.is_store = '1' then
                            state <= S_WB;
                        elsif wait_cnt = 0 then
                            wait_cnt <= 1;
                        elsif wait_cnt = READ_LATENCY then
                            load_word <= mem_rdata;
                            wait_cnt  <= 0;
                            state     <= S_WB;
                        else
                            wait_cnt <= wait_cnt + 1;
                        end if;

                    when S_WB =>
                        pc    <= next_pc_reg;
                        state <= S_FETCH;

                    when S_TRAP =>
                        null;

                end case;
            end if;
        end if;
    end process fsm;

   
    with d.a_sel select alu_a <=
        rs1_data        when A_RS1,
        pc              when A_PC,
        (others => '0') when A_ZERO;

    alu_b <= rs2_data when d.b_sel = B_RS2 else imm;

   
    branch_decide : process (all)
        variable holds : boolean;
    begin
        if d.funct3(2) = '0' then
            holds := unsigned(alu_result) = 0;
        else
            holds := alu_result(0) = '1';
        end if;
        if d.funct3(0) = '1' then
            holds := not holds;
        end if;

        if d.is_branch = '1' and holds then
            taken <= '1';
        else
            taken <= '0';
        end if;
    end process branch_decide;

    pc_plus4 <= std_logic_vector(unsigned(pc) + 4);

    
    next_pc <= alu_result(31 downto 1) & '0'                  when d.is_jump = '1' else
               std_logic_vector(unsigned(pc) + unsigned(imm)) when taken = '1' else
               pc_plus4;

    is_mem <= d.is_load or d.is_store;

    exec_trap_decide : process (all)
        variable misaligned : boolean;
    begin
        case d.funct3(1 downto 0) is
            when "00"   => misaligned := false;
            when "01"   => misaligned := alu_result(0) = '1';
            when others => misaligned := alu_result(1 downto 0) /= "00";
        end case;

        if d.illegal = '1' then
            exec_trap <= '1';
        elsif next_pc(1 downto 0) /= "00" then  
            exec_trap <= '1';
        elsif is_mem = '1' and misaligned then
            exec_trap <= '1';
        else
            exec_trap <= '0';
        end if;
    end process exec_trap_decide;

    
    access_mask <= "0001" when d.funct3(1 downto 0) = "00" else
                   "0011" when d.funct3(1 downto 0) = "01" else
                   "1111";

    store_value <= x"000000" & rs2_data(7 downto 0)  when d.funct3(1 downto 0) = "00" else
                   x"0000"   & rs2_data(15 downto 0) when d.funct3(1 downto 0) = "01" else
                   rs2_data;

    
    mem_port : process (all)
        variable offset : natural range 0 to 3;
    begin
        offset := to_integer(unsigned(alu_out(1 downto 0)));

        mem_en    <= '0';
        mem_we    <= '0';
        mem_be    <= "0000";
        mem_wdata <= (others => '0');

        if state = S_MEM then
            mem_addr <= alu_out(31 downto 2) & "00";
        else
            mem_addr <= pc(31 downto 2) & "00";
        end if;

        if rstn = '1' and wait_cnt = 0 then
            if state = S_FETCH then
                mem_en <= run;
            elsif state = S_MEM then
                mem_en <= '1';
                if d.is_store = '1' then
                    mem_we    <= '1';
                    mem_be    <= std_logic_vector(shift_left(unsigned(access_mask), offset));
                    mem_wdata <= std_logic_vector(shift_left(unsigned(store_value), 8 * offset));
                end if;
            end if;
        end if;
    end process mem_port;

 
    load_extract : process (all)
        variable shifted : word_t;
    begin
        shifted := std_logic_vector(
            shift_right(unsigned(load_word), 8 * to_integer(unsigned(alu_out(1 downto 0)))));

        case d.funct3 is
            when F3_LB  => load_value <= std_logic_vector(resize(signed(shifted(7 downto 0)), 32));
            when F3_LH  => load_value <= std_logic_vector(resize(signed(shifted(15 downto 0)), 32));
            when F3_LBU => load_value <= x"000000" & shifted(7 downto 0);
            when F3_LHU => load_value <= x"0000" & shifted(15 downto 0);
            when others => load_value <= shifted;  -- lw: the offset is 0
        end case;
    end process load_extract;

 
    with d.wb_sel select wb_data <=
        alu_out    when WB_ALU,
        load_value when WB_MEM,
        pc_plus4   when WB_PC4;

    
    writes_reg <= '1' when d.reg_write = '1' and d.rd /= "00000" else '0';

    retiring <= '1' when state = S_WB and rstn = '1' else '0';
    reg_we   <= retiring and writes_reg;

    retire_valid <= retiring;

    retire_pc        <= pc;
    retire_insn      <= ir;
    retire_next_pc   <= next_pc_reg;
    retire_rd        <= d.rd    when writes_reg = '1' else (others => '0');
    retire_rd_wdata  <= wb_data when writes_reg = '1' else (others => '0');
    retire_mem_addr  <= alu_out     when is_mem = '1' else (others => '0');
    retire_mem_mask  <= access_mask when is_mem = '1' else "0000";
    retire_mem_wdata <= store_value when d.is_store = '1' else (others => '0');
    retire_is_load   <= d.is_load;
    retire_is_store  <= d.is_store;

    trap <= '1' when state = S_TRAP else '0';

end architecture rtl;
