-- Self-checking testbench for rv_core. Run it with:  tools\sim.bat tb_rv_core
-- It prints PASS when every check held and stops at the first one that did not.
--
-- The core runs a 23-word program out of a small RAM model. The testbench checks
-- every field of every retire, the number of clock cycles each instruction takes,
-- the trap on the illegal word that ends the program, the reset, and the run input.
-- The words are from the assembler and the expected records from the ISS
-- (florv iss --trace) on the same program.
--
-- It is a test of the state machine: every state and every way from one to the
-- next. It does not try every instruction or every load and store offset.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.rv32i_pkg.all;

entity tb_rv_core is
    generic (
        READ_LATENCY : positive := 1
    );
end entity tb_rv_core;

architecture sim of tb_rv_core is

    constant CLK_PERIOD : time := 20 ns;  -- 50 MHz, the clock of the fabric

    constant RAM_WORDS : natural := 128;  -- 0x80000000 to 0x800001FF

    type word_array_t is array (natural range <>) of word_t;

    constant PROGRAM : word_array_t := (
        x"00500093",  -- 80000000  addi  x1, x0, 5
        x"FFD00113",  -- 80000004  addi  x2, x0, -3
        x"002081B3",  -- 80000008  add   x3, x1, x2
        x"00108013",  -- 8000000c  addi  x0, x1, 1        destination x0
        x"80000237",  -- 80000010  lui   x4, 0x80000
        x"10222023",  -- 80000014  sw    x2, 256(x4)
        x"10022283",  -- 80000018  lw    x5, 256(x4)
        x"10120123",  -- 8000001c  sb    x1, 258(x4)      byte 2 of the word
        x"10224303",  -- 80000020  lbu   x6, 258(x4)
        x"10221383",  -- 80000024  lh    x7, 258(x4)      upper half, negative
        x"10320603",  -- 80000028  lb    x12, 259(x4)     byte 3, negative
        x"10121223",  -- 8000002c  sh    x1, 260(x4)
        x"10425583",  -- 80000030  lhu   x11, 260(x4)
        x"00208663",  -- 80000034  beq   x1, x2, skip     not taken
        x"00209463",  -- 80000038  bne   x1, x2, skip     taken
        x"06300093",  -- 8000003c  addi  x1, x0, 99       jumped over
        x"0080046F",  -- 80000040  skip: jal x8, target
        x"06200093",  -- 80000044  addi  x1, x0, 98       jumped over
        x"00000497",  -- 80000048  target: auipc x9, 0
        x"00D48567",  -- 8000004c  jalr  x10, 13(x9)      to 80000055, bit 0 is cleared
        x"06100093",  -- 80000050  addi  x1, x0, 97       jumped over
        x"00000073",  -- 80000054  ecall                  retires and does nothing
        x"FFFFFFFF"   -- 80000058  illegal word: the core traps here
    );

    constant TRAP_PC   : word_t := x"80000058";
    constant TRAP_INSN : word_t := x"FFFFFFFF";

    -- One expected retire, with the fields of the retire group.
    type retire_t is record
        pc        : word_t;
        insn      : word_t;
        next_pc   : word_t;
        rd        : natural range 0 to 31;
        rd_wdata  : word_t;
        mem_addr  : word_t;
        mem_mask  : std_logic_vector(3 downto 0);
        mem_wdata : word_t;
        is_load   : std_logic;
        is_store  : std_logic;
    end record;

    type retire_array_t is array (natural range <>) of retire_t;

    constant Z : word_t := x"00000000";

    constant EXPECTED : retire_array_t := (
        --  pc           insn         next_pc      rd  rd_wdata     mem_addr     mask  mem_wdata   load store
        (x"80000000", x"00500093", x"80000004",  1, x"00000005", Z,           x"0", Z,           '0', '0'),
        (x"80000004", x"FFD00113", x"80000008",  2, x"FFFFFFFD", Z,           x"0", Z,           '0', '0'),
        (x"80000008", x"002081B3", x"8000000C",  3, x"00000002", Z,           x"0", Z,           '0', '0'),
        (x"8000000C", x"00108013", x"80000010",  0, Z,           Z,           x"0", Z,           '0', '0'),
        (x"80000010", x"80000237", x"80000014",  4, x"80000000", Z,           x"0", Z,           '0', '0'),
        (x"80000014", x"10222023", x"80000018",  0, Z,           x"80000100", x"F", x"FFFFFFFD", '0', '1'),
        (x"80000018", x"10022283", x"8000001C",  5, x"FFFFFFFD", x"80000100", x"F", Z,           '1', '0'),
        (x"8000001C", x"10120123", x"80000020",  0, Z,           x"80000102", x"1", x"00000005", '0', '1'),
        (x"80000020", x"10224303", x"80000024",  6, x"00000005", x"80000102", x"1", Z,           '1', '0'),
        (x"80000024", x"10221383", x"80000028",  7, x"FFFFFF05", x"80000102", x"3", Z,           '1', '0'),
        (x"80000028", x"10320603", x"8000002C", 12, x"FFFFFFFF", x"80000103", x"1", Z,           '1', '0'),
        (x"8000002C", x"10121223", x"80000030",  0, Z,           x"80000104", x"3", x"00000005", '0', '1'),
        (x"80000030", x"10425583", x"80000034", 11, x"00000005", x"80000104", x"3", Z,           '1', '0'),
        (x"80000034", x"00208663", x"80000038",  0, Z,           Z,           x"0", Z,           '0', '0'),
        (x"80000038", x"00209463", x"80000040",  0, Z,           Z,           x"0", Z,           '0', '0'),
        (x"80000040", x"0080046F", x"80000048",  8, x"80000044", Z,           x"0", Z,           '0', '0'),
        (x"80000048", x"00000497", x"8000004C",  9, x"80000048", Z,           x"0", Z,           '0', '0'),
        (x"8000004C", x"00D48567", x"80000054", 10, x"80000050", Z,           x"0", Z,           '0', '0'),
        (x"80000054", x"00000073", x"80000058",  0, Z,           Z,           x"0", Z,           '0', '0')
    );

    -- The two data words the program leaves behind, and their index in the RAM.
    constant DATA_INDEX_0 : natural := 64;           -- 0x80000100
    constant DATA_WORD_0  : word_t  := x"FF05FFFD";  -- sw fffffffd, then sb 05 into byte 2
    constant DATA_INDEX_1 : natural := 65;           -- 0x80000104
    constant DATA_WORD_1  : word_t  := x"00000005";  -- sh 0005 into the low half

    -- Clock cycles one instruction takes: fetch, S_EXEC, S_MEM for a load or a
    -- store, S_WB. A read takes READ_LATENCY + 1 cycles, a write one.
    function cycles_of(r : retire_t) return natural is
        variable n : natural := (READ_LATENCY + 1) + 1 + 1;
    begin
        if r.is_load = '1' then
            n := n + READ_LATENCY + 1;
        elsif r.is_store = '1' then
            n := n + 1;
        end if;
        return n;
    end function;

    -- From the retire before a trap to trap = '1': fetch, S_EXEC, and one more
    -- edge for the state to be S_TRAP.
    constant TRAP_CYCLES : natural := (READ_LATENCY + 1) + 1 + 1;

    function initial_ram return word_array_t is
        variable r : word_array_t(0 to RAM_WORDS - 1) := (others => (others => '0'));
    begin
        for i in PROGRAM'range loop
            r(i) := PROGRAM(i);
        end loop;
        return r;
    end function;

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

    signal ram : word_array_t(0 to RAM_WORDS - 1) := initial_ram;

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

    -- The RAM. It is stricter than a block RAM: the word read is on mem_rdata for
    -- one cycle only, READ_LATENCY edges after the access, and mem_rdata is 'X'
    -- at every other time. A core that takes the word too early or too late gets
    -- 'X' and fails the checks. It also checks how the core drives the port.
    ram_model : process (clk)
        variable index : natural range 0 to RAM_WORDS - 1;
    begin
        if rising_edge(clk) then
            for i in READ_LATENCY downto 2 loop
                read_pipe(i) <= read_pipe(i - 1);
            end loop;
            read_pipe(1) <= (others => 'X');

            if mem_en = '1' then
                assert mem_addr(31 downto 9) = x"80000" & "000"
                    report "memory port: address " & to_hstring(mem_addr) & " is outside the RAM"
                    severity failure;
                assert mem_addr(1 downto 0) = "00"
                    report "memory port: address " & to_hstring(mem_addr) & " is not a word address"
                    severity failure;

                index := to_integer(unsigned(mem_addr(8 downto 2)));
                if mem_we = '1' then
                    for lane in 0 to 3 loop
                        if mem_be(lane) = '1' then
                            ram(index)(8 * lane + 7 downto 8 * lane) <=
                                mem_wdata(8 * lane + 7 downto 8 * lane);
                        end if;
                    end loop;
                else
                    assert mem_be = "0000"
                        report "memory port: mem_be is " & to_hstring(mem_be) & " on a read"
                        severity failure;
                    read_pipe(1) <= ram(index);
                end if;
            end if;
        end if;
    end process ram_model;

    mem_rdata <= read_pipe(READ_LATENCY);

    stimulus : process

        variable checks : natural := 0;
        variable cycles : natural;

        procedure check_word(index : natural; field : string; got : word_t; want : word_t) is
        begin
            assert got = want
                report "retire " & integer'image(index) & ": " & field & " is " &
                       to_hstring(got) & ", expected " & to_hstring(want)
                severity failure;
            checks := checks + 1;
        end procedure;

        procedure check_bit(index : natural; field : string; got : std_logic; want : std_logic) is
        begin
            assert got = want
                report "retire " & integer'image(index) & ": " & field & " is " &
                       std_logic'image(got) & ", expected " & std_logic'image(want)
                severity failure;
            checks := checks + 1;
        end procedure;

        -- Waits for the next retire and compares it with EXPECTED(index). With
        -- timed, the retire must come exactly cycles_of clock cycles after the
        -- one before it; that needs run high all the way from that retire.
        procedure expect_retire(index : natural; timed : boolean) is
            constant e : retire_t := EXPECTED(index);
            variable n : natural  := 0;
        begin
            loop
                wait until rising_edge(clk);
                n := n + 1;
                exit when retire_valid = '1';
                assert trap = '0'
                    report "retire " & integer'image(index) & ": the core trapped instead"
                    severity failure;
                assert n < 50
                    report "retire " & integer'image(index) & ": nothing retired in 50 cycles"
                    severity failure;
            end loop;

            check_word(index, "pc", retire_pc, e.pc);
            check_word(index, "insn", retire_insn, e.insn);
            check_word(index, "next_pc", retire_next_pc, e.next_pc);
            assert to_integer(unsigned(retire_rd)) = e.rd
                report "retire " & integer'image(index) & ": rd is " &
                       integer'image(to_integer(unsigned(retire_rd))) & ", expected " &
                       integer'image(e.rd)
                severity failure;
            checks := checks + 1;
            check_word(index, "rd_wdata", retire_rd_wdata, e.rd_wdata);
            check_word(index, "mem_addr", retire_mem_addr, e.mem_addr);
            assert retire_mem_mask = e.mem_mask
                report "retire " & integer'image(index) & ": mem_mask is " &
                       to_hstring(retire_mem_mask) & ", expected " & to_hstring(e.mem_mask)
                severity failure;
            checks := checks + 1;
            check_word(index, "mem_wdata", retire_mem_wdata, e.mem_wdata);
            check_bit(index, "is_load", retire_is_load, e.is_load);
            check_bit(index, "is_store", retire_is_store, e.is_store);
            check_bit(index, "trap", trap, '0');

            if timed then
                assert n = cycles_of(e)
                    report "retire " & integer'image(index) & ": took " & integer'image(n) &
                           " cycles, expected " & integer'image(cycles_of(e))
                    severity failure;
                checks := checks + 1;
            end if;
        end procedure;

        -- For count clock cycles: no memory access, nothing retires, and trap
        -- stays at trap_level.
        procedure expect_quiet(count : natural; trap_level : std_logic; what : string) is
        begin
            for i in 1 to count loop
                wait until rising_edge(clk);
                assert mem_en = '0'
                    report what & ": the core made a memory access" severity failure;
                assert retire_valid = '0'
                    report what & ": an instruction retired" severity failure;
                assert trap = trap_level
                    report what & ": trap is " & std_logic'image(trap) severity failure;
                checks := checks + 3;
            end loop;
        end procedure;

        -- Waits for trap = '1' and returns the clock cycles it took. Nothing may
        -- retire on the way.
        procedure wait_for_trap(taken : out natural) is
            variable n : natural := 0;
        begin
            loop
                wait until rising_edge(clk);
                n := n + 1;
                assert retire_valid = '0'
                    report "the illegal word retired instead of trapping" severity failure;
                exit when trap = '1';
                assert n < 50
                    report "no trap in 50 cycles after the last instruction" severity failure;
            end loop;
            check_word(EXPECTED'length, "pc of the trap", retire_pc, TRAP_PC);
            check_word(EXPECTED'length, "insn of the trap", retire_insn, TRAP_INSN);
            taken := n;
        end procedure;

    begin
        -- 1. In reset the core does nothing, even with run high.
        rstn <= '0';
        run  <= '1';
        expect_quiet(3, '0', "in reset");
        wait until falling_edge(clk);
        rstn <= '1';

        -- 2. The whole program: every retire, and how many cycles each took.
        expect_retire(0, false);
        for i in 1 to EXPECTED'high loop
            expect_retire(i, true);
        end loop;

        -- 3. The illegal word traps: nothing retires, and the core stays stopped.
        wait_for_trap(cycles);
        assert cycles = TRAP_CYCLES
            report "the trap took " & integer'image(cycles) & " cycles, expected " &
                   integer'image(TRAP_CYCLES)
            severity failure;
        checks := checks + 1;
        expect_quiet(20, '1', "after the trap");

        -- 4. The stores reached the right bytes of the RAM.
        assert ram(DATA_INDEX_0) = DATA_WORD_0
            report "RAM word at 80000100 is " & to_hstring(ram(DATA_INDEX_0)) &
                   ", expected " & to_hstring(DATA_WORD_0)
            severity failure;
        assert ram(DATA_INDEX_1) = DATA_WORD_1
            report "RAM word at 80000104 is " & to_hstring(ram(DATA_INDEX_1)) &
                   ", expected " & to_hstring(DATA_WORD_1)
            severity failure;
        checks := checks + 2;

        -- 5. One clock edge of reset ends the trap. With run low the core then
        --    does not start.
        wait until falling_edge(clk);
        rstn <= '0';
        run  <= '0';
        wait until falling_edge(clk);
        rstn <= '1';
        expect_quiet(10, '0', "run low after reset");

        -- 6. run high: the program starts again from RESET_PC. run is then taken
        --    low while instruction 2 is under way: that instruction completes
        --    and the core stops before the next one.
        wait until falling_edge(clk);
        run <= '1';
        expect_retire(0, false);
        expect_retire(1, false);
        wait until rising_edge(clk);
        wait until rising_edge(clk);   -- the fetch of instruction 2 has been issued
        wait until falling_edge(clk);
        run <= '0';
        expect_retire(2, false);
        expect_quiet(20, '0', "run low between two instructions");

        -- 7. run high again: the rest of the program, to the trap.
        wait until falling_edge(clk);
        run <= '1';
        for i in 3 to EXPECTED'high loop
            expect_retire(i, false);
        end loop;
        wait_for_trap(cycles);

        report "tb_rv_core: PASS (" & integer'image(checks) & " checks)";
        std.env.finish;
    end process stimulus;

end architecture sim;
