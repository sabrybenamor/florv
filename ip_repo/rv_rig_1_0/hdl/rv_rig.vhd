library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity rv_rig is
	generic (
		-- Users to add parameters here

		-- User parameters ends
		-- Do not modify the parameters beyond this line


		-- Parameters of Axi Slave Bus Interface S00_AXI
		C_S00_AXI_DATA_WIDTH	: integer	:= 32;
		C_S00_AXI_ADDR_WIDTH	: integer	:= 5
	);
	port (
		-- Users to add ports here

		-- The core's memory port, for port B of the program RAM. The names follow
		-- the BRAM interface: din is the data written into the RAM, dout the data
		-- read from it. mem_addr is a byte address whose bits 1:0 are always "00";
		-- the RAM ignores the bits above its size. mem_we has one bit per byte and
		-- is "0000" on a read. The RAM must answer a read after one clock edge
		-- (no output register).
		mem_clk	: out std_logic;
		mem_rst	: out std_logic;
		mem_en	: out std_logic;
		mem_we	: out std_logic_vector(3 downto 0);
		mem_addr	: out std_logic_vector(31 downto 0);
		mem_din	: out std_logic_vector(31 downto 0);
		mem_dout	: in std_logic_vector(31 downto 0);

		-- User ports ends
		-- Do not modify the ports beyond this line


		-- Ports of Axi Slave Bus Interface S00_AXI
		s00_axi_aclk	: in std_logic;
		s00_axi_aresetn	: in std_logic;
		s00_axi_awaddr	: in std_logic_vector(C_S00_AXI_ADDR_WIDTH-1 downto 0);
		s00_axi_awprot	: in std_logic_vector(2 downto 0);
		s00_axi_awvalid	: in std_logic;
		s00_axi_awready	: out std_logic;
		s00_axi_wdata	: in std_logic_vector(C_S00_AXI_DATA_WIDTH-1 downto 0);
		s00_axi_wstrb	: in std_logic_vector((C_S00_AXI_DATA_WIDTH/8)-1 downto 0);
		s00_axi_wvalid	: in std_logic;
		s00_axi_wready	: out std_logic;
		s00_axi_bresp	: out std_logic_vector(1 downto 0);
		s00_axi_bvalid	: out std_logic;
		s00_axi_bready	: in std_logic;
		s00_axi_araddr	: in std_logic_vector(C_S00_AXI_ADDR_WIDTH-1 downto 0);
		s00_axi_arprot	: in std_logic_vector(2 downto 0);
		s00_axi_arvalid	: in std_logic;
		s00_axi_arready	: out std_logic;
		s00_axi_rdata	: out std_logic_vector(C_S00_AXI_DATA_WIDTH-1 downto 0);
		s00_axi_rresp	: out std_logic_vector(1 downto 0);
		s00_axi_rvalid	: out std_logic;
		s00_axi_rready	: in std_logic
	);
end rv_rig;

architecture arch_imp of rv_rig is

	-- component declaration
	component rv_rig_slave_lite_v1_0_S00_AXI is
		generic (
		C_S_AXI_DATA_WIDTH	: integer	:= 32;
		C_S_AXI_ADDR_WIDTH	: integer	:= 5
		);
		port (
		ctrl_run	: out std_logic;
		ctrl_reset	: out std_logic;
		status	: in std_logic_vector(31 downto 0);
		last_pc	: in std_logic_vector(31 downto 0);
		retire_count	: in std_logic_vector(31 downto 0);
		S_AXI_ACLK	: in std_logic;
		S_AXI_ARESETN	: in std_logic;
		S_AXI_AWADDR	: in std_logic_vector(C_S_AXI_ADDR_WIDTH-1 downto 0);
		S_AXI_AWPROT	: in std_logic_vector(2 downto 0);
		S_AXI_AWVALID	: in std_logic;
		S_AXI_AWREADY	: out std_logic;
		S_AXI_WDATA	: in std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
		S_AXI_WSTRB	: in std_logic_vector((C_S_AXI_DATA_WIDTH/8)-1 downto 0);
		S_AXI_WVALID	: in std_logic;
		S_AXI_WREADY	: out std_logic;
		S_AXI_BRESP	: out std_logic_vector(1 downto 0);
		S_AXI_BVALID	: out std_logic;
		S_AXI_BREADY	: in std_logic;
		S_AXI_ARADDR	: in std_logic_vector(C_S_AXI_ADDR_WIDTH-1 downto 0);
		S_AXI_ARPROT	: in std_logic_vector(2 downto 0);
		S_AXI_ARVALID	: in std_logic;
		S_AXI_ARREADY	: out std_logic;
		S_AXI_RDATA	: out std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
		S_AXI_RRESP	: out std_logic_vector(1 downto 0);
		S_AXI_RVALID	: out std_logic;
		S_AXI_RREADY	: in std_logic
		);
	end component rv_rig_slave_lite_v1_0_S00_AXI;

	-- The registers and the core (docs/regmap.md)
	signal ctrl_run	: std_logic;
	signal ctrl_reset	: std_logic;
	signal status	: std_logic_vector(31 downto 0);
	signal last_pc	: std_logic_vector(31 downto 0);
	signal retire_count	: std_logic_vector(31 downto 0);

	signal core_rstn	: std_logic;
	signal core_mem_we	: std_logic;
	signal core_mem_be	: std_logic_vector(3 downto 0);
	signal core_trap	: std_logic;
	signal retire_valid	: std_logic;
	signal retire_pc	: std_logic_vector(31 downto 0);
	signal retire_next_pc	: std_logic_vector(31 downto 0);

