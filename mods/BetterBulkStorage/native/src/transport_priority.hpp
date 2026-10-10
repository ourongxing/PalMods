#pragma once
#include "storage_transfer.hpp"

namespace storage {
// A fractional bonus preserves every vanilla priority tier. Distance still
// breaks ties between candidates with the same priority and stacking status.
template <typename HasStack>
float transport_priority(std::uint8_t priority, HasStack has_stack) {
    return static_cast<float>(priority)
        + (priority >= 1 && priority <= 3 && has_stack() ? 0.5f : 0.0f);
}

template <typename Maximum, typename Allows>
bool has_transport_stack(void* container, std::uint64_t name, std::uint64_t none,
                         Maximum maximum, Allows allows) {
    if (name == none || !valid(container)) return false;
    auto** slots = read<void**>(container, 0x70);
    const auto count = read<std::int32_t>(container, 0x78);
    for (std::int32_t i = 0; i < count; ++i) {
        auto* slot = slots[i];
        if (!valid(slot) || read<std::uint64_t>(slot, 0x12c) != name) continue;
        const auto quantity = read<std::int32_t>(slot, 0x154);
        // Transport candidates contain static IDs only; never prefer a dynamic
        // item instance that cannot merge with the transported static item.
        const std::array<std::byte, 16> empty_id{};
        if (quantity > 0 && !std::memcmp(static_cast<std::byte*>(slot) + 0x144,
                                       empty_id.data(), empty_id.size())
            && maximum(slot) > quantity && allows(slot)) return true;
    }
    return false;
}
}
