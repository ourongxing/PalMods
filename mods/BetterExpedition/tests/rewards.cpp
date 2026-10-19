#include "../native/src/RewardRules.hpp"
#include <cassert>
#include <limits>
using namespace better_expedition;
int main() {
    assert(time_ratio(150, 100, 200) == .5);
    assert(time_ratio(200, 100, 200) == 1);
    assert(time_ratio(400, 100, 200) == 3);
    assert(time_ratio(90, 100, 200) == 0);
    assert(time_ratio(100, 100, 100) == 0);
    assert(time_ratio(100, -1, 200) == 0);
    assert(quantity(6, 1, 0) == 6);
    assert(quantity(6, 2, .99) == 12);
    assert(quantity(6, .5, .99) == 3);
    assert(quantity(1, .25, .249) == 1);
    assert(quantity(1, .25, .25) == 0);
    assert(quantity(999, 0, 0) == 0);
    assert(quantity(1, std::numeric_limits<double>::quiet_NaN(), 0) == 0);
    assert(quantity(2, 1e20, .5) == std::numeric_limits<int>::max());
    int sum{};
    for (int i = 0; i < 10000; ++i) sum += quantity(3, .125, (i + .5) / 10000.);
    assert(sum == 3750);
}