begin

-- Instantiation of Axi Bus Interface S00_AXI
rv_rig_slave_lite_v1_0_S00_AXI_inst : rv_rig_slave_lite_v1_0_S00_AXI
	generic map (
		C_S_AXI_DATA_WIDTH	=> C_S00_AXI_DATA_WIDTH,
		C_S_AXI_ADDR_WIDTH	=> C_S00_AXI_ADDR_WIDTH
	)
	port map (
		ctrl_run	=> ctrl_run,
		ctrl_reset	=> ctrl_reset,
		status	=> status,
		last_pc	=> last_pc,
		retire_count	=> retire_count,
		S_AXI_ACLK	=> s00_axi_aclk,
		S_AXI_ARESETN	=> s00_axi_aresetn,
		S_AXI_AWADDR	=> s00_axi_awaddr,
		S_AXI_AWPROT	=> s00_axi_awprot,
		S_AXI_AWVALID	=> s00_axi_awvalid,
		S_AXI_AWREADY	=> s00_axi_awready,
		S_AXI_WDATA	=> s00_axi_wdata,
		S_AXI_WSTRB	=> s00_axi_wstrb,
		S_AXI_WVALID	=> s00_axi_wvalid,
		S_AXI_WREADY	=> s00_axi_wready,
		S_AXI_BRESP	=> s00_axi_bresp,
		S_AXI_BVALID	=> s00_axi_bvalid,
		S_AXI_BREADY	=> s00_axi_bready,
		S_AXI_ARADDR	=> s00_axi_araddr,
		S_AXI_ARPROT	=> s00_axi_arprot,
		S_AXI_ARVALID	=> s00_axi_arvalid,
		S_AXI_ARREADY	=> s00_axi_arready,
		S_AXI_RDATA	=> s00_axi_rdata,
		S_AXI_RRESP	=> s00_axi_rresp,
		S_AXI_RVALID	=> s00_axi_rvalid,
		S_AXI_RREADY	=> s00_axi_rready
	);

	-- Add user logic here

	-- The core is in reset while the bus is, or while CTRL.RESET is 1.
	core_rstn <= s00_axi_aresetn and not ctrl_reset;

	-- The RISC-V core. Its retire outputs that nothing reads yet (they are for the
	-- trace writer of revision 3) are left open.
	u_core : entity work.rv_core
		generic map (
			RESET_PC	=> x"80000000",
			READ_LATENCY	=> 1
		)
		port map (
			clk	=> s00_axi_aclk,
			rstn	=> core_rstn,
			run	=> ctrl_run,
			mem_en	=> mem_en,
			mem_we	=> core_mem_we,
			mem_addr	=> mem_addr,
			mem_be	=> core_mem_be,
			mem_wdata	=> mem_din,
			mem_rdata	=> mem_dout,
			retire_valid	=> retire_valid,
			retire_pc	=> retire_pc,
			retire_insn	=> open,
			retire_next_pc	=> retire_next_pc,
			retire_rd	=> open,
			retire_rd_wdata	=> open,
			retire_mem_addr	=> open,
			retire_mem_mask	=> open,
			retire_mem_wdata	=> open,
			retire_is_load	=> open,
			retire_is_store	=> open,
			trap	=> core_trap
		);

	-- The RAM has no separate write signal: a byte is written when its bit of
	-- mem_we is 1. The core already gives "0000" on a read; core_mem_we is and-ed
	-- in so that this does not rest on that alone.
	mem_we  <= core_mem_be when core_mem_we = '1' else "0000";
	mem_clk <= s00_axi_aclk;
	mem_rst <= '0';

	-- STATUS, LAST_PC and RETIRE_COUNT
	u_status : entity work.core_status
		port map (
			clk	=> s00_axi_aclk,
			rstn	=> core_rstn,
			run	=> ctrl_run,
			retire_valid	=> retire_valid,
			retire_pc	=> retire_pc,
			retire_next_pc	=> retire_next_pc,
			trap	=> core_trap,
			status	=> status,
			last_pc	=> last_pc,
			retire_count	=> retire_count
		);

	-- User logic ends

end arch_imp;
