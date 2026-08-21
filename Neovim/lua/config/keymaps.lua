vim.g.mapleader = " "

local map = function(mode, lhs, rhs, desc)
    vim.keymap.set(mode, lhs, rhs, { noremap = true, silent = true, desc = desc })
end

-- Reload config
map("n", "<leader>sv", "<cmd>source $MYVIMRC<cr>", "Reload config")

-- New empty buffer
map("n", "<leader>n", "<cmd>enew<cr>", "New buffer")

-- Ctrl+Z undo, Ctrl+Y redo
map("n", "<C-z>", "u",        "Undo")
map("n", "<C-y>", "<C-r>",    "Redo")
map("i", "<C-z>", "<Esc>ua",  "Undo")

-- Ctrl+S save in all modes
map("n", "<C-s>", "<cmd>w<cr>",          "Save")
map("i", "<C-s>", "<Esc><cmd>w<cr>a",   "Save")
map("v", "<C-s>", "<Esc><cmd>w<cr>",    "Save")

-- Save / quit
map("n", "<leader>w", "<cmd>w<cr>",  "Save")
map("n", "<leader>q", "<cmd>q<cr>",  "Quit")
map("n", "<leader>Q", "<cmd>q!<cr>", "Force quit")

-- Create splits
map("n", "<leader>sp",  "<cmd>split<cr>",  "Split horizontal")
map("n", "<leader>vsp", "<cmd>vsplit<cr>", "Split vertical")
map("n", "<leader>clo", "<cmd>close<cr>", "Close split")

-- Move between splits
map("n", "<C-h>", "<C-w>h", "Move to left split")
map("n", "<C-j>", "<C-w>j", "Move to split below")
map("n", "<C-k>", "<C-w>k", "Move to split above")
map("n", "<C-l>", "<C-w>l", "Move to right split")

-- Run current file
map("n", "<leader>rr", function()
    local ft = vim.bo.filetype
    local file = vim.fn.expand("%:p")
    local cmd = ({
        python     = "python " .. file,
        sh         = "bash " .. file,
        fish       = "fish " .. file,
        javascript = "node " .. file,
        html       = "xdg-open " .. file,
        markdown   = "xdg-open " .. file,
        typescript = "ts-node " .. file,
        rust       = "cargo run",
        go         = "go run " .. file,
        c          = "gcc " .. file .. " -o /tmp/nvim_out && /tmp/nvim_out",
        cpp        = "g++ " .. file .. " -o /tmp/nvim_out && /tmp/nvim_out",
    })[ft]
    if cmd then
        vim.cmd("ToggleTerm direction=horizontal")
        vim.defer_fn(function()
            vim.fn.chansend(vim.b.terminal_job_id, cmd .. "\n")
        end, 300)
    else
        vim.notify("No run command for filetype: " .. ft, vim.log.levels.WARN)
    end
end, "Run current file")

-- Exit terminal mode
map("t", "<Esc>", "<C-\\><C-n>", "Exit terminal mode")

-- Alt+: enters command mode from any mode
map("n", "<D-;>", ":", "Command mode")
map("i", "<D-;>", "<Esc>:", "Command mode")
map("v", "<D-;>", "<Esc>:", "Command mode")
map("t", "<D-;>", "<C-\\><C-n>:", "Command mode")

-- Move lines in visual mode
map("v", "J", ":m '>+1<cr>gv=gv", "Move line down")
map("v", "K", ":m '<-2<cr>gv=gv", "Move line up")

-- Keep cursor centered when jumping
map("n", "<C-d>", "<C-d>zz", "Scroll down (centered)")
map("n", "<C-u>", "<C-u>zz", "Scroll up (centered)")
