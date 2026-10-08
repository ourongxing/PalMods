#pragma once
#include <array>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <span>
#include <stdexcept>

namespace better_workbench {
// Layout established by both native raw-material builders. Runtime reflection
// must confirm it before an adapter applies this to a GetCurrentRecipe copy.
struct MaterialLayout {
    std::size_t row_size;
    std::array<std::size_t, 5> names;
    std::array<std::size_t, 5> counts;
};
inline constexpr MaterialLayout observed_layout{
    0x88, {0x24, 0x30, 0x3c, 0x48, 0x54}, {0x2c, 0x38, 0x44, 0x50, 0x5c}};

struct MaterialPatch {
    uint64_t none;
    std::array<uint64_t, 5> names;
    std::array<int32_t, 5> presence;
};

// Quantities here are positive identity markers for the native slot-index
// lookup. They are NOT unit costs, totals, or research-adjusted quantities.
// Actual cost arrays/maps must be supplied independently by the same job plan.
inline MaterialPatch slot_identities(std::span<const uint64_t> items, uint64_t none) {
    if (items.size() > 5) throw std::invalid_argument("native input slot limit");
    MaterialPatch patch{};
    patch.none = none;
    patch.names.fill(none);
    for (std::size_t index = 0; index < items.size(); ++index) {
        if (items[index] == none) throw std::invalid_argument("empty material identity");
        for (std::size_t prior = 0; prior < index; ++prior)
            if (items[prior] == items[index]) throw std::invalid_argument("duplicate material identity");
        patch.names[index] = items[index];
        patch.presence[index] = 1;
    }
    return patch;
}

inline void verify_layout(const MaterialLayout& layout) {
    // Until another layout is explicitly audited, do not adapt by guessing.
    if (layout.row_size != observed_layout.row_size || layout.names != observed_layout.names
        || layout.counts != observed_layout.counts)
        throw std::invalid_argument("recipe material layout mismatch");
}

// The future native adapter may apply this ONLY to the existing native-owned
// return buffer, after the original GetCurrentRecipe has populated that copy.
// Never memcpy a whole FPalRecipeData: it contains an owning array at +0x70.
// This function neither copies nor changes any pointer or nonmaterial field.
inline void apply_to_recipe_copy(std::span<std::byte> copy, const MaterialPatch& patch,
                                 const MaterialLayout& reflected_layout) {
    verify_layout(reflected_layout);
    if (copy.size() < reflected_layout.row_size) throw std::invalid_argument("recipe copy too small");
    bool unused{};
    for (std::size_t index = 0; index < 5; ++index) {
        if (patch.presence[index] == 0) {
            if (patch.names[index] != patch.none) throw std::invalid_argument("unused slot identity mismatch");
            unused = true;
        } else {
            if (patch.presence[index] != 1 || patch.names[index] == patch.none || unused)
                throw std::invalid_argument("invalid slot presence marker");
            for (std::size_t prior = 0; prior < index; ++prior)
                if (patch.names[prior] == patch.names[index]) throw std::invalid_argument("duplicate material identity");
        }
    }
    // All checks precede the first write. The caller owns the validated patch.
    for (std::size_t index = 0; index < 5; ++index) {
        std::memcpy(copy.data() + reflected_layout.names[index], &patch.names[index], 8);
        std::memcpy(copy.data() + reflected_layout.counts[index], &patch.presence[index], 4);
    }
}
}
