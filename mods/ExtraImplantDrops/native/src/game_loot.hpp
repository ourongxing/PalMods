#pragma once
#include <cstring>
#include "binary_guard.hpp"
#include "drop_plan.hpp"

namespace extra_implant_drops {
// Version-pinned native APIs. Game allocations and quantity/probability rules
// stay in the game; the mod only supplies an extra item's ID, chance and base=1.
class GameLoot {
    std::uintptr_t base;
    using Getter = void* (*)(void*);
    using Rate = float (*)(void*, std::uint8_t, NameArray*);
    using ItemRate = float (*)(void*, float, std::uint8_t, std::uint64_t, bool);
    using Constructor = Drop* (*)(void*, Drop*, std::uint64_t, float, float,
                                  std::int32_t, std::int32_t, float, const Location*);
    template<class T> T function(std::uintptr_t rva) const { return reinterpret_cast<T>(base + rva); }
public:
    explicit GameLoot(std::uintptr_t base) : base(base) {}
    std::optional<float> world_rate(void* manager) const {
        const auto* world = function<Getter>(guard::world_settings_rva)(manager);
        if (!world) return {};
        float value{};
        std::memcpy(&value, static_cast<const std::byte*>(world) + guard::world_rate_offset, sizeof(value));
        return std::isfinite(value) && value >= 0 && value <= 1000000 ? std::optional{value} : std::nullopt;
    }
    float drop_bonus(void* manager, const NameArray& skills, float partner_bonus) const {
        auto* passive_manager = function<Getter>(guard::passive_manager_rva)(manager);
        if (!passive_manager) return partner_bonus;
        NameArray owned{};
        function<void (*)(NameArray*, const NameArray*)>(guard::copy_names_rva)(&owned, &skills);
        // The rate function takes ownership of this engine-allocated copy and
        // frees it. A live Pal's array must never be passed directly.
        return partner_bonus + function<Rate>(guard::passive_rate_rva)(passive_manager, 0xb5, &owned) - 1.0f;
    }
    void roll(void* manager, Drop& entry, float probability, float bonus, float world,
              void* killer, bool item_bonus) const {
        if (killer && item_bonus)
            bonus += function<ItemRate>(guard::item_bonus_rva)(killer, 1.0f, 0x3b, entry.item, true) - 1.0f;
        function<Constructor>(guard::entry_constructor_rva)(manager, &entry, entry.item,
            probability, bonus, 1, 1, world, &entry.location);
    }
    void grow(DropArray& array, std::int32_t previous) const {
        function<void (*)(DropArray*, std::int32_t)>(guard::grow_rva)(&array, previous);
    }
};
} // namespace extra_implant_drops
