#include <cstddef>
#include <cstdint>
#include <cstring>
#include <string>

#include "doctest.h"
#include "retire_record.hpp"

using florv::kRetireTextSize;
using florv::RetireRecord;
using florv::toString;

namespace {

// add x10,x11,x10 at 0x80000010, the seventh instruction retired, writing 42 to x10.
RetireRecord registerWrite() {
    RetireRecord r;
    r.order = 7;
    r.pc = 0x80000010u;
    r.insn = 0x00A58533u;
    r.next_pc = 0x80000014u;
    r.rd = 10;
    r.rd_wdata = 0x0000002Au;
    return r;
}

// A word store of 42 to 0x8000100C.
RetireRecord store() {
    RetireRecord r;
    r.order = 8;
    r.pc = 0x80000014u;
    r.insn = 0x00A12623u;
    r.next_pc = 0x80000018u;
    r.mem_addr = 0x8000100Cu;
    r.mem_mask = 0xF;
    r.mem_wdata = 0x0000002Au;
    r.is_store = true;
    return r;
}

// A byte load from 0x8000100C into x10.
RetireRecord load() {
    RetireRecord r;
    r.order = 9;
    r.pc = 0x80000018u;
    r.insn = 0x00C14503u;
    r.next_pc = 0x8000001Cu;
    r.rd = 10;
    r.rd_wdata = 0x00000080u;
    r.mem_addr = 0x8000100Cu;
    r.mem_mask = 0x1;
    r.is_load = true;
    return r;
}

std::string text(const RetireRecord& r) {
    char buffer[kRetireTextSize];
    const std::size_t length = toString(r, buffer, sizeof(buffer));
    REQUIRE(length < sizeof(buffer));
    REQUIRE(std::strlen(buffer) == length);
    return std::string(buffer);
}

}  // namespace

TEST_CASE("RetireRecord: a new record is all zero") {
    const RetireRecord r;
    CHECK(r.order == 0);
    CHECK(r.pc == 0);
    CHECK(r.insn == 0);
    CHECK(r.next_pc == 0);
    CHECK(r.rd == 0);
    CHECK(r.rd_wdata == 0);
    CHECK(r.mem_addr == 0);
    CHECK(r.mem_mask == 0);
    CHECK(r.mem_wdata == 0);
    CHECK_FALSE(r.is_load);
    CHECK_FALSE(r.is_store);
}

TEST_CASE("RetireRecord: two records with the same fields are equal") {
    CHECK(RetireRecord{} == RetireRecord{});
    CHECK(registerWrite() == registerWrite());
    CHECK(store() == store());
    CHECK(load() == load());
    CHECK_FALSE(registerWrite() != registerWrite());

    CHECK(registerWrite() != store());
    CHECK_FALSE(registerWrite() == store());
}

TEST_CASE("RetireRecord: a difference in any one field makes two records unequal") {
    const RetireRecord base = load();

    // Each entry changes exactly one field.
    using Change = void (*)(RetireRecord&);
    const Change changes[] = {
        [](RetireRecord& r) { r.order ^= 1u; },
        [](RetireRecord& r) { r.pc ^= 0x80000000u; },
        [](RetireRecord& r) { r.insn ^= 1u; },
        [](RetireRecord& r) { r.next_pc ^= 4u; },
        [](RetireRecord& r) { r.rd ^= 1u; },
        [](RetireRecord& r) { r.rd_wdata ^= 0x80000000u; },
        [](RetireRecord& r) { r.mem_addr ^= 1u; },
        [](RetireRecord& r) { r.mem_mask ^= 2u; },
        [](RetireRecord& r) { r.mem_wdata ^= 1u; },
        [](RetireRecord& r) { r.is_load = !r.is_load; },
        [](RetireRecord& r) { r.is_store = !r.is_store; },
    };
    CHECK(sizeof(changes) / sizeof(changes[0]) == 11);  // one per field of the record

    int index = 0;
    for (const Change change : changes) {
        CAPTURE(index);
        RetireRecord changed = base;
        change(changed);
        CHECK(changed != base);
        CHECK_FALSE(changed == base);
        ++index;
    }
}

TEST_CASE("RetireRecord: toString of a register write") {
    CHECK(text(registerWrite()) == "#7 pc=80000010 insn=00a58533 next=80000014 x10=0000002a");
}

TEST_CASE("RetireRecord: toString of a store shows address, mask and data") {
    CHECK(text(store()) ==
          "#8 pc=80000014 insn=00a12623 next=80000018 store addr=8000100c mask=f data=0000002a");
}

TEST_CASE("RetireRecord: toString of a load shows the register and the address") {
    CHECK(text(load()) ==
          "#9 pc=80000018 insn=00c14503 next=8000001c x10=00000080 load addr=8000100c mask=1");
}

TEST_CASE("RetireRecord: toString of a record with no register and no memory access") {
    RetireRecord branch;
    branch.order = 3;
    branch.pc = 0x80000020u;
    branch.insn = 0xFF95E0E3u;
    branch.next_pc = 0x80000000u;
    CHECK(text(branch) == "#3 pc=80000020 insn=ff95e0e3 next=80000000");
}

TEST_CASE("RetireRecord: the longest text fits in kRetireTextSize") {
    RetireRecord r;
    r.order = 0xFFFFFFFFu;  // ten decimal digits
    r.pc = 0xFFFFFFFFu;
    r.insn = 0xFFFFFFFFu;
    r.next_pc = 0xFFFFFFFFu;
    r.rd = 31;
    r.rd_wdata = 0xFFFFFFFFu;
    r.mem_addr = 0xFFFFFFFFu;
    r.mem_mask = 0xF;
    r.mem_wdata = 0xFFFFFFFFu;
    r.is_load = true;  // never both in a real record; both here gives the longest text
    r.is_store = true;

    char buffer[kRetireTextSize];
    const std::size_t length = toString(r, buffer, sizeof(buffer));
    CHECK(length < sizeof(buffer));
    CHECK(std::strlen(buffer) == length);
}

TEST_CASE("RetireRecord: toString cuts the text to a small buffer and stays inside it") {
    const std::string full = text(store());

    char buffer[32];
    std::memset(buffer, 'Z', sizeof(buffer));
    const std::size_t length = toString(store(), buffer, 16);

    CHECK(length == full.size());  // the full length is still reported
    CHECK(std::strlen(buffer) == 15);
    CHECK(std::string(buffer) == full.substr(0, 15));
    for (std::size_t i = 16; i < sizeof(buffer); ++i) {
        CHECK(buffer[i] == 'Z');  // nothing written past the size that was given
    }

    // Size 0 writes nothing at all, and a null buffer is then allowed.
    CHECK(toString(store(), nullptr, 0) == full.size());
}
