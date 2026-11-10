"""Tests for cmp_spike.py. Run from the repo root:  python -m pytest tools

The sample files are real output for tests/asm/fib_loop.S:
  tests/data/fib_loop.csv        "florv iss --trace"
  tests/data/fib_loop.spike.txt  "spike --log-commits", cut three lines after the
                                 store to tohost
"""

from pathlib import Path

import pytest

import cmp_spike
from cmp_spike import Record

DATA = Path(__file__).resolve().parent.parent / "tests" / "data"
CSV = DATA / "fib_loop.csv"
LOG = DATA / "fib_loop.spike.txt"

HEADER = cmp_spike.CSV_HEADER


def sample_iss():
    return cmp_spike.parse_iss_csv(CSV.read_text())


def sample_spike():
    return cmp_spike.parse_spike_log(LOG.read_text())


# ---------------------------------------------------------------- Spike parser

def test_first_parsed_pc_is_the_start_of_the_ram():
    assert sample_spike()[0].pc == 0x80000000


def test_boot_rom_lines_are_skipped():
    text = LOG.read_text()
    assert "0x00001000" in text  # the boot ROM is in the file
    assert all(record.pc >= 0x80000000 for record in sample_spike())


def test_sample_log_has_the_program_and_three_loop_lines():
    assert len(sample_spike()) == 286 + 3


def test_register_write_line():
    record = cmp_spike.parse_spike_line("core   0: 3 0x80000008 (0x00100293) x5  0x00000001")
    assert record == Record(pc=0x80000008, insn=0x00100293, rd=5, rd_wdata=1)


def test_two_digit_register():
    record = cmp_spike.parse_spike_line("core   0: 3 0x80000040 (0x00744683) x13 0x0000007f")
    assert record.rd == 13
    assert record.rd_wdata == 0x7F


def test_store_line_gives_address_data_and_width():
    word = cmp_spike.parse_spike_line(
        "core   0: 3 0x80000014 (0x00532023) mem 0x80000040 0x00000001")
    assert word == Record(pc=0x80000014, insn=0x00532023, mem_addr=0x80000040,
                          mem_bytes=4, store_data=1)

    byte = cmp_spike.parse_spike_line("core   0: 3 0x80000094 (0x013484a3) mem 0x80000195 0xdd")
    assert byte.mem_bytes == 1
    assert byte.store_data == 0xDD
    assert byte.rd is None  # the address must not be read as a register


def test_load_line_gives_register_and_address_but_no_data():
    record = cmp_spike.parse_spike_line(
        "core   0: 3 0x80000040 (0x00744683) x13 0x0000007f mem 0x80000187")
    assert record == Record(pc=0x80000040, insn=0x00744683, rd=13, rd_wdata=0x7F,
                            mem_addr=0x80000187)


def test_line_with_nothing_written():
    record = cmp_spike.parse_spike_line("core   0: 3 0x80000018 (0x0000006f)")
    assert record == Record(pc=0x80000018, insn=0x0000006F)


def test_write_to_x0_is_dropped():
    record = cmp_spike.parse_spike_line("core   0: 3 0x80000008 (0x00100013) x0  0x00000001")
    assert record.rd is None
    assert record.rd_wdata is None


def test_lines_that_are_not_commits_are_ignored():
    assert cmp_spike.parse_spike_line("warning: tohost and fromhost symbols not in ELF") is None
    assert cmp_spike.parse_spike_line("") is None
    text = "some warning\ncore   0: 3 0x80000000 (0x00010117) x2  0x80010000\n\n"
    assert len(cmp_spike.parse_spike_log(text)) == 1


# ------------------------------------------------------------------ CSV parser

def test_csv_sample_has_286_instructions_starting_at_the_ram():
    records = sample_iss()
    assert len(records) == 286
    assert records[0].pc == 0x80000000


def test_csv_fields():
    text = HEADER + "\n" + "\n".join([
        "0,80000000,00100513,80000004,10,00000001,-,-,-",
        "1,8000000c,00a5a023,80000010,-,-,8000101c,f,00000001",
        "2,80000018,00c14503,8000001c,10,00000080,8000100c,1,-",
        "3,80000100,ec499ea3,80000104,-,-,80001000,3,0000ccdd",
    ]) + "\n"
    register, store, load, half = cmp_spike.parse_iss_csv(text)
    assert register == Record(pc=0x80000000, insn=0x00100513, rd=10, rd_wdata=1)
    assert store == Record(pc=0x8000000C, insn=0x00A5A023, mem_addr=0x8000101C,
                           mem_bytes=4, store_data=1)
    assert load == Record(pc=0x80000018, insn=0x00C14503, rd=10, rd_wdata=0x80,
                          mem_addr=0x8000100C, mem_bytes=1)
    assert half.mem_bytes == 2
    assert half.store_data == 0xCCDD


