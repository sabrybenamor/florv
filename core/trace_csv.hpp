#pragma once

#include <cstddef>

#include "retire_record.hpp"

namespace florv {


extern const char kTraceCsvHeader[];
constexpr std::size_t kTraceCsvLineSize = 80;
std::size_t toCsv(const RetireRecord& record, char* buffer, std::size_t size);

}  // namespace florv
