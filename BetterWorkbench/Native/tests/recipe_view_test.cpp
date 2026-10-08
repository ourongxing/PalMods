#include "../src/recipe_view.hpp"
#include <iostream>
#include <vector>

using namespace better_workbench;
static void require(bool condition) { if (!condition) throw std::runtime_error("check failed"); }
template<class Function> static void rejected(Function function) {
    bool caught{};
    try { function(); } catch (const std::invalid_argument&) { caught = true; }
    require(caught);
}
int main() {
    try {
        std::array<std::byte, 0x90> original;
        original.fill(std::byte{0xa5});
        auto returned_copy = original;
        std::array<uint64_t, 5> materials{10, 11, 12, 13, 14};
        auto patch = slot_identities(materials, 999);
        apply_to_recipe_copy(returned_copy, patch, observed_layout);
        for (std::size_t offset = 0; offset < returned_copy.size(); ++offset)
            if (offset < 0x24 || offset >= 0x60) require(returned_copy[offset] == original[offset]);
        for (std::size_t index = 0; index < 5; ++index) {
            uint64_t name{}; int32_t presence{};
            std::memcpy(&name, returned_copy.data() + observed_layout.names[index], 8);
            std::memcpy(&presence, returned_copy.data() + observed_layout.counts[index], 4);
            require(name == materials[index] && presence == 1);
        }
        for (auto byte : original) require(byte == std::byte{0xa5});
        // Changing a later phase's identity list clears old, unused slots.
        std::array<uint64_t, 1> one{20};
        auto short_patch = slot_identities(one, 999);
        require(short_patch.names[4] == 999 && short_patch.presence[4] == 0);
        apply_to_recipe_copy(returned_copy, short_patch, observed_layout);
        rejected([&] { auto wrong = observed_layout; wrong.names[0] = 0x1c;
            apply_to_recipe_copy(returned_copy, patch, wrong); });
        const auto before = returned_copy;
        rejected([&] { apply_to_recipe_copy(std::span(returned_copy).first(0x60), patch, observed_layout); });
        require(returned_copy == before);
        auto corrupt = patch; corrupt.presence[0] = 6;
        rejected([&] { apply_to_recipe_copy(returned_copy, corrupt, observed_layout); });
        require(returned_copy == before);
        std::array<uint64_t, 6> too_many{1, 2, 3, 4, 5, 6};
        rejected([&] { slot_identities(too_many, 999); });
        std::array<uint64_t, 2> repeated{1, 1};
        rejected([&] { slot_identities(repeated, 999); });
        std::array<uint64_t, 1> empty{999};
        rejected([&] { slot_identities(empty, 999); });
        // Own scalar copies, never references into a caller's plan vector.
        materials[0] = 42;
        require(patch.names[0] == 10);
        std::cout << "Recipe copy isolation, metadata preservation, bounds and slot identity checks passed.\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << error.what() << '\n'; return 1;
    }
}
