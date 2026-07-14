local opt = vim.opt

-- Line numbers
opt.number         = true   -- show absolute line number on current line
opt.relativenumber = true   -- show relative numbers on all other lines

-- Indentation
opt.tabstop    = 4          -- tab = 4 spaces
opt.shiftwidth = 4          -- indent = 4 spaces
opt.expandtab  = true       -- use spaces instead of tabs
opt.smartindent = true      -- auto-indent new lines

-- Search
opt.ignorecase = true       -- case-insensitive search
opt.smartcase  = true       -- case-sensitive if uppercase used
opt.hlsearch   = false      -- don't highlight all matches after search
opt.incsearch  = true       -- highlight as you type

-- Appearance
opt.termguicolors = true    -- enable 24-bit color
opt.signcolumn    = "yes"   -- always show sign column (prevents layout shift)
opt.cursorline    = true    -- highlight current line
opt.wrap          = false   -- don't wrap long lines

-- Splits
opt.splitbelow = true       -- horizontal splits open below
opt.splitright = true       -- vertical splits open to the right

-- Scrolling (see behavior/scrolloff.lua for insert mode enforcement)
opt.scrolloff = 30          -- keep 30 lines above/below cursor at all times

-- Behaviour
opt.clipboard  = "unnamedplus"  -- use system clipboard for all yank/paste
opt.updatetime = 300            -- faster CursorHold (used for signature help)
opt.swapfile   = false          -- disable swap files
opt.undofile   = true           -- persist undo history across sessions

-- UI
opt.shortmess:append("I")       -- disable intro/splash screen

-- ============================================================
-- Startup behaviour (see behavior/ for implementation)
-- ============================================================

vim.g.startup_insert     = true   -- start in insert mode on launch

-- Panel autostart (only active when save_ui_state = false)
vim.g.autostart_explorer = true   -- open neo-tree on launch
vim.g.autostart_terminal = false  -- open terminal on launch
vim.g.autostart_undotree = false  -- open undotree on launch

-- UI state persistence (overrides autostart_* when enabled)
vim.g.save_ui_state      = true   -- save/restore which panels are open
vim.g.save_widget_sizes  = true   -- save/restore panel sizes (width/height)
vim.g.save_mode          = true   -- save/restore last mode (insert/normal)

-- Autosave (see behavior/autosave.lua for implementation)
vim.g.autosave_enabled = true   -- save automatically after typing stops
vim.g.autosave_delay   = 1000  -- ms of inactivity before saving

-- Undotree
vim.g.undotree_WindowLayout = 3   -- show undotree on the right side
