#pragma once
#include <algorithm>
#include <cmath>
#include <cstdint>
#include <limits>

namespace better_expedition {
inline double time_ratio(std::int64_t now, std::int64_t start, std::int64_t complete) {
    if (start < 0 || complete <= start || now <= start) return 0;
    return static_cast<double>(now - start) / static_cast<double>(complete - start);
}
// Stochastic rounding preserves fractional rewards in expectation, including
// expeditions too short to earn one whole item. Full vanilla runs are exact.
inline std::int32_t quantity(std::int32_t vanilla, double ratio, double random) {
    if (vanilla <= 0 || !std::isfinite(ratio) || ratio <= 0) return 0;
    const double value = vanilla * ratio;
    constexpr auto maximum = std::numeric_limits<std::int32_t>::max();
    if (value >= maximum) return maximum;
    const auto integral = static_cast<std::int32_t>(std::floor(value));
    return integral + (random < value - integral ? 1 : 0);
}
}
