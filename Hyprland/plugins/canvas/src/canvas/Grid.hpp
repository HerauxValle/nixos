/* &desc: "Deterministic workspace -> grid-slot layout, pure logic, no Hyprland types." */
#pragma once

#include <cstddef>

struct GridSlot {
    int col = 0;
    int row = 0;
};

namespace Grid {
    // Square-ish layout: ceil(sqrt(count)) columns, enough rows to fit the
    // rest. Deterministic in workspace order -- callers pass workspaces in
    // whatever stable order they already iterate them in (e.g. by ID) and
    // get back slots in the same order.
    int      columnsFor(std::size_t count);
    GridSlot slotFor(std::size_t index, std::size_t count);
}
