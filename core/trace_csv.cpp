#include "trace_csv.hpp"

#include <cinttypes>
#include <cstdio>

namespace florv {

const char kTraceCsvHeader[] = "order,pc,insn,next_pc,rd,rd_wdata,mem_addr,mem_mask,mem_wdata";

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

std::size_t toCsv(const RetireRecord& record, char* buffer, std::size_t size) {
    std::size_t used = 0;

    append(buffer, size, used, "%" PRIu32 ",%08" PRIx32 ",%08" PRIx32 ",%08" PRIx32,
           record.order, record.pc, record.insn, record.next_pc);

    if (record.rd != 0) {
        append(buffer, size, used, ",%u,%08" PRIx32, static_cast<unsigned>(record.rd),
               record.rd_wdata);
    } else {
        append(buffer, size, used, ",-,-");
    }

    if (record.is_load || record.is_store) {
        append(buffer, size, used, ",%08" PRIx32 ",%x", record.mem_addr,
               static_cast<unsigned>(record.mem_mask & 0xFu));
    } else {
        append(buffer, size, used, ",-,-");
    }

    if (record.is_store) {
        append(buffer, size, used, ",%08" PRIx32, record.mem_wdata);
    } else {
        append(buffer, size, used, ",-");
    }
    return used;
}

}  // namespace florv
