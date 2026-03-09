-- =====================================
-- Bootstrap lazy.nvim
-- =====================================
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not (vim.uv or vim.loop).fs_stat(lazypath) then
  vim.fn.system({
    "git",
    "clone",
    "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git",
    "--branch=stable", -- latest stable release
    lazypath,
  })
end
vim.opt.rtp:prepend(lazypath)

-- =====================================
-- Core options
-- =====================================
vim.opt.termguicolors    = true
vim.opt.background       = "dark"

vim.opt.number           = true
vim.opt.mouse            = "a"
vim.opt.encoding         = "utf-8"
vim.opt.scrolloff        = 3
vim.opt.backspace        = { "indent", "eol", "start" }
vim.opt.matchpairs:append("<:>")
vim.opt.laststatus       = 2
vim.opt.ruler            = true
vim.opt.wildmenu         = true
vim.opt.history          = 1000
vim.opt.hidden           = true
vim.opt.wrap             = true
vim.opt.undofile         = true
vim.opt.foldenable       = false
vim.opt.virtualedit      = "all"
vim.opt.guicursor        = "n-v-c:block,i-ci-ve:block,r-cr-o:block"
vim.opt.clipboard        = 'unnamedplus'

-- Tabs / indentation
vim.opt.tabstop     = 4
vim.opt.shiftwidth  = 4
vim.opt.softtabstop = 4
vim.opt.expandtab   = true
vim.opt.shiftround  = false

vim.api.nvim_create_autocmd("FileType", {
  pattern = "*",
  callback = function()
    vim.opt_local.formatoptions:remove("c")
    vim.opt_local.formatoptions:remove("r")
    vim.opt_local.formatoptions:remove("o")
  end,
})

-- List chars
vim.opt.list      = true
vim.opt.listchars = { tab = "»·", trail = "·", extends = "…", precedes = "…", nbsp = "␣" }

-- Search
vim.opt.hlsearch   = true
vim.opt.incsearch  = true
vim.opt.ignorecase = true
vim.opt.smartcase  = true

-- Bells & misc
vim.opt.visualbell = true
vim.opt.errorbells = false
vim.opt.modelines  = 0

vim.g.mapleader = " "

-- =====================================
-- Transparency + colors
-- =====================================
vim.api.nvim_create_autocmd("ColorScheme", {
  pattern = "*",
  callback = function()
    local set_hl = vim.api.nvim_set_hl
    set_hl(0, "Normal",      { bg = "NONE", ctermbg = "NONE" })
    set_hl(0, "NormalFloat", { bg = "NONE", ctermbg = "NONE" })
    set_hl(0, "NonText",     { bg = "NONE", ctermbg = "NONE" })
    set_hl(0, "EndOfBuffer", { bg = "NONE", ctermbg = "NONE" })
    set_hl(0, "SignColumn",  { bg = "NONE" })
    set_hl(0, "VertSplit",   { bg = "NONE" })
--    set_hl(0, "Comment",     { fg = "#88ff88", italic = true })
--    set_hl(0, "String",      { fg = "#00ff99" })
--    set_hl(0, "Constant",    { fg = "#00ff55" })
--    set_hl(0, "Identifier",  { fg = "#99ff99" })
--    set_hl(0, "Function",    { fg = "#33ff88", bold = true })
--    set_hl(0, "Todo",        { fg = "#ffff00", bg = "#004400", bold = true })
    set_hl(0, "Normal",     { fg = "#00ff00", bg = "NONE" })
    set_hl(0, "Comment",    { fg = "#90ee90" })
    set_hl(0, "Constant",   { fg = "#00ff00" })
    set_hl(0, "Identifier", { fg = "#90ee90" })
    set_hl(0, "StatusLine", { fg = "#000000", bg = "#00ff00" })
    set_hl(0, "StatusLineNC", { fg = "#000000", bg = "#00ff00" })
    set_hl(0, "CursorLine", { bg = "#001a00" })
    set_hl(0, "LineNr",       { fg = "#ffff00" })
    set_hl(0, "CursorLineNr", { fg = "#ffff00", bold = true })
    --set_hl(0, "LineNrAbove",  { fg = "#cccc00" })
    --set_hl(0, "LineNrBelow",  { fg = "#cccc00" })
    --vim.opt.cursorline = true
  end,
})
vim.cmd.colorscheme("torte")

vim.g.markdown_fenced_languages = {
  "bash=sh",
  "sh",
  "python",
  "lua",
  -- itd.
}

