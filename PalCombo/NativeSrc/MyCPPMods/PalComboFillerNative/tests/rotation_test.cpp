#include "../rotation.hpp"
#include <cassert>

using namespace pal_combo;

int main() {
    Phase phase = Phase::ready_for_first;

    // Repeated native selections before slot 1 starts must remain slot 1.
    assert(select({true, true, true}, phase, 3.0f) == 0);
    assert(phase == Phase::first_selected);
    assert(select({true, true, true}, phase, 3.0f) == 0);
    assert(phase == Phase::first_selected);
    assert(select({false, true, true}, phase, 3.0f) == 1);
    assert(phase == Phase::second_selected);
    assert(select({false, true, true}, phase, 3.0f) == 1);
    assert(select({false, false, true}, phase, 3.0f) == 2);
    assert(phase == Phase::ready_for_first);

    // Slot 2 never starts a new pair by itself. Slot 3 may fill the gap.
    assert(select({false, true, true}, phase, 3.0f) == 2);
    assert(select({false, true, false}, phase, 3.0f) == std::nullopt);
    assert(phase == Phase::ready_for_first);

    // An early start reserves the next skill for slot 2, with no slot 3 in between.
    assert(select({true, false, true, 2.5f}, phase, 3.0f) == 0);
    assert(select({true, false, true, 0.5f}, phase, 3.0f) == 0);
    assert(select({false, false, true, 0.5f}, phase, 3.0f) == std::nullopt);
    assert(phase == Phase::waiting_for_second);
    assert(select({false, true, true}, phase, 3.0f) == 1);
    assert(phase == Phase::second_selected);
    assert(select({false, false, true}, phase, 3.0f) == 2);
    assert(phase == Phase::ready_for_first);

    // Beyond the configured window, wait for the pair while allowing filler.
    assert(select({true, false, true, 3.5f}, phase, 3.0f) == 2);
    assert(select({true, false, false, 3.5f}, phase, 3.0f) == std::nullopt);
    assert(select({true, false, true, 2.5f}, phase, 0.0f) == 2);

    // GetCoolTime advances from zero; GetCoolTimeRate is elapsed / total.
    assert(remaining_seconds(5.0f, 0.25f) == 15.0f);
    assert(remaining_seconds(0.0f, 0.0f) == std::nullopt);
    assert(remaining_seconds(5.0f, 1.0f) == std::nullopt);
}
