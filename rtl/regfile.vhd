library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.rv32i_pkg.all;

entity regfile is
    port (
        clk    : in  std_logic;

        we     : in  std_logic;
        waddr  : in  reg_addr_t;
        wdata  : in  word_t;

        raddr1 : in  reg_addr_t;
        rdata1 : out word_t;

        raddr2 : in  reg_addr_t;
        rdata2 : out word_t
    );
end entity regfile;

architecture rtl of regfile is

    constant X0 : reg_addr_t := "00000";

    type reg_array_t is array (0 to 31) of word_t;
    signal regs : reg_array_t := (others => (others => '0'));

begin

    write_port : process (clk)
    begin
        if rising_edge(clk) then
            if we = '1' and waddr /= X0 then
                regs(to_integer(unsigned(waddr))) <= wdata;
            end if;
        end if;
    end process write_port;

    rdata1 <= (others => '0') when raddr1 = X0 else regs(to_integer(unsigned(raddr1)));
    rdata2 <= (others => '0') when raddr2 = X0 else regs(to_integer(unsigned(raddr2)));

end architecture rtl;
