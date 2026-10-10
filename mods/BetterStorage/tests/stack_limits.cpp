#include "../native/src/stack_limits.hpp"
#include <cassert>

int main() {
    // Money's vanilla limit is higher than the mod's ordinary-item minimum.
    assert(storage::expanded_limit(99999999, false) == 99999999);
    assert(storage::expanded_limit(200000, false) == 200000);
    assert(storage::expanded_limit(99999, false) == 99999);
    assert(storage::expanded_limit(9999, false) == 99999);
    assert(storage::expanded_limit(1, false) == 1);
    assert(storage::expanded_limit(0, false) == 0);
    assert(storage::expanded_limit(100, true) == 100);
    assert(storage::expanded_limit(99999999, true) == 99999999);
}
