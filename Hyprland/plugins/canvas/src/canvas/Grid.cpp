/* &desc: "Grid layout implementation -- ceil(sqrt(n)) columns, row-major slot assignment." */
#include "Grid.hpp"

#include <cmath>
#include <algorithm>

int Grid::columnsFor(std::size_t count) {
    if (count == 0)
        return 1;

    return std::max<int>(1, static_cast<int>(std::ceil(std::sqrt(static_cast<double>(count)))));
}

GridSlot Grid::slotFor(std::size_t index, std::size_t count) {
    const int cols = columnsFor(count);

    return GridSlot{
        .col = static_cast<int>(index) % cols,
        .row = static_cast<int>(index) / cols,
    };
}
