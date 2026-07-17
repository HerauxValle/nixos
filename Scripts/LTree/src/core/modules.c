/* &desc: "Defines MODULE_TABLE (every -o token's name/id/category) and module_lookup(), the case-insensitive lookup every -o/-oE/--stdout parser and every renderer uses." */
#include "core/modules.h"
#include <strings.h>
#include <stddef.h>

const ModuleDef MODULE_TABLE[MOD_COUNT] = {
    [MOD_LINES]  = { "LINES",       MOD_LINES,  MODCAT_COLUMN  },
    [MOD_CHARS]  = { "CHARS",       MOD_CHARS,  MODCAT_COLUMN  },
    [MOD_PERM]   = { "PERMISSIONS", MOD_PERM,   MODCAT_COLUMN  },
    [MOD_SIZE]   = { "SIZE",        MOD_SIZE,   MODCAT_COLUMN  },
    [MOD_DATE]   = { "DATE",        MOD_DATE,   MODCAT_COLUMN  },
    [MOD_EXT]    = { "EXT",         MOD_EXT,    MODCAT_COLUMN  },
    [MOD_HASH]   = { "HASH",        MOD_HASH,   MODCAT_COLUMN  },
    [MOD_TOTAL]  = { "TOTAL",       MOD_TOTAL,  MODCAT_SUMMARY },
    [MOD_FILES]  = { "FILES",       MOD_FILES,  MODCAT_SUMMARY },
    [MOD_DEBUG]  = { "DEBUG",       MOD_DEBUG,  MODCAT_SUMMARY },
    [MOD_DIFF]   = { "DIFF",        MOD_DIFF,   MODCAT_DIFF    },
    [MOD_TREE]   = { "TREE",        MOD_TREE,   MODCAT_TOGGLE  },
    [MOD_HIDDEN] = { "HIDDEN",      MOD_HIDDEN, MODCAT_TOGGLE  },
};

const ModuleDef *module_lookup(const char *name) {
    for (int i = 0; i < MOD_COUNT; i++) {
        if (strcasecmp(name, MODULE_TABLE[i].name) == 0) return &MODULE_TABLE[i];
    }
    return NULL;
}
