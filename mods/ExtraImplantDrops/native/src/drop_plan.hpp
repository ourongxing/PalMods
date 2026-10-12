#pragma once
#include <algorithm>
#include <array>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <optional>
#include <span>

namespace extra_implant_drops {
struct Location { double x{}, y{}, z{}; };
// Native drop-builder and its consumers copy entries in 0x28-byte strides.
struct Drop {
    std::uint64_t item{};
    std::int32_t count{};
    std::int32_t padding{};
    Location location{};
};
struct DropArray { Drop* data{}; std::int32_t count{}, capacity{}; };
struct NameArray { const std::uint64_t* data{}; std::int32_t count{}, capacity{}; };
struct DropSource {
    std::uint64_t character_id{};
    std::int32_t level{};
    std::uint8_t rare{};
    std::uint8_t padding[3]{};
    NameArray passives{};
};
static_assert(offsetof(DropSource, passives) == 16 && sizeof(DropSource) == 32);
static_assert(sizeof(Location) == 24 && sizeof(Drop) == 40 && sizeof(DropArray) == 16);
static_assert(offsetof(Drop, count) == 8 && offsetof(Drop, location) == 16);

inline bool valid(const NameArray& a) {
    return a.count >= 0 && a.count <= 64 && a.capacity >= a.count && a.capacity <= 64
        && (a.count == 0 || (a.data && reinterpret_cast<std::uintptr_t>(a.data) % 8 == 0));
}
inline bool valid(const DropArray& a) {
    return a.count >= 0 && a.capacity >= a.count && a.capacity <= 65536
        && (a.capacity == 0 || (a.data && reinterpret_cast<std::uintptr_t>(a.data) % 8 == 0));
}
struct Settings {
    float drop_chance{0.5f};
    // Native loot rows use percentage points (0..100), not a 0..1 fraction.
    float native_drop_rate() const { return drop_chance * 100.0f; }
};
struct Plan { std::array<Drop, 4> drops{}; std::size_t count{}; };

// Per-invocation values only: no UObject, task, global dedupe or recipient cache.
template<class Resolve>
Plan plan(std::span<const std::uint64_t> passives, Location location,
          Settings settings, Resolve resolve) {
    Plan result;
    if (!std::isfinite(settings.drop_chance) || settings.drop_chance <= 0 || settings.drop_chance > 1
        || !std::isfinite(location.x) || !std::isfinite(location.y) || !std::isfinite(location.z))
        return result;
    for (auto passive : passives.first(std::min<std::size_t>(passives.size(), 4))) {
        if (!passive) continue;
        const std::optional<std::uint64_t> item = resolve(passive);
        if (!item || !*item) continue;
        bool duplicate{};
        for (std::size_t i = 0; i < result.count; ++i) duplicate |= result.drops[i].item == *item;
        if (duplicate) continue;
        result.drops[result.count++] = {*item, 1, 0, location};
    }
    return result;
}

template<class Grow>
bool append(DropArray& output, const Plan& additions, Grow grow) {
    if (!valid(output) || additions.count > 4 || output.count > 65536 - static_cast<int>(additions.count))
        return false;
    if (!additions.count) return true;
    const auto previous = output.count;
    // This is the engine's own TArray<Drop> growth ABI: Num is updated first.
    output.count += static_cast<std::int32_t>(additions.count);
    if (output.count > output.capacity) grow(output, previous);
    for (std::size_t i = 0; i < additions.count; ++i) output.data[previous + i] = additions.drops[i];
    return true;
}

template<class Calculate>
Plan native_counts(const Plan& base, Calculate calculate) {
    Plan result;
    for (std::size_t i = 0; i < base.count; ++i) {
        Drop entry = base.drops[i];
        calculate(entry); // engine receives base min=max=1 and applies its own rates
        if (entry.count > 0) result.drops[result.count++] = entry;
    }
    return result;
}
inline bool allowed(bool game_thread, bool reentrant) {
    return game_thread && !reentrant;
}

// Shared scoped value restoration for reentry guards and nested harvests.
template<class T>
class ScopedValue {
    T& target;
    T previous;
public:
    ScopedValue(T& value, T replacement) : target(value), previous(value) { target = replacement; }
    ~ScopedValue() { target = previous; }
    ScopedValue(const ScopedValue&) = delete;
    ScopedValue& operator=(const ScopedValue&) = delete;
};
} // namespace extra_implant_drops
