"""Tests for diff_trace.py. Run from the repo root:  python -m pytest tools

The sample is tests/data/fib_loop.csv, the real "florv iss --trace" output for
tests/asm/fib_loop.S: the header and 286 instructions.
"""

from pathlib import Path

import diff_trace

SAMPLE = Path(__file__).resolve().parent.parent / "tests" / "data" / "fib_loop.csv"

HEADER = b"order,pc,insn,next_pc,rd,rd_wdata,mem_addr,mem_mask,mem_wdata\n"
LINE0 = b"0,80000000,00100513,80000004,10,00000001,-,-,-\n"
LINE1 = b"1,80000004,00a5a023,80000008,-,-,8000101c,f,00000001\n"


def run(tmp_path, rtl: bytes, iss: bytes):
    """Writes the two files and runs the tool on them."""
    rtl_path = tmp_path / "rtl.csv"
    iss_path = tmp_path / "iss.csv"
    rtl_path.write_bytes(rtl)
    iss_path.write_bytes(iss)
    return diff_trace.main([str(rtl_path), str(iss_path)])


# ------------------------------------------------------------------- identical

def test_identical_files_exit_0(tmp_path, capsys):
    data = SAMPLE.read_bytes()
    assert run(tmp_path, data, data) == 0
    assert capsys.readouterr().out == "MATCH: 286 instructions\n"


def test_header_alone_is_a_match_of_0_instructions(tmp_path, capsys):
    assert run(tmp_path, HEADER, HEADER) == 0
    assert "MATCH: 0 instructions" in capsys.readouterr().out


# ------------------------------------------------------------- one edited line

def test_one_edited_line_exits_1_and_names_the_line(tmp_path, capsys):
    lines = SAMPLE.read_bytes().split(b"\n")
    original = lines[34]  # line 35 of the file: instruction 33
    assert original.startswith(b"33,")
    fields = original.split(b",")
    assert fields[5] != b"-"  # it writes a register
    fields[5] = b"deadbeef"
    lines[34] = b",".join(fields)

    assert run(tmp_path, b"\n".join(lines), SAMPLE.read_bytes()) == 1
    out = capsys.readouterr().out
    assert "MISMATCH at line 35 (instruction 33)" in out
    assert "  rtl: " + lines[34].decode() + "\n" in out
    assert "  iss: " + original.decode() + "\n" in out
    assert "differs in: rd_wdata\n" in out


def test_only_the_first_of_two_mismatches_is_reported(tmp_path, capsys):
    rtl = HEADER + LINE0.replace(b"80000004", b"80000008") + LINE1.replace(b",f,", b",3,")
    assert run(tmp_path, rtl, HEADER + LINE0 + LINE1) == 1
    out = capsys.readouterr().out
    assert "line 2 (instruction 0)" in out
    assert "line 3" not in out
    assert "differs in: next_pc\n" in out


def test_several_differing_columns_are_all_named(tmp_path, capsys):
    rtl = HEADER + b"0,80000000,00100513,80000004,-,-,-,-,-\n"
    assert run(tmp_path, rtl, HEADER + LINE0) == 1
    assert "differs in: rd, rd_wdata\n" in capsys.readouterr().out


def test_a_different_header_is_line_1(tmp_path, capsys):
    assert run(tmp_path, HEADER.replace(b"insn", b"word") + LINE0, HEADER + LINE0) == 1
    assert "MISMATCH at line 1 (the header)" in capsys.readouterr().out


# ---------------------------------------------------------------- length

def test_shorter_rtl_file_reports_the_first_missing_line(tmp_path, capsys):
    assert run(tmp_path, HEADER + LINE0, HEADER + LINE0 + LINE1) == 1
    out = capsys.readouterr().out
    assert "MISMATCH at line 3 (instruction 1)" in out
    assert "  rtl: (the file ends before this line)" in out
    assert "  iss: " + LINE1.decode() in out
    assert "differs in" not in out


def test_shorter_iss_file_reports_the_first_missing_line(tmp_path, capsys):
    assert run(tmp_path, HEADER + LINE0 + LINE1, HEADER + LINE0) == 1
    out = capsys.readouterr().out
    assert "MISMATCH at line 3 (instruction 1)" in out
    assert "  iss: (the file ends before this line)" in out


# ---------------------------------------------------------------- line endings

def test_carriage_returns_are_a_mismatch_and_are_shown(tmp_path, capsys):
    crlf = (HEADER + LINE0).replace(b"\n", b"\r\n")
    assert run(tmp_path, crlf, HEADER + LINE0) == 1
    out = capsys.readouterr().out
    assert "MISMATCH at line 1 (the header)" in out
    assert "mem_wdata\\r\n" in out  # printed as backslash r, not as a real one
    assert "\r" not in out


def test_missing_last_line_feed_is_a_mismatch_and_is_said(tmp_path, capsys):
    assert run(tmp_path, HEADER + LINE0[:-1], HEADER + LINE0) == 1
    out = capsys.readouterr().out
    assert "MISMATCH at line 2 (instruction 0)" in out
    assert "(no line feed at the end)" in out


def test_bytes_that_are_not_ascii_do_not_crash_the_report(tmp_path, capsys):
    assert run(tmp_path, HEADER + b"0,\xff\xfe\n", HEADER + LINE0) == 1
    assert "\\xff\\xfe" in capsys.readouterr().out


# ---------------------------------------------------------------- unusable files

def test_missing_file_exits_2(tmp_path, capsys):
    present = tmp_path / "iss.csv"
    present.write_bytes(HEADER)
    assert diff_trace.main([str(tmp_path / "absent.csv"), str(present)]) == 2
    assert diff_trace.main([str(present), str(tmp_path / "absent.csv")]) == 2
    assert "diff_trace:" in capsys.readouterr().err


def test_empty_file_exits_2_even_against_another_empty_file(tmp_path, capsys):
    assert run(tmp_path, b"", b"") == 2
    assert run(tmp_path, b"", HEADER) == 2
    assert run(tmp_path, HEADER, b"") == 2
    assert "is empty" in capsys.readouterr().err


# ---------------------------------------------------------------- split_lines

def test_split_lines_splits_at_line_feeds_only():
    assert diff_trace.split_lines(b"a\r\nb\n") == [b"a\r\n", b"b\n"]
    assert diff_trace.split_lines(b"a\nb") == [b"a\n", b"b"]
    assert diff_trace.split_lines(b"a\n\nb\n") == [b"a\n", b"\n", b"b\n"]
    assert diff_trace.split_lines(b"") == []
