#pragma once
#include <array>
#include <cmath>

namespace bond {
// Additional growth, after the vanilla awakening term and before native scaling.
inline float growth_delta(const std::array<int, 3>& base, const std::array<float, 3>& growth, int stat) {
    double total = 0;
    std::array<double, 3> final{};
    for (int i = 0; i < 3; ++i) {
        if (base[i] <= 0 || !std::isfinite(growth[i]) || growth[i] < 0) return 0;
        final[i] = base[i] + 10.0 * growth[i];
        total += final[i];
    }
    if (stat < 0 || stat >= 3 || total >= 450.0 || total <= 0) return 0;
    return static_cast<float>(final[stat] * (450.0 / total - 1.0) / 10.0);
}
inline float gated_growth(const std::array<int,3>& base,const std::array<float,3>& growth,int stat,bool awakened) {
    return growth[stat]+(awakened?growth_delta(base,growth,stat):0.f);
}
}
