-- Testbench for the whole rv_rig block: the AXI4-Lite registers, the core inside
-- it and the status logic, as docs/regmap.md defines them. It plays the ARM: it
-- reads and writes the registers over the bus and follows the sequence "How the
-- ARM runs a program" of that document. The program RAM is a model on the block's
-- memory port, filled from the hex file "florv elf2hex" writes.
--
--     tools\sim.bat tb_rv_rig "HEX_FILE=C:/work/florv/tests/build/fib_loop.hex" "TOHOST_ADDR=800000c0" "EXPECT_RETIRES=286" "EXPECT_LAST_PC=80000080"
--
-- TOHOST_ADDR is the address of the program's tohost symbol (from nm).
-- EXPECT_RETIRES is the "retired:" line of "florv iss" for the same program and
-- EXPECT_LAST_PC the address of its store to tohost (the pc of the last line of
-- the ISS trace). EXPECT_STATUS is the STATUS register at the end: 3 (RUNNING and
-- STALLED) for a program that ends in its final loop, 4 (TRAPPED) for one that
-- traps. EXPECT_TOHOST is the tohost word in the RAM at the end: 1 for a program
-- that passed, 0 for one that never stored to it.
--
-- On the board the ARM loads the RAM through its other port. Here the RAM is
-- already filled when the run starts, and the testbench checks that the core
-- leaves it alone until CTRL releases it.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use std.textio.all;

entity tb_rv_rig is
    generic (
        HEX_FILE       : string  := "";
        TOHOST_ADDR    : string  := "80000040";
        EXPECT_TOHOST  : natural := 1;
        EXPECT_RETIRES : natural := 0;
        EXPECT_LAST_PC : string  := "00000000";
        EXPECT_STATUS  : natural := 3;
        MAX_POLLS      : positive := 100000  -- reads of STATUS before giving up
    );
end entity tb_rv_rig;

architecture sim of tb_rv_rig is

    constant CLK_PERIOD : time := 20 ns;

    constant RAM_WORDS : natural := 16384;  -- 64 KiB

    subtype word_t is std_logic_vector(31 downto 0);
    type word_array_t is array (natural range <>) of word_t;

    -- Register offsets and bits, as in docs/regmap.md.
    constant REG_ID           : natural := 16#00#;
    constant REG_SCRATCH      : natural := 16#04#;
    constant REG_CTRL         : natural := 16#08#;
    constant REG_STATUS       : natural := 16#0C#;
    constant REG_LAST_PC      : natural := 16#10#;
    constant REG_RETIRE_COUNT : natural := 16#14#;
    constant REG_TRACE_HEAD   : natural := 16#18#;
    constant REG_TRACE_TAIL   : natural := 16#1C#;

    constant CTRL_RUN   : word_t := x"00000001";
    constant CTRL_RESET : word_t := x"00000002";
    constant CTRL_PAUSE : word_t := x"00000000";

    constant STATUS_RUNNING : natural := 0;
    constant STATUS_STALLED : natural := 1;
    constant STATUS_TRAPPED : natural := 2;

    -- The hex file: one word of 8 hex digits per line, RAM_WORDS lines.
    impure function load_hex(path : string) return word_array_t is
        file f          : text;
        variable status : file_open_status;
        variable l      : line;
        variable word   : word_t;
        variable good   : boolean;
        variable count  : natural := 0;
        variable r      : word_array_t(0 to RAM_WORDS - 1) := (others => (others => '0'));
    begin
        assert path'length > 0
            report "tb_rv_rig: no hex file given; set the generic HEX_FILE"
            severity failure;
        file_open(status, f, path, read_mode);
        assert status = open_ok
            report "tb_rv_rig: cannot open the hex file " & path
            severity failure;
        while not endfile(f) loop
            readline(f, l);
            assert count < RAM_WORDS
                report "tb_rv_rig: " & path & " has more than " & integer'image(RAM_WORDS) & " lines"
                severity failure;
            hread(l, word, good);
            assert good
                report "tb_rv_rig: " & path & " line " & integer'image(count + 1) &
                       " is not a word of 8 hex digits"
                severity failure;
            r(count) := word;
            count    := count + 1;
        end loop;
        file_close(f);
        assert count = RAM_WORDS
            report "tb_rv_rig: " & path & " has " & integer'image(count) & " lines, expected " &
                   integer'image(RAM_WORDS)
            severity failure;
        return r;
    end function;

    -- A generic of 8 hex digits as a word.
    impure function hex_word(text : string) return word_t is
        variable l    : line;
        variable word : word_t;
        variable good : boolean;
    begin
        write(l, text);
        hread(l, word, good);
        assert good and text'length = 8
            report "tb_rv_rig: '" & text & "' is not 8 hex digits"
            severity failure;
        deallocate(l);
        return word;
    end function;

    signal clk     : std_logic := '0';
    signal aresetn : std_logic := '0';

    signal awaddr  : std_logic_vector(4 downto 0) := (others => '0');
    signal awvalid : std_logic := '0';
    signal awready : std_logic;
    signal wdata   : word_t := (others => '0');
    signal wstrb   : std_logic_vector(3 downto 0) := "0000";
    signal wvalid  : std_logic := '0';
    signal wready  : std_logic;
    signal bresp   : std_logic_vector(1 downto 0);
    signal bvalid  : std_logic;
    signal bready  : std_logic := '0';
    signal araddr  : std_logic_vector(4 downto 0) := (others => '0');
    signal arvalid : std_logic := '0';
    signal arready : std_logic;
    signal rdata   : word_t;
    signal rresp   : std_logic_vector(1 downto 0);
    signal rvalid  : std_logic;
    signal rready  : std_logic := '0';

    signal mem_clk  : std_logic;
    signal mem_rst  : std_logic;
    signal mem_en   : std_logic;
    signal mem_we   : std_logic_vector(3 downto 0);
    signal mem_addr : word_t;
    signal mem_din  : word_t;
    signal mem_dout : word_t := (others => 'X');

    -- Counted by the RAM model, read by the main process.
    signal accesses : natural := 0;

    -- The tohost word of the RAM model, as the ARM would read it through port A.
    signal tohost_word : word_t := (others => '0');

