#pragma once

#include <cstddef>
#include <cstdint>

namespace florv {


struct ByteView {
    const std::uint8_t* data = nullptr;
    std::size_t size = 0;

    
    bool contains(std::size_t offset, std::size_t length) const {
        return length <= size && offset <= size - length;
    }

    
    ByteView sub(std::size_t offset, std::size_t length) const {
        return ByteView{data + offset, length};
    }
};

}  
