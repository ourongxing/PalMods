#include "../native/src/storage_transfer.hpp"
#include "../native/src/transport_priority.hpp"
#ifdef NDEBUG
#undef NDEBUG
#endif
#include <cassert>
#include <iostream>
#include <vector>

template <typename T, std::size_t N>
void put(std::array<std::byte, N>& data, std::size_t offset, T value) {
    std::memcpy(data.data() + offset, &value, sizeof(value));
}
struct Fixture {
    std::array<std::array<std::byte, 0x180>, 4> slots{};
    std::array<std::array<std::byte, 0x90>, 2> containers{};
    std::array<void*, 4> slot_ptrs{};
    std::array<void*, 2> container_ptrs{};
    std::array<std::byte, 16> list{};
    std::array<std::byte, 24> context{};
    std::array<std::byte, 0x2c> item{};
    int manager{}, transaction{}, source{};
    void* manager_pointer = &manager;
    int capacity[4]{100, 100, 10, 100};
    bool denied[4]{};
    std::vector<int> attempts;
    Fixture() {
        for (int i = 0; i < 4; ++i) {
            slot_ptrs[i] = slots[i].data();
            put(slots[i], 0x11c, i);
            put(slots[i], 0x118, i);
        }
        for (int c = 0; c < 2; ++c) {
            container_ptrs[c] = containers[c].data();
            put(containers[c], 0x70, slot_ptrs.data() + c * 2);
            put(containers[c], 0x78, 2);
        }
        put(list, 0, container_ptrs.data()); put(list, 8, 2);
        put(context, 0, list.data()); put(context, 8, &manager_pointer);
        put(context, 16, &transaction);
        put(item, 0, std::uint64_t{7});
        put(slots[2], 0x12c, std::uint64_t{7}); put(slots[2], 0x154, 8);
    }
    int count(int index) { return storage::read<int>(slots[index].data(), 0x154); }
    void run(int amount) {
        put(item, 0x28, amount);
        storage::transfer(context.data(), &source, item.data(), 0,
            [&](void* slot) { return capacity[storage::read<int>(slot, 0x11c)]; },
            [&](void* m, int quantity, const void* destination, const void* origin, void* tx) {
                assert(m == &manager && origin == &source && tx == &transaction);
                const int index = storage::read<int>(destination, 0);
                assert(storage::read<int>(destination, 16) == index);
                attempts.push_back(index);
                if (denied[index]) return; // Official transfer rejects permissions/filters.
                const int moved = std::min(quantity, capacity[index] - count(index));
                put(slots[index], 0x154, count(index) + moved);
                put(slots[index], 0x12c, std::uint64_t{7});
            });
    }
};
int main() {
    { Fixture f;
    auto rank = [&](std::uint8_t priority) {
        return storage::transport_priority(priority, [&] {
            return storage::has_transport_stack(f.containers[1].data(), 7, 0,
                [&](void* slot) { return f.capacity[storage::read<int>(slot, 0x11c)]; },
                [&](void* slot) { return !f.denied[storage::read<int>(slot, 0x11c)]; });
        });
    };
    assert(storage::transport_priority(5, []() -> bool {
        assert(false && "Food/production priorities must not scan chest slots"); return false;
    }) == 5);
    assert(rank(2) == 2.5f && rank(3) == 3.5f);
    assert(rank(1) == 1.5f && rank(4) == 4 && rank(5) == 5 && rank(6) == 6 && rank(7) == 7);
    assert(rank(2) < 3); // A stack never overrides the configured priority tier.
    f.denied[2] = true; assert(rank(2) == 2); f.denied[2] = false;
    put(f.slots[2], 0x154, 10); assert(rank(2) == 2); // Full stack.
    put(f.slots[2], 0x154, 0); assert(rank(2) == 2); // Empty slot.
    put(f.slots[2], 0x154, 8);
    put(f.slots[2], 0x12c, std::uint64_t{8}); assert(rank(2) == 2); // Other item.
    put(f.slots[2], 0x12c, std::uint64_t{7});
    put(f.slots[2], 0x144, 1); assert(rank(2) == 2); // Dynamic instance.
    put(f.slots[2], 0x144, 0);
    put(f.slots[2], 8, std::uint32_t{0x60000000}); assert(rank(2) == 2);
    }
    { Fixture f; f.run(1);
    assert(f.count(2) == 9 && f.count(0) == 0 && f.attempts == std::vector<int>{2});
    }
    { Fixture f; f.run(7);
    assert(f.count(2) == 10 && f.count(0) == 5 && f.attempts == (std::vector<int>{2, 0}));
    }
    { Fixture f; f.denied[2] = true; f.denied[0] = true; f.run(7);
    assert(f.count(2) == 8 && f.count(0) == 0 && f.count(1) == 7);
    }
    { Fixture f; put(f.slots[2], 0x144, 1); f.run(1);
    assert(f.count(2) == 8 && f.count(0) == 1); // Different dynamic item never merges.
    }
    { Fixture f; put(f.slots[2], 8, std::uint32_t{0x60000000}); f.run(1);
    assert(f.count(2) == 8 && f.count(0) == 1); // Invalid UObject is skipped.
    }
    { Fixture f; f.run(0); assert(f.attempts.empty());
    }
    std::cout << "PASS: transport stack preference with vanilla priority tiers, full/empty/denied/dynamic/invalid slots; cross-container transfer and overflow\n";
}