-- =====================================
-- Plugins via lazy.nvim
-- =====================================
require("lazy").setup({
--  -- Matrix / green phosphor style theme
--  {
--    "iruzo/matrix-nvim",
--    lazy = false,          -- load immediately
--    priority = 1000,       -- load before other plugins
--    config = function()
--      vim.cmd.colorscheme("matrix")
--      -- Extra green boost if needed (matrix is already very green)
--      vim.api.nvim_set_hl(0, "Normal",   { fg = "#00ff00", bg = "NONE" })
--      vim.api.nvim_set_hl(0, "CursorLine",{ bg = "#001100" })
--    end,
--  },
  {
    "folke/zen-mode.nvim",
    cmd = "ZenMode",
    opts = {
      window = {
        backdrop = 0.95,          -- shade the backdrop slightly (0 = fully dark, 1 = no shade)
        width = 80,              -- fixed width (or 0.8 for 80% of screen)
        height = 1.0,             -- full height
        options = {
          signcolumn = "no",      -- disable sign column
          number = false,         -- disable line numbers
          relativenumber = false, -- disable relative numbers
          cursorline = false,
          cursorcolumn = false,
          foldcolumn = "0",
          list = false,
        },
      },
      plugins = {
        -- disable some global plugins when in zen mode
        options = { enabled = true },
        twilight = { enabled = false },
        gitsigns = { enabled = false },
        tmux = { enabled = true },      -- if using tmux
      },
      -- callback when zen mode opens/closes
      on_open = function() -- optional: extra green/matrix feel
        vim.opt.laststatus = 0
        vim.opt.showtabline = 0
        vim.opt.signcolumn = "no"
      end,
      on_close = function()
        vim.opt.laststatus = 2
        vim.opt.showtabline = 1
      end,
    },
    keys = {
      { "<F7>", "<cmd>ZenMode<cr>", desc = "Toggle Zen Mode" },
    },
  },
  {
    "folke/twilight.nvim",
    opts = {
      -- your configuration comes here
      -- or leave it empty to use the default settings
      -- refer to the configuration section below
    }
  },
  -- Optional: even more green alternatives (uncomment if you want to try)
  -- { "ribru17/bamboo.nvim", config = function() vim.cmd.colorscheme("bamboo") end },
  -- { "luisiacc/the-matrix.nvim", config = function() vim.cmd.colorscheme("thematrix") end },

  -- You can add your old plugins here, e.g.:
  -- { "preservim/nerdtree", cmd = "NERDTreeToggle" },
})

-- =====================================
-- Autocommands / extras
-- =====================================
local aug = vim.api.nvim_create_augroup
local au  = vim.api.nvim_create_autocmd

-- Makefile: no expandtab
au("FileType", {
  pattern = "make",
  callback = function() vim.bo.expandtab = false end,
})

-- Markdown files
au({ "BufNewFile", "BufRead" }, {
  pattern = { "*.md", "TODO.txt", "CHANGELOG.txt", "NOTES.txt" },
  callback = function() vim.bo.filetype = "markdown" end,
})

-- Jump to last position
vim.api.nvim_create_autocmd("BufReadPost", {
  callback = function()
    local mark = vim.api.nvim_buf_get_mark(0, '"')
    local lcount = vim.api.nvim_buf_line_count(0)

    -- Only jump if mark is valid and not first line (avoids annoying jumps in new-ish files)
    if mark[1] > 1 and mark[1] <= lcount then
      -- Better way: use API instead of cmd.normal (more reliable)
      vim.api.nvim_win_set_cursor(0, { mark[1], mark[2] })

      -- Optional: unfold if needed and center view
      vim.cmd.normal({ "zv", bang = true })   -- open fold
      vim.cmd.normal({ "zz", bang = true })   -- center cursor line
    end
  end,
})

-- Highlight TODO/FIXME/XXX etc.
au("Syntax", {
  callback = function()
    vim.fn.matchadd("Todo", "\\v<(FIXME|NOTE|TODO|OPTIMIZE|XXX):")
  end,
})

-- F5: compile & run C++
vim.keymap.set("n", "<F5>", function()
  vim.cmd("w")
  local file = vim.fn.expand("%")
  local out  = vim.fn.expand("%<")
  local cmd = string.format(
    "g++ -std=c++23 -fmodules -O2 -Wall -Wextra -pedantic '%s' -o '%s' && echo -e \"\\n\\n\" && ./" .. out,
    vim.fn.shellescape(file),
    vim.fn.shellescape(out)
  )
  vim.cmd("!" .. cmd)
end, { desc = "Compile & run C++" })

-- Ctrl+C: copy
vim.keymap.set('v', '<C-c>', '"+y', { remap = false })

-- Hide ^M (new lines in mixed mode files)
--vim.api.nvim_create_autocmd("BufEnter", {
--  callback = function()
--    vim.cmd([[
--      syntax match HideCr /\r$/ conceal containedin=ALL
--      setlocal conceallevel=2
--      setlocal concealcursor=nvic
--    ]])
--  end,
--})

