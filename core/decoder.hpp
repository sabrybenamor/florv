#pragma once

#include <cstdint>

#include "instruction.hpp"

namespace florv {


Instruction decode(std::uint32_t raw);

}  // namespace florv