begin

    clk <= not clk after CLK_PERIOD / 2;

    dut : entity work.rv_rig
        port map (
            mem_clk         => mem_clk,
            mem_rst         => mem_rst,
            mem_en          => mem_en,
            mem_we          => mem_we,
            mem_addr        => mem_addr,
            mem_din         => mem_din,
            mem_dout        => mem_dout,
            s00_axi_aclk    => clk,
            s00_axi_aresetn => aresetn,
            s00_axi_awaddr  => awaddr,
            s00_axi_awprot  => "000",
            s00_axi_awvalid => awvalid,
            s00_axi_awready => awready,
            s00_axi_wdata   => wdata,
            s00_axi_wstrb   => wstrb,
            s00_axi_wvalid  => wvalid,
            s00_axi_wready  => wready,
            s00_axi_bresp   => bresp,
            s00_axi_bvalid  => bvalid,
            s00_axi_bready  => bready,
            s00_axi_araddr  => araddr,
            s00_axi_arprot  => "000",
            s00_axi_arvalid => arvalid,
            s00_axi_arready => arready,
            s00_axi_rdata   => rdata,
            s00_axi_rresp   => rresp,
            s00_axi_rvalid  => rvalid,
            s00_axi_rready  => rready
        );

    -- Port B of the program RAM as the block sees it: clocked by mem_clk, one
    -- clock edge from the access to the data, byte write enables, and only the
    -- low 16 address bits used. The data is 'X' except in the cycle after a read.
    ram_model : process (mem_clk)
        variable ram    : word_array_t(0 to RAM_WORDS - 1);
        variable loaded : boolean := false;
        variable index  : natural range 0 to RAM_WORDS - 1;
        variable tohost : word_t;
    begin
        if rising_edge(mem_clk) then
            -- Read at the first edge, not in the declaration: xelab evaluates
            -- declarations itself and ignores a failed assertion there.
            if not loaded then
                ram    := load_hex(HEX_FILE);
                loaded := true;
                tohost := hex_word(TOHOST_ADDR);
                assert tohost(31 downto 16) = x"8000" and tohost(1 downto 0) = "00"
                    report "tb_rv_rig: TOHOST_ADDR " & TOHOST_ADDR & " is not a word of the RAM"
                    severity failure;
            end if;

            mem_dout <= (others => 'X');
            if mem_en = '1' then
                accesses <= accesses + 1;
                assert mem_addr(31 downto 16) = x"8000"
                    report "tb_rv_rig: address " & to_hstring(mem_addr) & " is outside the RAM"
                    severity failure;
                assert mem_addr(1 downto 0) = "00"
                    report "tb_rv_rig: address " & to_hstring(mem_addr) & " is not a word address"
                    severity failure;

                index := to_integer(unsigned(mem_addr(15 downto 2)));
                if mem_we = "0000" then
                    mem_dout <= ram(index);
                else
                    for lane in 0 to 3 loop
                        if mem_we(lane) = '1' then
                            ram(index)(8 * lane + 7 downto 8 * lane) :=
                                mem_din(8 * lane + 7 downto 8 * lane);
                        end if;
                    end loop;
                end if;
            else
                assert mem_we = "0000"
                    report "tb_rv_rig: mem_we is set without mem_en"
                    severity failure;
            end if;
            tohost_word <= ram(to_integer(unsigned(tohost(15 downto 2))));
        end if;
    end process ram_model;

    -- The ARM.
    main : process
        variable value  : word_t;
        variable polls  : natural := 0;
        variable checks : natural := 0;
        variable before : natural;

        -- One AXI4-Lite write, address and data in the same cycle.
        procedure axi_write(offset : in natural; data : in word_t;
                            strobes : in std_logic_vector(3 downto 0) := "1111") is
        begin
            wait until falling_edge(clk);
            awaddr  <= std_logic_vector(to_unsigned(offset, 5));
            wdata   <= data;
            wstrb   <= strobes;
            awvalid <= '1';
            wvalid  <= '1';
            bready  <= '1';
            loop
                wait until rising_edge(clk);
                exit when awready = '1' and wready = '1';
            end loop;
            wait until falling_edge(clk);
            awvalid <= '0';
            wvalid  <= '0';
            while bvalid /= '1' loop
                wait until falling_edge(clk);
            end loop;
            assert bresp = "00"
                report "tb_rv_rig: write to offset " & integer'image(offset) & " not answered OKAY"
                severity failure;
            wait until falling_edge(clk);
            bready <= '0';
        end procedure;

        -- One AXI4-Lite read.
        procedure axi_read(offset : in natural; data : out word_t) is
        begin
            wait until falling_edge(clk);
            araddr  <= std_logic_vector(to_unsigned(offset, 5));
            arvalid <= '1';
            rready  <= '1';
            loop
                wait until rising_edge(clk);
                exit when arready = '1';
            end loop;
            wait until falling_edge(clk);
            arvalid <= '0';
            while rvalid /= '1' loop
                wait until falling_edge(clk);
            end loop;
            assert rresp = "00"
                report "tb_rv_rig: read of offset " & integer'image(offset) & " not answered OKAY"
                severity failure;
            data := rdata;
            wait until falling_edge(clk);
            rready <= '0';
        end procedure;

        -- Reads a register and compares it.
        procedure expect(offset : in natural; wanted : in word_t; what : in string) is
            variable got : word_t;
        begin
            axi_read(offset, got);
            assert got = wanted
                report "tb_rv_rig: " & what & " is " & to_hstring(got) & ", expected " &
                       to_hstring(wanted)
                severity failure;
            checks := checks + 1;
        end procedure;

        procedure idle(cycles : in positive) is
        begin
            for i in 1 to cycles loop
                wait until falling_edge(clk);
            end loop;
        end procedure;
    begin
        idle(4);
        aresetn <= '1';
        idle(3);

        -- After power-up: the right revision, the core held in reset, nothing counted.
        expect(REG_ID,           x"52560002", "ID");
        expect(REG_SCRATCH,      x"00000000", "SCRATCH after power-up");
        expect(REG_CTRL,         CTRL_RESET,  "CTRL after power-up");
        expect(REG_STATUS,       x"00000000", "STATUS after power-up");
        expect(REG_LAST_PC,      x"00000000", "LAST_PC after power-up");
        expect(REG_RETIRE_COUNT, x"00000000", "RETIRE_COUNT after power-up");
        expect(REG_TRACE_HEAD,   x"00000000", "TRACE_HEAD");
        expect(REG_TRACE_TAIL,   x"00000000", "TRACE_TAIL");

        -- The loopback register.
        axi_write(REG_SCRATCH, x"A5A55A5A");
        expect(REG_SCRATCH, x"A5A55A5A", "SCRATCH");
        axi_write(REG_SCRATCH, x"11223344", "0101");
        expect(REG_SCRATCH, x"A5225A44", "SCRATCH after a write of bytes 0 and 2");

        -- Read-only and reserved registers ignore writes.
        axi_write(REG_ID, x"FFFFFFFF");
        axi_write(REG_STATUS, x"FFFFFFFF");
        axi_write(REG_LAST_PC, x"FFFFFFFF");
        axi_write(REG_RETIRE_COUNT, x"FFFFFFFF");
        axi_write(REG_TRACE_HEAD, x"FFFFFFFF");
        axi_write(REG_TRACE_TAIL, x"FFFFFFFF");
        expect(REG_ID,           x"52560002", "ID after a write");
        expect(REG_STATUS,       x"00000000", "STATUS after a write");
        expect(REG_LAST_PC,      x"00000000", "LAST_PC after a write");
        expect(REG_RETIRE_COUNT, x"00000000", "RETIRE_COUNT after a write");
        expect(REG_TRACE_HEAD,   x"00000000", "TRACE_HEAD after a write");
        expect(REG_TRACE_TAIL,   x"00000000", "TRACE_TAIL after a write");

        -- Held in reset, the core has not touched the RAM in all this time, and
        -- RUN alone does not start it: RESET wins.
        axi_write(REG_CTRL, x"00000003");
        expect(REG_CTRL,   x"00000003", "CTRL with RUN and RESET");
        expect(REG_STATUS, x"00000000", "STATUS with RUN and RESET");
        -- Both bits are in byte 0: a write that leaves byte 0 out changes nothing.
        axi_write(REG_CTRL, x"00000000", "1110");
        expect(REG_CTRL, x"00000003", "CTRL after a write without byte 0");
        idle(20);
        assert accesses = 0
            report "tb_rv_rig: the core accessed the RAM while held in reset"
            severity failure;

        -- Out of reset but not running: still no access.
        axi_write(REG_CTRL, CTRL_PAUSE);
        expect(REG_STATUS, x"00000000", "STATUS out of reset without RUN");
        idle(20);
        assert accesses = 0
            report "tb_rv_rig: the core accessed the RAM without RUN"
            severity failure;

        -- Start the program and wait until it stalls in its final loop or traps.
        axi_write(REG_CTRL, CTRL_RUN);
        loop
            axi_read(REG_STATUS, value);
            exit when value(STATUS_STALLED) = '1' or value(STATUS_TRAPPED) = '1';
            assert value = x"00000001"
                report "tb_rv_rig: STATUS is " & to_hstring(value) & " while the program runs"
                severity failure;
            polls := polls + 1;
            assert polls < MAX_POLLS
                report "tb_rv_rig: neither STALLED nor TRAPPED after " &
                       integer'image(MAX_POLLS) & " reads of STATUS"
                severity failure;
        end loop;

        -- The result. It is final: read twice, some cycles apart.
        for pass in 1 to 2 loop
            expect(REG_STATUS, std_logic_vector(to_unsigned(EXPECT_STATUS, 32)), "STATUS at the end");
            expect(REG_LAST_PC, hex_word(EXPECT_LAST_PC), "LAST_PC at the end");
            expect(REG_RETIRE_COUNT, std_logic_vector(to_unsigned(EXPECT_RETIRES, 32)),
                   "RETIRE_COUNT at the end");
            idle(50);
        end loop;

        -- The store to tohost reached the RAM.
        assert tohost_word = std_logic_vector(to_unsigned(EXPECT_TOHOST, 32))
            report "tb_rv_rig: the tohost word is " & to_hstring(tohost_word) & ", expected " &
                   to_hstring(std_logic_vector(to_unsigned(EXPECT_TOHOST, 32)))
            severity failure;
        checks := checks + 1;

        -- RUN = 0 stops the core; the counters keep their values.
        axi_write(REG_CTRL, CTRL_PAUSE);
        idle(10);  -- the instruction in flight finishes
        before := accesses;
        idle(20);
        assert accesses = before
            report "tb_rv_rig: the core accessed the RAM after RUN was cleared"
            severity failure;
        axi_read(REG_STATUS, value);
        assert value(STATUS_RUNNING) = '0'
            report "tb_rv_rig: RUNNING is still 1 after RUN was cleared"
            severity failure;
        expect(REG_LAST_PC, hex_word(EXPECT_LAST_PC), "LAST_PC with RUN cleared");
        expect(REG_RETIRE_COUNT, std_logic_vector(to_unsigned(EXPECT_RETIRES, 32)),
               "RETIRE_COUNT with RUN cleared");

        -- RESET clears everything about the core. SCRATCH is not part of it.
        axi_write(REG_CTRL, CTRL_RESET);
        expect(REG_STATUS,       x"00000000", "STATUS after RESET");
        expect(REG_LAST_PC,      x"00000000", "LAST_PC after RESET");
        expect(REG_RETIRE_COUNT, x"00000000", "RETIRE_COUNT after RESET");
        expect(REG_SCRATCH,      x"A5225A44", "SCRATCH after RESET");

        report "tb_rv_rig: PASS, tohost=" & integer'image(EXPECT_TOHOST) &
               " status=" & integer'image(EXPECT_STATUS) &
               " last_pc=" & EXPECT_LAST_PC & " retire_count=" & integer'image(EXPECT_RETIRES) &
               " (" & integer'image(checks) & " register checks, " & integer'image(polls) &
               " polls)";
        std.env.finish;
    end process main;

end architecture sim;
