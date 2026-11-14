-- Whole-program testbench for rv_core. It runs a compiled program, not a table
-- of words: the RAM is filled from the hex file that "florv elf2hex" writes, the
-- same image the ARM will load into the block RAM on the board.
--
--     build\florv.exe elf2hex tests\build\fib_loop.elf tests\build\fib_loop.hex
--     tools\sim.bat tb_core "HEX_FILE=C:/work/florv/tests/build/fib_loop.hex" "TOHOST_ADDR=800000c0"
--
-- TOHOST_ADDR is the address of the program's tohost symbol, as the 8 hex digits
-- riscv64-unknown-elf-nm prints; it differs from program to program. It is a
-- string because xelab cannot set a std_logic_vector generic of a VHDL top from
-- the command line.
--
-- The run ends in one of four ways:
--   PASS      the core retired a word store of 1 to TOHOST_ADDR
--   failure   it stored another non-zero value there (the message has tohost=...)
--   failure   the core raised trap
--   failure   MAX_CYCLES clock cycles went by without a tohost store
--
-- The testbench does not check the instructions one by one; tb_rv_core and
-- tb_rv_core_insns do that. It checks that a whole program reaches its end.
--
-- With the generic REGS_FILE set, a run that passes also writes x0 to x31 to that
-- file, in the format of docs/regs-format.md. "florv iss prog.elf --regs FILE"
-- writes the same file from the ISS, and the two must be equal byte for byte:
--
--     tools\sim.bat tb_core "HEX_FILE=..." "TOHOST_ADDR=800000c0" "REGS_FILE=C:/work/florv/tests/build/fib_loop.rtl.regs.txt"
--     build\florv.exe iss tests\build\fib_loop.elf --regs tests\build\fib_loop.iss.regs.txt
--     fc /b tests\build\fib_loop.rtl.regs.txt tests\build\fib_loop.iss.regs.txt

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use std.textio.all;

use work.rv32i_pkg.all;
use work.regfile_pkg.all;

entity tb_core is
    generic (
        HEX_FILE     : string   := "";
        TOHOST_ADDR  : string   := "80000040";
        REGS_FILE    : string   := "";  -- empty: no register dump
        READ_LATENCY : positive := 1;
        MAX_CYCLES   : positive := 1000000
    );
end entity tb_core;

