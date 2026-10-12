#pragma once
#include <cmath>
#include <cwchar>
#include <cwctype>

namespace extra_implant_drops {
inline float parse_drop_chance(const wchar_t* text) {
    if (!text) return 0.5f;
    wchar_t* end{};
    const float value = std::wcstof(text, &end);
    if (end == text) return 0.5f;
    while (std::iswspace(*end)) ++end;
    return *end == L'\0' && std::isfinite(value) && value >= 0.0f && value <= 1.0f
        ? value : 0.5f;
}
} // namespace extra_implant_drops