def test_csv_with_windows_line_endings_is_read_the_same():
    text = CSV.read_text()
    assert cmp_spike.parse_iss_csv(text.replace("\n", "\r\n")) == sample_iss()


@pytest.mark.parametrize("text", [
    "",
    "pc,insn\n0,1\n",                                             # wrong header
    HEADER + "\n0,80000000,00100513,80000004,10,00000001,-,-\n",  # 8 fields
    HEADER + "\n0,8000000g,00100513,80000004,10,00000001,-,-,-\n",  # not hex
    HEADER + "\n0,80000000,00100513,80000004,-,-,80001000,7,00000001\n",  # bad mask
])
def test_malformed_csv_is_rejected(text):
    with pytest.raises(cmp_spike.TraceError):
        cmp_spike.parse_iss_csv(text)


# ------------------------------------------------------------------ comparison

def test_sample_trace_matches_sample_log():
    assert cmp_spike.compare(sample_iss(), sample_spike()) is None


def edited(index, **changes):
    """The sample ISS trace with some fields of one record changed."""
    records = sample_iss()
    fields = dict(records[index].__dict__)
    fields.update(changes)
    records[index] = Record(**fields)
    return records


def test_one_changed_register_value_is_rejected():
    iss = sample_iss()
    index = next(i for i, record in enumerate(iss) if record.rd is not None and i > 20)
    mismatch = cmp_spike.compare(edited(index, rd_wdata=iss[index].rd_wdata ^ 1), sample_spike())
    assert mismatch is not None
    assert mismatch.index == index
    assert mismatch.field == "rd_wdata"


def test_each_compared_field_is_checked():
    iss = sample_iss()
    with_rd = next(i for i, r in enumerate(iss) if r.rd is not None and i > 20)
    store = next(i for i, r in enumerate(iss) if r.store_data is not None)
    load = next(i for i, r in enumerate(iss) if r.mem_addr is not None and r.store_data is None)
    plain = next(i for i, r in enumerate(iss) if r.rd is None and r.mem_addr is None)

    cases = [
        (with_rd, dict(pc=iss[with_rd].pc + 4), "pc"),
        (with_rd, dict(insn=iss[with_rd].insn ^ 0x100), "insn"),
        (with_rd, dict(rd=iss[with_rd].rd ^ 1), "rd"),
        (with_rd, dict(rd=None, rd_wdata=None), "rd"),
        (plain, dict(rd=7, rd_wdata=0), "rd"),
        (with_rd, dict(rd_wdata=iss[with_rd].rd_wdata ^ 0x80000000), "rd_wdata"),
        (store, dict(mem_addr=iss[store].mem_addr + 4), "mem_addr"),
        (store, dict(store_data=iss[store].store_data ^ 1), "store data"),
        (store, dict(mem_bytes=2), "store width"),
        (store, dict(store_data=None), "load or store"),
        (store, dict(mem_addr=None, mem_bytes=None, store_data=None), "memory access"),
        (load, dict(mem_addr=iss[load].mem_addr + 1), "mem_addr"),
        (plain, dict(mem_addr=0x80001000, mem_bytes=4), "memory access"),
    ]
    for index, changes, field in cases:
        mismatch = cmp_spike.compare(edited(index, **changes), sample_spike())
        assert mismatch is not None, (index, changes)
        assert (mismatch.index, mismatch.field) == (index, field), (index, changes)


def test_the_first_of_two_differences_is_reported():
    iss = sample_iss()
    first = next(i for i, r in enumerate(iss) if r.rd is not None and i > 20)
    later = next(i for i, r in enumerate(iss) if r.rd is not None and i > first + 10)
    records = edited(first, rd_wdata=iss[first].rd_wdata ^ 1)
    fields = dict(records[later].__dict__)
    fields["rd_wdata"] ^= 1
    records[later] = Record(**fields)
    assert cmp_spike.compare(records, sample_spike()).index == first


def test_store_data_is_compared_at_the_access_width():
    # The ISS reports a byte store as 000000dd; Spike prints dd.
    iss = [Record(pc=0x80000000, insn=0x013484A3, mem_addr=0x80000195, mem_bytes=1,
                  store_data=0xDD)]
    spike = [cmp_spike.parse_spike_line(
        "core   0: 3 0x80000000 (0x013484a3) mem 0x80000195 0xdd")]
    assert cmp_spike._first_difference(iss[0], spike[0]) is None

    wrong = [Record(pc=0x80000000, insn=0x013484A3, mem_addr=0x80000195, mem_bytes=1,
                    store_data=0xDC)]
    assert cmp_spike._first_difference(wrong[0], spike[0]) == "store data"


def test_spike_log_shorter_than_the_trace_is_a_mismatch():
    mismatch = cmp_spike.compare(sample_iss(), sample_spike()[:100])
    assert mismatch.index == 100
    assert mismatch.field == "length"
    assert mismatch.spike is None


