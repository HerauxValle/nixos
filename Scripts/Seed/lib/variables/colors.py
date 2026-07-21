"""
lib/variables/colors.py — ANSI color constants
"""

RESET   = "\033[0m"
BOLD    = "\033[1m"
DIM     = "\033[2m"
ITALIC  = "\033[3m"
UNDER   = "\033[4m"

# --- standard foreground ---
BLACK   = "\033[30m"
RED     = "\033[31m"
GREEN   = "\033[32m"
YELLOW  = "\033[33m"
BLUE    = "\033[34m"
MAGENTA = "\033[35m"
CYAN    = "\033[36m"
WHITE   = "\033[37m"

# --- bright foreground ---
BBLACK   = "\033[90m"
BRED     = "\033[91m"
BGREEN   = "\033[92m"
BYELLOW  = "\033[93m"
BBLUE    = "\033[94m"
BMAGENTA = "\033[95m"
BCYAN    = "\033[96m"
BWHITE   = "\033[97m"

# --- extra colors via 256-color ---
def _fg(n: int) -> str:
    return f"\033[38;5;{n}m"

ORANGE      = _fg(214)
PINK        = _fg(213)
PURPLE      = _fg(135)
VIOLET      = _fg(141)
INDIGO      = _fg(54)
TURQUOISE   = _fg(45)
TEAL        = _fg(37)
LIME        = _fg(154)
OLIVE       = _fg(100)
MAROON      = _fg(88)
NAVY        = _fg(17)
AQUA        = _fg(51)
GOLD        = _fg(220)
SILVER      = _fg(250)
BRONZE      = _fg(130)
CORAL       = _fg(209)
SALMON      = _fg(210)
KHAKI       = _fg(185)
BEIGE       = _fg(230)
MINT        = _fg(121)
LAVENDER    = _fg(183)
PEACH       = _fg(223)
PLUM        = _fg(96)
CHOCOLATE   = _fg(94)
CRIMSON     = _fg(160)

# --- semantic defaults ---
# change these to restyle the entire UI at once
DEFAULT         = CYAN       # primary value color
DEFAULT_DIM     = BBLACK     # secondary / muted text
DEFAULT_LABEL   = BWHITE     # column headers, labels
DEFAULT_SUCCESS = GREEN      # success / created / ok
DEFAULT_ERROR   = BRED       # error codes
DEFAULT_WARN    = ORANGE     # warnings, details
DEFAULT_CMD     = GREEN      # command names in help
DEFAULT_FLAG    = CYAN       # flag names in help
DEFAULT_DESC    = BBLACK     # descriptions in help
DEFAULT_INDEX   = BBLACK     # row index numbers


def c(color: str, text: str) -> str:
    """Wrap text in color + reset."""
    return f"{color}{text}{RESET}"