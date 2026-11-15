-- The read-only registers of rv_rig that describe the core: STATUS, LAST_PC and
-- RETIRE_COUNT. Their meaning is defined in docs/regmap.md and not repeated here.
--
-- It sits next to rv_core and watches its retire outputs and its trap output. It
-- is clocked and reset like the core (rstn synchronous, active low), so the three
-- values are 0 while the core is in reset and start from 0 after it.
--
-- A retire whose next pc equals its own pc (an instruction that jumps to itself)
-- is not counted and does not change last_pc; it sets the STALLED bit, which
-- stays set until reset. That is how every test program ends ("1: j 1b" after the
-- store to tohost), so the count stops at the store, where the ISS stops too.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.rv32i_pkg.all;

entity core_status is
    port (
        clk  : in std_logic;
        rstn : in std_logic;  -- the core's reset
        run  : in std_logic;  -- the core's run input

        -- from rv_core
        retire_valid   : in std_logic;
        retire_pc      : in word_t;
        retire_next_pc : in word_t;
        trap           : in std_logic;

        -- to the register read multiplexer
        status       : out word_t;  -- bit 0 RUNNING, bit 1 STALLED, bit 2 TRAPPED
        last_pc      : out word_t;
        retire_count : out word_t
    );
end entity core_status;

architecture rtl of core_status is

    signal count   : unsigned(31 downto 0) := (others => '0');
    signal last    : word_t                := (others => '0');
    signal stalled : std_logic             := '0';

begin

    process (clk)
    begin
        if rising_edge(clk) then
            if rstn = '0' then
                count   <= (others => '0');
                last    <= (others => '0');
                stalled <= '0';
            elsif retire_valid = '1' then
                if retire_next_pc = retire_pc then
                    stalled <= '1';
                else
                    last  <= retire_pc;
                    count <= count + 1;  -- wraps to 0 after 0xFFFFFFFF
                end if;
            end if;
        end if;
    end process;

    last_pc      <= last;
    retire_count <= std_logic_vector(count);

    status(0)           <= run and rstn and not trap;
    status(1)           <= stalled;
    status(2)           <= trap;
    status(31 downto 3) <= (others => '0');

end architecture rtl;