def test_trace_that_does_not_end_with_the_tohost_store_is_a_mismatch():
    # As if the ISS had hit the step limit: the last line is not the halting store.
    mismatch = cmp_spike.compare(sample_iss()[:-1], sample_spike())
    assert mismatch is not None
    assert mismatch.field == "halt"


def test_iss_halting_early_on_another_store_is_a_mismatch():
    # Cut the ISS trace at its first store: it ends with a store, but Spike goes on
    # running the program instead of sitting in the final loop.
    iss = sample_iss()
    first_store = next(i for i, r in enumerate(iss)
                       if r.store_data not in (None, 0) and r.mem_bytes == 4)
    assert first_store < len(iss) - 1
    mismatch = cmp_spike.compare(iss[:first_store + 1], sample_spike())
    assert mismatch is not None
    assert mismatch.field == "halt"
    assert mismatch.iss is None


def test_empty_trace_is_a_mismatch():
    assert cmp_spike.compare([], sample_spike()).field == "halt"


# ---------------------------------------------------------------------- report

def test_report_names_the_index_and_shows_three_records_before_it():
    iss = sample_iss()
    index = next(i for i, record in enumerate(iss) if record.rd is not None and i > 20)
    changed = edited(index, rd_wdata=iss[index].rd_wdata ^ 1)
    mismatch = cmp_spike.compare(changed, sample_spike())
    report = cmp_spike.format_report(mismatch, changed, sample_spike())

    lines = report.splitlines()
    assert lines[0] == f"MISMATCH at instruction {index}: rd_wdata"
    assert any(line.startswith("  iss  : ") for line in lines)
    assert any(line.startswith("  spike: ") for line in lines)
    for earlier in (index - 3, index - 2, index - 1):
        assert any(line.strip().startswith(f"{earlier}:") for line in lines)
    assert not any(line.strip().startswith(f"{index - 4}:") for line in lines)

    # Both values are in the report, so neither file has to be opened.
    assert f"{iss[index].rd_wdata:08x}" in report
    assert f"{iss[index].rd_wdata ^ 1:08x}" in report


def test_report_at_the_first_instruction_has_no_context():
    changed = edited(0, rd_wdata=0)
    mismatch = cmp_spike.compare(changed, sample_spike())
    report = cmp_spike.format_report(mismatch, changed, sample_spike())
    assert report.splitlines()[0] == "MISMATCH at instruction 0: rd_wdata"
    assert "before it" not in report


def test_format_record():
    assert cmp_spike.format_record(Record(pc=0x80000008, insn=0x00100293, rd=5, rd_wdata=1)) \
        == "pc=80000008 insn=00100293 x5=00000001"
    assert cmp_spike.format_record(Record(pc=0x80000014, insn=0x00532023, mem_addr=0x80000040,
                                          mem_bytes=4, store_data=1)) \
        == "pc=80000014 insn=00532023 store addr=80000040 data=00000001"
    assert cmp_spike.format_record(Record(pc=0x80000040, insn=0x00744683, rd=13, rd_wdata=0x7F,
                                          mem_addr=0x80000187)) \
        == "pc=80000040 insn=00744683 x13=0000007f load addr=80000187"
    assert cmp_spike.format_record(None) == "(nothing)"


# ---------------------------------------------------------------- command line

def test_main_exits_0_on_a_match(capsys):
    assert cmp_spike.main([str(CSV), str(LOG)]) == 0
    assert capsys.readouterr().out.strip() == "MATCH: 286 instructions"


def test_main_exits_1_on_a_hand_edited_csv(tmp_path, capsys):
    lines = CSV.read_text().splitlines()
    # Take the first line after instruction 20 that writes a register and change the
    # last digit of its rd_wdata, as a text editor would.
    number = next(i for i, line in enumerate(lines) if i > 21 and line.split(",")[5] != "-")
    fields = lines[number].split(",")
    order = fields[0]
    fields[5] = fields[5][:-1] + ("0" if fields[5][-1] != "0" else "1")
    lines[number] = ",".join(fields)
    edited_csv = tmp_path / "edited.csv"
    edited_csv.write_text("\n".join(lines) + "\n")

    assert cmp_spike.main([str(edited_csv), str(LOG)]) == 1
    assert capsys.readouterr().out.startswith(f"MISMATCH at instruction {order}: rd_wdata")


def test_main_exits_2_on_a_missing_or_malformed_file(tmp_path, capsys):
    assert cmp_spike.main([str(tmp_path / "none.csv"), str(LOG)]) == 2
    not_csv = tmp_path / "bad.csv"
    not_csv.write_text("hello\n")
    assert cmp_spike.main([str(not_csv), str(LOG)]) == 2
    capsys.readouterr()
