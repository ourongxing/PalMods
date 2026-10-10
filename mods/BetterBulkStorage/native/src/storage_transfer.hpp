#pragma once
#include <algorithm>
#include <array>
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
// These offsets and the callback ABI are checked against the supported native
// helper. Keep its slot IDs, capacity query and authoritative transfer intact.
template <typename Maximum, typename Transfer>
void transfer(void* context, const void* source, const void* item,
              std::uint64_t none, Maximum maximum, Transfer move) {
    auto* containers = read<void*>(context, 0);
    auto** data = read<void**>(containers, 0);
    const auto count = read<std::int32_t>(containers, 8);
    auto* manager = *read<void**>(context, 8);
    auto* transaction = read<void*>(context, 16);
    auto remaining = read<std::int32_t>(item, 0x28);
    const auto name = read<std::uint64_t>(item, 0);
    // First merge across every chest; only then allocate any empty slot.
    for (unsigned pass = 0; pass < 2 && remaining > 0; ++pass) {
        for (std::int32_t c = 0; c < count && remaining > 0; ++c) {
            auto* container = data[c];
            if (!valid(container)) continue;
            auto** slots = read<void**>(container, 0x70);
            const auto slot_count = read<std::int32_t>(container, 0x78);
            for (std::int32_t s = 0; s < slot_count && remaining > 0; ++s) {
                auto* slot = slots[s];
                if (!valid(slot)) continue;
                const auto before = read<std::int32_t>(slot, 0x154);
                const auto slot_name = read<std::uint64_t>(slot, 0x12c);
                auto quantity = remaining;
                if (pass == 0) {
                    if (!before || slot_name == none || slot_name != name
                        || std::memcmp(static_cast<const std::byte*>(slot) + 0x144,
                                       static_cast<const std::byte*>(item) + 0x18, 16)) continue;
                    quantity = std::min(remaining, std::max(0, maximum(slot) - before));
                    if (!quantity) continue;
                } else if (before && slot_name != none) continue;
                std::array<std::byte, 20> destination{};
                std::memcpy(destination.data(), static_cast<const std::byte*>(slot) + 0x11c, 16);
                std::memcpy(destination.data() + 16, static_cast<const std::byte*>(slot) + 0x118, 4);
                move(manager, quantity, destination.data(), source, transaction);
                // The official transfer may reject a slot or move only part of
                // the request. Measure its result exactly as the native helper.
                remaining += before - read<std::int32_t>(slot, 0x154);
            }
        }
    }
}
}
