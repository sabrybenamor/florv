#include "retire_record.hpp"

#include <cinttypes>
#include <cstdio>

namespace florv {

bool operator==(const RetireRecord& a, const RetireRecord& b) {
    return a.order == b.order && a.pc == b.pc && a.insn == b.insn &&
           a.next_pc == b.next_pc && a.rd == b.rd && a.rd_wdata == b.rd_wdata &&
           a.mem_addr == b.mem_addr && a.mem_mask == b.mem_mask &&
           a.mem_wdata == b.mem_wdata && a.is_load == b.is_load &&
           a.is_store == b.is_store;
}

bool operator!=(const RetireRecord& a, const RetireRecord& b) {
    return !(a == b);
}

namespace {


template <typename... Args>
void append(char* buffer, std::size_t size, std::size_t& used, const char* format,
            Args... args) {
    const std::size_t room = used < size ? size - used : 0;
    const int wanted = std::snprintf(room != 0 ? buffer + used : nullptr, room, format, args...);
    if (wanted > 0) {
        used += static_cast<std::size_t>(wanted);
    }
}

}  // namespace

std::size_t toString(const RetireRecord& record, char* buffer, std::size_t size) {
    std::size_t used = 0;

    
    append(buffer, size, used, "#%" PRIu32 " pc=%08" PRIx32 " insn=%08" PRIx32 " next=%08" PRIx32,
           record.order, record.pc, record.insn, record.next_pc);

    if (record.rd != 0) {
        append(buffer, size, used, " x%u=%08" PRIx32, static_cast<unsigned>(record.rd),
               record.rd_wdata);
    }
    if (record.is_load) {
        append(buffer, size, used, " load addr=%08" PRIx32 " mask=%x", record.mem_addr,
               static_cast<unsigned>(record.mem_mask));
    }
    if (record.is_store) {
        append(buffer, size, used, " store addr=%08" PRIx32 " mask=%x data=%08" PRIx32,
               record.mem_addr, static_cast<unsigned>(record.mem_mask), record.mem_wdata);
    }
    return used;
}

}  // namespace florv
