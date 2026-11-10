// The expected lines are the examples of docs/trace-format.md.

#include <cstddef>
#include <cstdint>
#include <cstring>
#include <string>

#include "doctest.h"
#include "trace_csv.hpp"

using florv::kTraceCsvHeader;
using florv::kTraceCsvLineSize;
using florv::RetireRecord;
using florv::toCsv;

namespace {

std::string line(const RetireRecord& r) {
    char buffer[kTraceCsvLineSize];
    const std::size_t length = toCsv(r, buffer, sizeof(buffer));
    REQUIRE(length < sizeof(buffer));
    REQUIRE(std::strlen(buffer) == length);
    return std::string(buffer);
}

RetireRecord record(std::uint32_t order, std::uint32_t pc, std::uint32_t insn,
                    std::uint32_t next_pc) {
    RetireRecord r;
    r.order = order;
    r.pc = pc;
    r.insn = insn;
    r.next_pc = next_pc;
    return r;
}

}  // namespace

TEST_CASE("trace CSV: the header names the nine columns") {
    CHECK(std::string(kTraceCsvHeader) ==
          "order,pc,insn,next_pc,rd,rd_wdata,mem_addr,mem_mask,mem_wdata");
}

TEST_CASE("trace CSV: a register write has no memory fields") {
    RetireRecord r = record(0, 0x80000000u, 0x00100513u, 0x80000004u);
    r.rd = 10;
    r.rd_wdata = 1;
    CHECK(line(r) == "0,80000000,00100513,80000004,10,00000001,-,-,-");

    r = record(1, 0x80000004u, 0x00001597u, 0x80000008u);
    r.rd = 11;
    r.rd_wdata = 0x80001004u;
    CHECK(line(r) == "1,80000004,00001597,80000008,11,80001004,-,-,-");
}

TEST_CASE("trace CSV: a store has no register fields") {
    RetireRecord r = record(3, 0x8000000Cu, 0x00A5A023u, 0x80000010u);
    r.is_store = true;
    r.mem_addr = 0x8000101Cu;
    r.mem_mask = 0xF;
    r.mem_wdata = 1;
    CHECK(line(r) == "3,8000000c,00a5a023,80000010,-,-,8000101c,f,00000001");
}

TEST_CASE("trace CSV: a load has a register and an address, and no stored value") {
    RetireRecord r = record(9, 0x80000018u, 0x00C14503u, 0x8000001Cu);
    r.rd = 10;
    r.rd_wdata = 0x80;
    r.is_load = true;
    r.mem_addr = 0x8000100Cu;
    r.mem_mask = 0x1;
    CHECK(line(r) == "9,80000018,00c14503,8000001c,10,00000080,8000100c,1,-");
}

TEST_CASE("trace CSV: a half-word store shows mask 3") {
    RetireRecord r = record(12, 0x80000100u, 0xEC499EA3u, 0x80000104u);
    r.is_store = true;
    r.mem_addr = 0x80001000u;
    r.mem_mask = 0x3;
    r.mem_wdata = 0xCCDD;
    CHECK(line(r) == "12,80000100,ec499ea3,80000104,-,-,80001000,3,0000ccdd");
}

TEST_CASE("trace CSV: neither a register nor memory") {
    // A branch, and a store of zero to address zero is still a store.
    CHECK(line(record(5, 0x80000020u, 0xFF95E0E3u, 0x80000000u)) ==
          "5,80000020,ff95e0e3,80000000,-,-,-,-,-");

    RetireRecord zero = record(0, 0, 0, 0);
    zero.is_store = true;
    zero.mem_mask = 0xF;
    CHECK(line(zero) == "0,00000000,00000000,00000000,-,-,00000000,f,00000000");
}

TEST_CASE("trace CSV: a load into x0 keeps the address and has no register") {
    RetireRecord r = record(7, 0x80000100u, 0x0002A003u, 0x80000104u);
    r.is_load = true;
    r.mem_addr = 0x80001000u;
    r.mem_mask = 0xF;
    CHECK(line(r) == "7,80000100,0002a003,80000104,-,-,80001000,f,-");
}

TEST_CASE("trace CSV: the longest line fits in kTraceCsvLineSize") {
    RetireRecord r = record(0xFFFFFFFFu, 0xFFFFFFFFu, 0xFFFFFFFFu, 0xFFFFFFFFu);
    r.rd = 31;
    r.rd_wdata = 0xFFFFFFFFu;
    r.is_store = true;  // never with a register in a real record; this is the longest text
    r.mem_addr = 0xFFFFFFFFu;
    r.mem_mask = 0xF;
    r.mem_wdata = 0xFFFFFFFFu;
    CHECK(line(r) == "4294967295,ffffffff,ffffffff,ffffffff,31,ffffffff,ffffffff,f,ffffffff");
}

TEST_CASE("trace CSV: a small buffer is not overrun and the full length is returned") {
    RetireRecord r = record(3, 0x8000000Cu, 0x00A5A023u, 0x80000010u);
    r.is_store = true;
    r.mem_addr = 0x8000101Cu;
    r.mem_mask = 0xF;
    r.mem_wdata = 1;
    const std::string full = line(r);

    char buffer[32];
    std::memset(buffer, 'Z', sizeof(buffer));
    CHECK(toCsv(r, buffer, 12) == full.size());
    CHECK(std::string(buffer) == full.substr(0, 11));
    for (std::size_t i = 12; i < sizeof(buffer); ++i) {
        CHECK(buffer[i] == 'Z');
    }
    CHECK(toCsv(r, nullptr, 0) == full.size());
}
