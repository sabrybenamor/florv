library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.rv32i_pkg.all;

entity trace_logger is
    generic (
        TRACE_FILE : string := ""  -- empty: no trace
    );
    port (
        clk              : in std_logic;
        retire_valid     : in std_logic;
        retire_pc        : in word_t;
        retire_insn      : in word_t;
        retire_next_pc   : in word_t;
        retire_rd        : in reg_addr_t;
        retire_rd_wdata  : in word_t;
        retire_mem_addr  : in word_t;
        retire_mem_mask  : in std_logic_vector(3 downto 0);
        retire_mem_wdata : in word_t;
        retire_is_load   : in std_logic;
        retire_is_store  : in std_logic
    );
end entity trace_logger;

architecture sim of trace_logger is

    constant HEADER : string := "order,pc,insn,next_pc,rd,rd_wdata,mem_addr,mem_mask,mem_wdata";

    -- A vector of 4, 8, ... bits as lower-case hex digits, the leftmost bits first.
    -- A digit with a bit that is not '0' or '1' is written as 'x', so an unknown
    -- value shows up in the comparison instead of passing as a 0.
    function hex(v : std_logic_vector) return string is
        constant DIGITS : string(1 to 16) := "0123456789abcdef";
        constant COUNT  : natural := v'length / 4;
        variable bits   : std_logic_vector(v'length - 1 downto 0) := v;
        variable nibble : std_logic_vector(3 downto 0);
        variable text   : string(1 to COUNT);
    begin
        for i in 1 to COUNT loop
            nibble := bits(4 * (COUNT - i) + 3 downto 4 * (COUNT - i));
            if is_x(nibble) then
                text(i) := 'x';
            else
                text(i) := DIGITS(to_integer(unsigned(nibble)) + 1);
            end if;
        end loop;
        return text;
    end function;

    -- A number in decimal without the leading space integer'image never writes
    -- for a natural, named so the calls below read like the column list.
    function dec(n : natural) return string is
    begin
        return integer'image(n);
    end function;

begin

    logger : process (clk)
        -- A file of character, not of text: writeline would end each line the
        -- way the operating system does, and the format wants a line feed alone.
        type char_file_t is file of character;
        file f : char_file_t;

        variable status : file_open_status;
        variable opened : boolean := false;
        variable order  : natural := 0;
        variable rd     : natural range 0 to 31;

        procedure put(s : in string) is
        begin
            for i in s'range loop
                write(f, s(i));
            end loop;
        end procedure;

        procedure end_line is
        begin
            write(f, LF);
            flush(f);
        end procedure;
    begin
        if TRACE_FILE'length > 0 and rising_edge(clk) then

            if not opened then
                file_open(status, f, TRACE_FILE, write_mode);
                assert status = open_ok
                    report "trace_logger: cannot write the trace file " & TRACE_FILE
                    severity failure;
                opened := true;
                put(HEADER);
                end_line;
            end if;

            if retire_valid = '1' then
                put(dec(order) & "," & hex(retire_pc) & "," & hex(retire_insn) & "," &
                    hex(retire_next_pc));

                -- rd and rd_wdata: the core gives rd = 0 for a write to x0.
                rd := to_integer(unsigned(retire_rd));
                if rd /= 0 then
                    put("," & dec(rd) & "," & hex(retire_rd_wdata));
                else
                    put(",-,-");
                end if;

                -- mem_addr and mem_mask
                if retire_is_load = '1' or retire_is_store = '1' then
                    put("," & hex(retire_mem_addr) & "," & hex(retire_mem_mask));
                else
                    put(",-,-");
                end if;

                -- mem_wdata: only a store has it
                if retire_is_store = '1' then
                    put("," & hex(retire_mem_wdata));
                else
                    put(",-");
                end if;

                end_line;
                order := order + 1;
            end if;
        end if;
    end process logger;

end architecture sim;
