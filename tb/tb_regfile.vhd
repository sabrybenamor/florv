-- Self-checking testbench for regfile. Run it with:  tools\sim.bat tb_regfile
-- It prints PASS when every check held and stops at the first one that did not.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.rv32i_pkg.all;

entity tb_regfile is
end entity tb_regfile;

architecture sim of tb_regfile is

    constant CLK_PERIOD : time := 20 ns;  -- 50 MHz, the clock of the fabric

    signal clk    : std_logic  := '0';
    signal we     : std_logic  := '0';
    signal waddr  : reg_addr_t := (others => '0');
    signal wdata  : word_t     := (others => '0');
    signal raddr1 : reg_addr_t := (others => '0');
    signal rdata1 : word_t;
    signal raddr2 : reg_addr_t := (others => '0');
    signal rdata2 : word_t;

    function to_addr(index : natural) return reg_addr_t is
    begin
        return std_logic_vector(to_unsigned(index, 5));
    end function;

    -- A different value for every register, with the top bit set for half of them.
    function pattern(index : natural) return word_t is
    begin
        return std_logic_vector(to_unsigned(index, 8)) &
               std_logic_vector(to_unsigned(255 - index, 8)) &
               x"A5" &
               std_logic_vector(to_unsigned(index * 7, 8));
    end function;

begin

    clk <= not clk after CLK_PERIOD / 2;

    dut : entity work.regfile
        port map (
            clk    => clk,
            we     => we,
            waddr  => waddr,
            wdata  => wdata,
            raddr1 => raddr1,
            rdata1 => rdata1,
            raddr2 => raddr2,
            rdata2 => rdata2
        );

    stimulus : process

        variable checks : natural := 0;

        -- Writes one register: the inputs are set while the clock is low, the rising
        -- edge does the write, and we is taken away again at the next falling edge.
        procedure write_reg(index : natural; value : word_t) is
        begin
            waddr <= to_addr(index);
            wdata <= value;
            we    <= '1';
            wait until rising_edge(clk);
            wait until falling_edge(clk);
            we    <= '0';
        end procedure;

        -- Reads one register on both ports. No clock edge: the read is asynchronous.
        procedure expect_reg(index : natural; expected : word_t; what : string) is
        begin
            raddr1 <= to_addr(index);
            raddr2 <= to_addr(index);
            wait for 1 ns;
            assert rdata1 = expected
                report what & ": port 1 read x" & integer'image(index) & " as " &
                       to_hstring(rdata1) & ", expected " & to_hstring(expected)
                severity failure;
            assert rdata2 = expected
                report what & ": port 2 read x" & integer'image(index) & " as " &
                       to_hstring(rdata2) & ", expected " & to_hstring(expected)
                severity failure;
            checks := checks + 2;
        end procedure;

    begin
        wait until falling_edge(clk);

        -- 1. Every register reads zero before anything is written.
        for i in 0 to 31 loop
            expect_reg(i, x"00000000", "initial value");
        end loop;

        -- 2. x0 stays zero whatever is written to it.
        write_reg(0, x"FFFFFFFF");
        expect_reg(0, x"00000000", "x0 after a write of all ones");
        write_reg(0, x"12345678");
        expect_reg(0, x"00000000", "x0 after a second write");

        -- 3. x31 is written and read back.
        write_reg(31, x"DEADBEEF");
        expect_reg(31, x"DEADBEEF", "x31 read back");

        -- 4. The write to x31 touched no other register.
        for i in 0 to 30 loop
            expect_reg(i, x"00000000", "after writing only x31");
        end loop;

        -- 5. Nothing is written while we is low.
        waddr <= to_addr(31);
        wdata <= x"00000000";
        we    <= '0';
        wait until rising_edge(clk);
        wait until falling_edge(clk);
        expect_reg(31, x"DEADBEEF", "we low");

        -- 6. The write is synchronous: with we high, the old value stays until the
        --    rising edge and the new one is there right after it.
        waddr <= to_addr(31);
        wdata <= x"0BADF00D";
        we    <= '1';
        expect_reg(31, x"DEADBEEF", "before the clock edge");
        wait until rising_edge(clk);
        expect_reg(31, x"0BADF00D", "after the clock edge");
        wait until falling_edge(clk);
        we    <= '0';

        -- 7. Every register holds its own value: write all, then read all.
        for i in 1 to 31 loop
            write_reg(i, pattern(i));
        end loop;
        for i in 1 to 31 loop
            expect_reg(i, pattern(i), "own value");
        end loop;
        expect_reg(0, x"00000000", "x0 after all registers were written");

        -- 8. A register can be overwritten, and its neighbours keep their values.
        write_reg(16, x"FFFFFFFF");
        expect_reg(16, x"FFFFFFFF", "overwrite");
        expect_reg(15, pattern(15), "neighbour below");
        expect_reg(17, pattern(17), "neighbour above");
        write_reg(16, x"00000000");
        expect_reg(16, x"00000000", "overwrite with zero");

        -- 9. The two read ports are independent: two different registers at once.
        raddr1 <= to_addr(5);
        raddr2 <= to_addr(27);
        wait for 1 ns;
        assert rdata1 = pattern(5)
            report "two ports: port 1 read " & to_hstring(rdata1) severity failure;
        assert rdata2 = pattern(27)
            report "two ports: port 2 read " & to_hstring(rdata2) severity failure;
        raddr1 <= to_addr(27);
        raddr2 <= to_addr(0);
        wait for 1 ns;
        assert rdata1 = pattern(27)
            report "two ports swapped: port 1 read " & to_hstring(rdata1) severity failure;
        assert rdata2 = x"00000000"
            report "two ports swapped: port 2 read " & to_hstring(rdata2) severity failure;
        checks := checks + 4;

        -- 10. The read is asynchronous: a new address shows without a clock edge.
        wait until rising_edge(clk);
        wait for 2 ns;                 -- well away from any edge
        raddr1 <= to_addr(9);
        wait for 1 ns;
        assert rdata1 = pattern(9)
            report "asynchronous read: port 1 read " & to_hstring(rdata1) severity failure;
        raddr1 <= to_addr(10);
        wait for 1 ns;
        assert rdata1 = pattern(10)
            report "asynchronous read: port 1 read " & to_hstring(rdata1) severity failure;
        checks := checks + 2;

        report "tb_regfile: PASS (" & integer'image(checks) & " checks)";
        std.env.finish;
    end process stimulus;

end architecture sim;
