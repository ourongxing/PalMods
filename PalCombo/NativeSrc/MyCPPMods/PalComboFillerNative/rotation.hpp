#pragma once

#include <cmath>
#include <optional>

namespace pal_combo {

struct Ready {
    bool first{};
    bool second{};
    bool third{};
    std::optional<float> second_remaining_seconds{};
};

enum class Phase { ready_for_first, first_selected, waiting_for_second, second_selected };

// GetCoolTime is elapsed time, and GetCoolTimeRate is elapsed / total.
inline auto remaining_seconds(float elapsed, float rate) -> std::optional<float> {
    if (!std::isfinite(elapsed) || !std::isfinite(rate)
        || elapsed <= 0.0f || rate <= 0.0f || rate >= 1.0f) return std::nullopt;
    const float remaining = elapsed * (1.0f - rate) / rate;
    return std::isfinite(remaining) && remaining >= 0.0f
        ? std::optional<float>{remaining} : std::nullopt;
}

inline auto select(Ready ready, Phase& phase,
                   float early_start_seconds = 0.0f) -> std::optional<int> {
    // The native selector can be called repeatedly before an action begins.
    // Keep returning the same slot until its cooldown confirms the cast.
    if (phase == Phase::first_selected) {
        if (ready.first) return 0;
        phase = Phase::waiting_for_second;
    }
    if (phase == Phase::waiting_for_second) {
        if (!ready.second) return std::nullopt;
        phase = Phase::second_selected;
        return 1;
    }
    if (phase == Phase::second_selected) {
        if (ready.second) return 1;
        phase = Phase::ready_for_first;
    }

    const bool second_soon = ready.second_remaining_seconds
        && std::isfinite(*ready.second_remaining_seconds)
        && *ready.second_remaining_seconds > 0.0f
        && *ready.second_remaining_seconds <= early_start_seconds;
    if (ready.first && (ready.second || second_soon)) {
        phase = Phase::first_selected;
        return 0;
    }
    if (ready.third) return 2;
    return std::nullopt;
}

} // namespace pal_combo
