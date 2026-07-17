#ifndef LTREE_RENDER_FILES_H
#define LTREE_RENDER_FILES_H

#include "core/config.h"
#include "scan/exttable.h"

/* prints the FILES: per-extension summary table. */
void print_files_summary(const ExtTable *ext, const Config *cfg);

#endif
