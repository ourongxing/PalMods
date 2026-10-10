#pragma once
#include "storage_transfer.hpp"

namespace storage {
inline constexpr std::int32_t expanded_stack_limit = 99999;
inline std::int32_t expanded_limit(std::int32_t original, bool dynamic) {
    // Zero/one limits and per-instance items must keep their vanilla rules.
    return original > 1 && !dynamic ? expanded_stack_limit : original;
}
inline void set_item_stack_limit(void* data, std::int32_t amount) {
    std::memcpy(static_cast<std::byte*>(data) + 0x78, &amount, sizeof(amount));
}
}
