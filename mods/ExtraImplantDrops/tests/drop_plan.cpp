#include "../native/src/drop_plan.hpp"
#include "../native/src/implant_rules.hpp"
#include "../native/src/config_value.hpp"
#include <cassert>
#include <iostream>
#include <vector>
#include <string_view>
using namespace extra_implant_drops;

int main() {
    static_assert(implant_rules.size() == 28);
    for (std::size_t i = 0; i < implant_rules.size(); ++i) {
        assert(std::wstring_view(implant_rules[i].passive) != L"SomeSkill");
        assert(std::wstring_view(implant_rules[i].item).starts_with(L"PalPassiveSkillChange_Consumable_"));
        for (std::size_t j = 0; j < i; ++j)
            assert(std::wstring_view(implant_rules[i].passive) != implant_rules[j].passive);
    }
    const Location position{1, 2, 3};
    assert(Settings{}.native_drop_rate() == 50.0f);
    assert(Settings{0.25f}.native_drop_rate() == 25.0f);
    assert(Settings{1.0f}.native_drop_rate() == 100.0f);
    assert(parse_drop_chance(L"0.5") == 0.5f);
    assert(parse_drop_chance(L"0.25") == 0.25f);
    assert(parse_drop_chance(L" 1 ") == 1.0f);
    assert(parse_drop_chance(L"0") == 0.0f);
    for (auto invalid : {L"-0.1", L"1.1", L"50", L"NaN", L"inf", L"0.25invalid", L""})
        assert(parse_drop_chance(invalid) == 0.5f);
    auto resolve = [](std::uint64_t skill) -> std::optional<std::uint64_t> {
        if (skill > 4) return {}; return skill + 100;
    };
    const std::array<std::uint64_t, 4> skills{1, 2, 3, 4};
    const auto four = plan(skills, position, {}, resolve);
    assert(four.count == 4 && four.drops[3].item == 104 && four.drops[3].location.z == 3);
    const std::array<std::uint64_t, 4> duplicate{1, 1, 0, 99};
    assert(plan(duplicate, position, {}, resolve).count == 1);
    assert(plan(skills, position, {0}, resolve).count == 0);
    assert(plan(skills, position, {-0.1f}, resolve).count == 0);
    assert(plan(skills, position, {1.1f}, resolve).count == 0);
    assert(plan(skills, position, {1.0f}, resolve).count == 4);
    assert(plan(skills, position, {0.25f}, resolve).count == 4);
    assert(!allowed(false, false));
    assert(!allowed(true, true));
    assert(allowed(true, false)); // no caller, trainer or ownership restriction
    int native_calls{};
    const auto multiplied = native_counts(four, [&](Drop& entry) {
        assert(entry.count == 1); ++native_calls; entry.count = 3;
    });
    assert(native_calls == 4 && multiplied.count == 4 && multiplied.drops[0].count == 3);
    const auto suppressed = native_counts(four, [](Drop& entry) { entry.count = 0; });
    assert(suppressed.count == 0); // game rules may suppress an implant
    const auto mixed = native_counts(four, [](Drop& entry) { entry.count = entry.item == 101 ? 0 : 2; });
    assert(mixed.count == 3 && mixed.drops[0].item == 102 && mixed.drops[0].count == 2);
    bool reentry = false;
    {
        ScopedValue outer(reentry, true);
        { ScopedValue inner(reentry, true); assert(reentry); }
        assert(reentry);
    }
    assert(!reentry);

    // Stress independent events with allocator relocation. Old native drops
    // and their locations must survive; source objects may disappear immediately.
    std::uint64_t received{};
    for (int event = 0; event < 10000; ++event) {
        std::vector<Drop> storage{{42, 3, 0, {10, 20, 30}}};
        DropArray output{storage.data(), 1, 1};
        int growths{};
        const auto grow = [&](DropArray& a, int previous) {
            assert(previous == 1 && a.count == 5);
            storage.resize(a.count);
            a.data = storage.data(); a.capacity = a.count; ++growths;
        };
        assert(append(output, four, grow));
        assert(growths == 1 && output.count == 5);
        assert(output.data[0].item == 42 && output.data[0].count == 3 && output.data[0].location.y == 20);
        for (int i = 1; i < output.count; ++i) {
            assert(output.data[i].item == 100 + i && output.data[i].count == 1);
            received += output.data[i].count;
        }
    }
    assert(received == 40000);
    std::array<Drop, 8> reserved{};
    DropArray output{reserved.data(), 0, 8};
    assert(append(output, four, [](DropArray&, int) { assert(false); }));
    assert(output.count == 4); // a Pal with no normal drops still earns implants
    DropArray invalid{nullptr, 1, 1};
    assert(!append(invalid, four, [](DropArray&, int) { assert(false); }));
    NameArray invalid_passives{nullptr, 1, 4};
    assert(!valid(invalid_passives));
    std::cout << "PASS: 10000 rapid events, 40000 implants, native preservation, relocation, scope and malformed inputs\n";
}
