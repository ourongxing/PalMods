#pragma once
#include <cstddef>
#include <cstdint>
#include <cstring>

namespace storage {
template <typename T> T read(const void* object, std::size_t offset) {
    T value{};
    std::memcpy(&value, static_cast<const std::byte*>(object) + offset, sizeof(value));
    return value;
}
inline bool valid(const void* object) {
    return object && !(read<std::uint32_t>(object, 8) & 0x60000000);
}
}