architecture sim of tb_core is

    constant CLK_PERIOD : time := 20 ns;  -- 50 MHz, the clock of the fabric

    constant RAM_WORDS : natural := 16384;  -- 64 KiB, 0x80000000 to 0x8000FFFF

    type word_array_t is array (natural range <>) of word_t;

    -- Reads the hex file: one word of 8 hex digits per line, the first line being
    -- the word at 0x80000000, exactly RAM_WORDS lines.
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
            report "tb_core: no hex file given; set the generic HEX_FILE"
            severity failure;

        file_open(status, f, path, read_mode);
        assert status = open_ok
            report "tb_core: cannot open the hex file " & path
            severity failure;

        while not endfile(f) loop
            readline(f, l);
            assert count < RAM_WORDS
                report "tb_core: " & path & " has more than " & integer'image(RAM_WORDS) & " lines"
                severity failure;
            hread(l, word, good);
            assert good
                report "tb_core: " & path & " line " & integer'image(count + 1) &
                       " is not a word of 8 hex digits"
                severity failure;
            r(count) := word;
            count    := count + 1;
        end loop;
        file_close(f);

        assert count = RAM_WORDS
            report "tb_core: " & path & " has " & integer'image(count) & " lines, expected " &
                   integer'image(RAM_WORDS)
            severity failure;
        return r;
    end function;

    -- The generic TOHOST_ADDR as a word.
    impure function tohost_word return word_t is
        variable l    : line;
        variable word : word_t;
        variable good : boolean;
    begin
        write(l, TOHOST_ADDR);
        hread(l, word, good);
        assert good and TOHOST_ADDR'length = 8
            report "tb_core: TOHOST_ADDR is '" & TOHOST_ADDR & "', expected 8 hex digits"
            severity failure;
        deallocate(l);
        return word;
    end function;

    constant TOHOST : word_t := tohost_word;


    procedure dump_regs(path : in string; regs : in reg_array_t) is
        type char_file_t is file of character;
        file f          : char_file_t;
        variable status : file_open_status;

        constant DIGITS : string(1 to 16) := "0123456789abcdef";

        procedure put(s : in string) is
        begin
            for i in s'range loop
                write(f, s(i));
            end loop;
        end procedure;
    begin
        if path'length = 0 then
            return;  -- no file asked for
        end if;

        file_open(status, f, path, write_mode);
        assert status = open_ok
            report "tb_core: cannot write the register file " & path
            severity failure;

        for r in regs'range loop
            put("x" & integer'image(r) & " ");
            for nibble in 7 downto 0 loop
                write(f, DIGITS(to_integer(unsigned(regs(r)(4 * nibble + 3 downto 4 * nibble))) + 1));
            end loop;
            write(f, LF);
        end loop;
        file_close(f);
    end procedure;

    signal clk  : std_logic := '0';
    signal rstn : std_logic := '0';
    signal run  : std_logic := '0';

    signal mem_en    : std_logic;
    signal mem_we    : std_logic;
    signal mem_addr  : word_t;
    signal mem_be    : std_logic_vector(3 downto 0);
    signal mem_wdata : word_t;
    signal mem_rdata : word_t;

    signal retire_valid     : std_logic;
    signal retire_pc        : word_t;
    signal retire_insn      : word_t;
    signal retire_next_pc   : word_t;
    signal retire_rd        : reg_addr_t;
    signal retire_rd_wdata  : word_t;
    signal retire_mem_addr  : word_t;
    signal retire_mem_mask  : std_logic_vector(3 downto 0);
    signal retire_mem_wdata : word_t;
    signal retire_is_load   : std_logic;
    signal retire_is_store  : std_logic;
    signal trap             : std_logic;

    -- The read data on its way out: read_pipe(READ_LATENCY) is mem_rdata.
    signal read_pipe : word_array_t(1 to READ_LATENCY) := (others => (others => 'X'));

begin

    clk <= not clk after CLK_PERIOD / 2;

    dut : entity work.rv_core
        generic map (
            RESET_PC     => x"80000000",
            READ_LATENCY => READ_LATENCY
        )
        port map (
            clk              => clk,
            rstn             => rstn,
            run              => run,
            mem_en           => mem_en,
            mem_we           => mem_we,
            mem_addr         => mem_addr,
            mem_be           => mem_be,
            mem_wdata        => mem_wdata,
            mem_rdata        => mem_rdata,
            retire_valid     => retire_valid,
            retire_pc        => retire_pc,
            retire_insn      => retire_insn,
            retire_next_pc   => retire_next_pc,
            retire_rd        => retire_rd,
            retire_rd_wdata  => retire_rd_wdata,
            retire_mem_addr  => retire_mem_addr,
            retire_mem_mask  => retire_mem_mask,
            retire_mem_wdata => retire_mem_wdata,
            retire_is_load   => retire_is_load,
            retire_is_store  => retire_is_store,
            trap             => trap
        );

    -- The RAM, the same model as in tb_rv_core but 64 KiB and filled from the hex
    -- file. The word read is on mem_rdata for one cycle only, READ_LATENCY edges
    -- after the access, and mem_rdata is 'X' at every other time.
    --
    -- The real RAM drops the high address bits, so an address outside it lands on
    -- a word inside it. The ISS traps on such an address instead. A program that
    -- leaves the RAM would therefore behave differently in the two, so here it is
    -- a failure.
    ram_model : process (clk)
        variable ram   : word_array_t(0 to RAM_WORDS - 1) := load_hex(HEX_FILE);
        variable index : natural range 0 to RAM_WORDS - 1;
    begin
        if rising_edge(clk) then
            for i in READ_LATENCY downto 2 loop
                read_pipe(i) <= read_pipe(i - 1);
            end loop;
            read_pipe(1) <= (others => 'X');

            if mem_en = '1' then
                assert mem_addr(31 downto 16) = x"8000"
                    report "tb_core: address " & to_hstring(mem_addr) & " is outside the RAM"
                    severity failure;
                assert mem_addr(1 downto 0) = "00"
                    report "tb_core: address " & to_hstring(mem_addr) & " is not a word address"
                    severity failure;

                index := to_integer(unsigned(mem_addr(15 downto 2)));
                if mem_we = '1' then
                    for lane in 0 to 3 loop
                        if mem_be(lane) = '1' then
                            ram(index)(8 * lane + 7 downto 8 * lane) :=
                                mem_wdata(8 * lane + 7 downto 8 * lane);
                        end if;
                    end loop;
                else
                    read_pipe(1) <= ram(index);
                end if;
            end if;
        end if;
    end process ram_model;

    mem_rdata <= read_pipe(READ_LATENCY);

    -- Reset for four cycles, then let the core run to the end of the program.
    stimulus : process
    begin
        rstn <= '0';
        run  <= '0';
        for i in 1 to 4 loop
            wait until falling_edge(clk);
        end loop;
        rstn <= '1';
        run  <= '1';
        wait;
    end process stimulus;

    -- Watches the retire group and ends the run. The tohost rule is the one of
    -- the ISS: a word store of a non-zero value to the tohost address, seen when
    -- the store retires.
    monitor : process (clk)
        variable cycles  : natural := 0;
        variable retires : natural := 0;
        variable last_pc : word_t  := (others => '0');
    begin
        if rising_edge(clk) and rstn = '1' then
            cycles := cycles + 1;

            assert trap /= '1'
                report "tb_core: the core trapped after " & integer'image(retires) &
                       " retires; the last one was at pc " & to_hstring(last_pc)
                severity failure;

            if retire_valid = '1' then
                retires := retires + 1;
                last_pc := retire_pc;

                if retire_is_store = '1' and retire_mem_addr = TOHOST and
                   retire_mem_mask = "1111" and retire_mem_wdata /= x"00000000" then
                    assert retire_mem_wdata = x"00000001"
                        report "tb_core: tohost=" & to_hstring(retire_mem_wdata) & " (hex) after " &
                               integer'image(retires) & " retires; the program reports a failure"
                        severity failure;
                    -- The registers are read inside the core's register file. They
                    -- are final here: the instruction retiring now is a store, which
                    -- writes no register, and every earlier write is already in.
                    -- The call is not inside "if REGS_FILE'length > 0": with the
                    -- generic empty, xelab 2025.2 crashes on an external name in a
                    -- branch it knows is never taken. dump_regs tests the name itself.
                    dump_regs(REGS_FILE, << signal dut.u_regfile.regs : reg_array_t >>);
                    report "tb_core: PASS, tohost=1 after " & integer'image(retires) &
                           " retires, " & integer'image(cycles) & " cycles";
                    std.env.finish;
                end if;
            end if;

            assert cycles < MAX_CYCLES
                report "tb_core: no tohost store in " & integer'image(MAX_CYCLES) & " cycles (" &
                       integer'image(retires) & " retires, the last one at pc " &
                       to_hstring(last_pc) & ")"
                severity failure;
        end if;
    end process monitor;

end architecture sim;
