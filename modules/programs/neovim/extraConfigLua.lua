-- ========================================================================
-- SYSTEM CONFIGURATION
-- ========================================================================

-- Completely disable netrw to prevent FileExplorer autocommand conflicts
vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1

-- WSL clipboard configuration
-- WSLg sets DISPLAY=:0 which makes Neovim try X11 clipboard tools
-- We detect WSL via environment variable (more reliable than has('wsl'))
-- and force Windows native clipboard tools
local is_wsl = vim.fn.getenv('WSL_DISTRO_NAME') ~= vim.NIL
if is_wsl then
  vim.g.clipboard = {
    name = 'WslClipboard',
    copy = {
      ['+'] = 'clip.exe',
      ['*'] = 'clip.exe',
    },
    paste = {
      ['+'] = 'powershell.exe -NoLogo -NoProfile -c [Console]::Out.Write($(Get-Clipboard -Raw).tostring().replace("`r", ""))',
      ['*'] = 'powershell.exe -NoLogo -NoProfile -c [Console]::Out.Write($(Get-Clipboard -Raw).tostring().replace("`r", ""))',
    },
    cache_enabled = 0,
  }
end

-- ========================================================================
-- LSP CONFIGURATION
-- ========================================================================

-- Set up proper keymaps for LSP
vim.api.nvim_create_autocmd('LspAttach', {
  group = vim.api.nvim_create_augroup('UserLspConfig', {}),
  callback = function(ev)
    local opts = { buffer = ev.buf, silent = true }

    -- Additional LSP keymaps not covered by the main config
    vim.keymap.set('n', '<leader>wa', vim.lsp.buf.add_workspace_folder, opts)
    vim.keymap.set('n', '<leader>wr', vim.lsp.buf.remove_workspace_folder, opts)
    vim.keymap.set('n', '<leader>wl', function()
      print(vim.inspect(vim.lsp.buf.list_workspace_folders()))
    end, opts)
  end,
})

-- Configure diagnostic display with less aggressive highlighting
vim.diagnostic.config({
  virtual_text = {
    prefix = '●',
    -- Only show errors in virtual text, not warnings
    severity = vim.diagnostic.severity.ERROR,
  },
  signs = {
    text = {
      [vim.diagnostic.severity.ERROR] = " ",
      [vim.diagnostic.severity.WARN] = " ",
      [vim.diagnostic.severity.HINT] = " ",
      [vim.diagnostic.severity.INFO] = " "
    }
  },
  -- Disable underlining for less visual noise
  underline = false,
  update_in_insert = false,
  severity_sort = true,
  -- Float window for diagnostics on hover instead of inline
  float = {
    source = 'always',
    border = 'rounded',
  },
})

-- ========================================================================
-- LANGUAGE-SPECIFIC AUTOCMDS
-- ========================================================================

-- Reduce red highlighting for C/C++ files
vim.api.nvim_create_autocmd("FileType", {
  pattern = {"c", "cpp", "h", "hpp"},
  callback = function()
    -- Tone down semantic highlighting
    vim.api.nvim_set_hl(0, '@lsp.type.macro.c', { link = 'Macro' })
    vim.api.nvim_set_hl(0, '@lsp.type.macro.cpp', { link = 'Macro' })

    -- Override error highlighting to be less aggressive
    vim.api.nvim_set_hl(0, 'DiagnosticError', { fg = '#db4b4b', bg = 'NONE', undercurl = true })
    vim.api.nvim_set_hl(0, 'DiagnosticWarn', { fg = '#e0af68', bg = 'NONE' })
    vim.api.nvim_set_hl(0, 'DiagnosticInfo', { fg = '#0db9d7', bg = 'NONE' })
    vim.api.nvim_set_hl(0, 'DiagnosticHint', { fg = '#10b981', bg = 'NONE' })

    -- Remove underlines from diagnostics in C/C++ files
    vim.api.nvim_set_hl(0, 'DiagnosticUnderlineError', { sp = '#db4b4b', undercurl = true })
    vim.api.nvim_set_hl(0, 'DiagnosticUnderlineWarn', { sp = '#e0af68', undercurl = false })
    vim.api.nvim_set_hl(0, 'DiagnosticUnderlineInfo', { sp = '#0db9d7', undercurl = false })
    vim.api.nvim_set_hl(0, 'DiagnosticUnderlineHint', { sp = '#10b981', undercurl = false })

    -- Reduce severity of certain diagnostics
    vim.diagnostic.config({
      virtual_text = {
        severity = { min = vim.diagnostic.severity.ERROR },
      },
      underline = {
        severity = { min = vim.diagnostic.severity.ERROR },
      },
    }, vim.api.nvim_get_current_buf())
  end,
})

-- Set proper errorformat for C/C++ compilers and build tools
vim.api.nvim_create_autocmd("FileType", {
  pattern = {"c", "cpp"},
  callback = function()
    -- Enhanced errorformat for GCC/Clang/Ninja/CMake/Meson
    vim.bo.errorformat = table.concat({
      -- GCC/Clang patterns
      "%f:%l:%c: %trror: %m",     -- filename:line:col: error: message
      "%f:%l:%c: %tarning: %m",   -- filename:line:col: warning: message
      "%f:%l:%c: %tote: %m",       -- filename:line:col: note: message
      "%f:%l:%c: %m",              -- filename:line:col: message
      "%f:%l: %trror: %m",         -- filename:line: error: message
      "%f:%l: %tarning: %m",       -- filename:line: warning: message
      "%f:%l: %tote: %m",          -- filename:line: note: message
      "%f:%l: %m",                 -- filename:line: message
      "%f: %trror: %m",            -- filename: error: message
      "%f: %tarning: %m",          -- filename: warning: message
      "%f: %m",                    -- filename: message
      -- Make patterns
      "make: *** %m",              -- make errors
      "make[%*\\d]: *** %m",        -- make recursive errors
      "make: %m",                  -- make general messages
      -- Ninja patterns
      "ninja: %trror: %m",         -- ninja errors
      "ninja: %m",                 -- ninja messages
      "FAILED: %f:%l:%c: %m",      -- ninja compilation failures
      "FAILED: %m",               -- ninja general failures
      -- CMake patterns
      "CMake %trror at %f:%l %m",  -- cmake errors with file:line
      "CMake %trror: %m",          -- cmake general errors
      "CMake %tarning at %f:%l %m", -- cmake warnings with file:line
      "CMake %tarning: %m",        -- cmake general warnings
      -- Meson patterns
      "meson.build:%l:%c: %trror: %m", -- meson build file errors
      "meson.build:%l:%c: %tarning: %m", -- meson build file warnings
      "ERROR: %m",                 -- meson general errors
      "WARNING: %m",               -- meson general warnings
      -- Include file traces
      "In file included from %f:%l:",  -- Include traces
      "%*[ ]from %f:%l:",          -- Continuation of include traces
      "In file included from %f:%l,%*\\d:",  -- Include with column
      "%*[ ]from %f:%l,%*\\d:",      -- Continuation with column
    }, ",")
  end,
})

-- ========================================================================
-- DIFF MODE ENHANCEMENTS
-- ========================================================================

-- Enhanced diff mode configuration
vim.api.nvim_create_autocmd({"VimEnter", "WinEnter"}, {
  callback = function()
    if vim.o.diff then
      -- Enable cursorline in all diff windows
      vim.wo.cursorline = true

      -- Set up better diff colors that work with various colorschemes
      vim.api.nvim_set_hl(0, 'DiffAdd', { bg = '#1a3a52', fg = '#9ccc65', bold = true })
      vim.api.nvim_set_hl(0, 'DiffDelete', { bg = '#3a1a1a', fg = '#ff5370', bold = true })
      vim.api.nvim_set_hl(0, 'DiffChange', { bg = '#3a3a1a', fg = '#e2b93d', bold = true })
      vim.api.nvim_set_hl(0, 'DiffText', { bg = '#f7ca88', fg = '#000000', bold = true, underline = true })

      -- Make the cursor line stand out
      vim.api.nvim_set_hl(0, 'CursorLine', { bg = '#3e4452', underline = true, bold = true })
      vim.api.nvim_set_hl(0, 'CursorLineNr', { fg = '#e2b93d', bold = true })

      -- Optional: Set up synchronized scrolling
      vim.wo.scrollbind = true
      vim.wo.cursorbind = true
    end
  end,
})

-- Add commands for better diff navigation
vim.api.nvim_create_user_command('DiffGetLocal', ':diffget LOCAL', {})
vim.api.nvim_create_user_command('DiffGetBase', ':diffget BASE', {})
vim.api.nvim_create_user_command('DiffGetRemote', ':diffget REMOTE', {})

-- DiffInfo command: Show context about LOCAL, BASE, and REMOTE
vim.api.nvim_create_user_command('DiffInfo', function()
  -- Check if we're in diff mode
  if not vim.o.diff then
    vim.notify("Not in diff mode", vim.log.levels.WARN)
    return
  end

  -- Get terminal dimensions (use 95% of width for better display)
  local term_width = vim.o.columns
  local max_width = math.min(math.floor(term_width * 0.95), 120)
  local min_width = 70
  local width = math.max(min_width, max_width)

  -- Inner content width (accounting for box borders ║ on each side)
  local inner_width = width - 2  -- 2 chars for "║ " and " ║"

  -- Helper: Truncate text to fit within width (middle truncation)
  local function truncate_middle(text, max_len)
    if vim.fn.strdisplaywidth(text) <= max_len then
      return text
    end

    local ellipsis = "…"
    local target = max_len - vim.fn.strdisplaywidth(ellipsis)
    if target <= 3 then return ellipsis end

    local start_len = math.floor(target / 2)
    local end_len = target - start_len

    -- Simple character-based truncation (good enough for filenames)
    local start_part = vim.fn.strcharpart(text, 0, start_len)
    local end_part = vim.fn.strcharpart(text, vim.fn.strchars(text) - end_len, end_len)

    return start_part .. ellipsis .. end_part
  end

  -- Helper: Pad line to exact width with spaces
  local function pad_line(content)
    local display_width = vim.fn.strdisplaywidth(content)
    local padding = inner_width - display_width
    if padding > 0 then
      return content .. string.rep(" ", padding)
    end
    return content
  end

  -- Helper: Create box line
  local function box_line(content)
    return "║ " .. pad_line(content) .. " ║"
  end

  -- Helper: Create separator
  local function separator()
    return "╠" .. string.rep("═", width - 2) .. "╣"
  end

  -- Collect all diff buffers in current tab
  local diff_bufs = {}
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local buf = vim.api.nvim_win_get_buf(win)
    if vim.wo[win].diff then
      table.insert(diff_bufs, {
        buf = buf,
        name = vim.api.nvim_buf_get_name(buf),
        win = win
      })
    end
  end

  -- Try to identify which buffer is which based on the file path
  local local_buf, base_buf, remote_buf, merged_buf
  for _, info in ipairs(diff_bufs) do
    local name = info.name
    if name:match("%.LOCAL%.%d+%.") or name:match("/LOCAL$") then
      local_buf = info
    elseif name:match("%.BASE%.%d+%.") or name:match("/BASE$") then
      base_buf = info
    elseif name:match("%.REMOTE%.%d+%.") or name:match("/REMOTE$") then
      remote_buf = info
    elseif name:match("%.BACKUP%.%d+%.") or name:match("%.orig$") then
      -- skip backup files
    else
      -- The file without special suffix is likely the MERGED file
      merged_buf = info
    end
  end

  -- Build the info message
  local lines = {
    "╔" .. string.rep("═", width - 2) .. "╗",
    box_line("GIT MERGE DIFF CONTEXT"),
    separator(),
    box_line(""),
  }

  -- Add responsive diagram
  local diagram_width = inner_width
  if diagram_width >= 60 then
    table.insert(lines, box_line("YOUR BRANCH (LOCAL) ←─── BASE ───→ THEIR BRANCH (REMOTE)"))
    table.insert(lines, box_line("       │                              │"))
    table.insert(lines, box_line("       └──────────→ MERGED ←──────────┘"))
  elseif diagram_width >= 50 then
    table.insert(lines, box_line("LOCAL ←─── BASE ───→ REMOTE"))
    table.insert(lines, box_line("  │                     │"))
    table.insert(lines, box_line("  └─────→ MERGED ←─────┘"))
  else
    table.insert(lines, box_line("LOCAL ← BASE → REMOTE"))
    table.insert(lines, box_line("   └─→ MERGED ←─┘"))
  end

  table.insert(lines, box_line(""))
  table.insert(lines, separator())

  -- File information with smart truncation
  local file_label_width = 8  -- "LOCAL:  " or "REMOTE: "
  local file_max_width = inner_width - file_label_width

  if local_buf then
    local fname = truncate_middle(vim.fn.fnamemodify(local_buf.name, ':t'), file_max_width)
    table.insert(lines, box_line("LOCAL:  " .. fname))
  end
  if base_buf then
    local fname = truncate_middle(vim.fn.fnamemodify(base_buf.name, ':t'), file_max_width)
    table.insert(lines, box_line("BASE:   " .. fname))
  end
  if remote_buf then
    local fname = truncate_middle(vim.fn.fnamemodify(remote_buf.name, ':t'), file_max_width)
    table.insert(lines, box_line("REMOTE: " .. fname))
  end
  if merged_buf then
    local fname = truncate_middle(vim.fn.fnamemodify(merged_buf.name, ':t'), file_max_width)
    table.insert(lines, box_line("MERGED: " .. fname))
  end

  table.insert(lines, box_line(""))
  table.insert(lines, separator())
  table.insert(lines, box_line("KEYBINDINGS:"))
  table.insert(lines, box_line("  <leader>dgl  - Accept LOCAL (your changes)"))
  table.insert(lines, box_line("  <leader>dgb  - Accept BASE (common ancestor)"))
  table.insert(lines, box_line("  <leader>dgr  - Accept REMOTE (their changes)"))
  table.insert(lines, box_line("  <leader>du   - Update diff highlighting"))
  table.insert(lines, box_line("  ]c / [c      - Next/previous diff change"))
  table.insert(lines, box_line("  ]x / [x      - Next/previous conflict marker"))
  table.insert(lines, "╚" .. string.rep("═", width - 2) .. "╝")

  -- Create floating window
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

  -- Calculate window position (centered)
  local height = #lines
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

  local opts = {
    relative = 'editor',
    width = width,
    height = height,
    row = row,
    col = col,
    style = 'minimal',
    border = 'none',
  }

  local win = vim.api.nvim_open_win(buf, true, opts)

  -- Set buffer options
  vim.api.nvim_buf_set_option(buf, 'modifiable', false)
  vim.api.nvim_buf_set_option(buf, 'bufhidden', 'wipe')

  -- Close on any key press
  vim.api.nvim_buf_set_keymap(buf, 'n', 'q', '<cmd>close<CR>', { silent = true, noremap = true })
  vim.api.nvim_buf_set_keymap(buf, 'n', '<Esc>', '<cmd>close<CR>', { silent = true, noremap = true })
  vim.api.nvim_buf_set_keymap(buf, 'n', '<CR>', '<cmd>close<CR>', { silent = true, noremap = true })

  -- Highlight the window
  vim.api.nvim_win_set_option(win, 'winhl', 'Normal:Normal,FloatBorder:Normal')
end, { desc = 'Show diff context information' })

-- Improved diff navigation with ]c and [c
vim.keymap.set('n', ']c', function()
  if vim.o.diff then
    vim.cmd('normal! ]c')
    -- Flash the cursor line briefly to show where we are
    vim.cmd('redraw')
  else
    vim.cmd('normal! ]c')
  end
end, { desc = 'Next diff/change' })

vim.keymap.set('n', '[c', function()
  if vim.o.diff then
    vim.cmd('normal! [c')
    -- Flash the cursor line briefly to show where we are
    vim.cmd('redraw')
  else
    vim.cmd('normal! [c')
  end
end, { desc = 'Previous diff/change' })

-- ========================================================================
-- UI ENHANCEMENTS
-- ========================================================================

-- Clean up Telescope appearance - reduce distracting background colors
vim.api.nvim_create_autocmd("ColorScheme", {
  callback = function()
    -- Make telescope prompt look like a clean input box
    vim.api.nvim_set_hl(0, 'TelescopePromptNormal', { bg = 'NONE', fg = 'NONE' })
    vim.api.nvim_set_hl(0, 'TelescopePromptBorder', { fg = '#565f89', bg = 'NONE' })
    vim.api.nvim_set_hl(0, 'TelescopePromptTitle', { fg = '#7aa2f7', bg = 'NONE', bold = true })

    -- Clean results window
    vim.api.nvim_set_hl(0, 'TelescopeResultsNormal', { bg = 'NONE' })
    vim.api.nvim_set_hl(0, 'TelescopeResultsBorder', { fg = '#565f89', bg = 'NONE' })
    vim.api.nvim_set_hl(0, 'TelescopeResultsTitle', { fg = '#7aa2f7', bg = 'NONE', bold = true })

    -- Clean preview window
    vim.api.nvim_set_hl(0, 'TelescopePreviewNormal', { bg = 'NONE' })
    vim.api.nvim_set_hl(0, 'TelescopePreviewBorder', { fg = '#565f89', bg = 'NONE' })
    vim.api.nvim_set_hl(0, 'TelescopePreviewTitle', { fg = '#7aa2f7', bg = 'NONE', bold = true })

    -- Selection highlighting
    vim.api.nvim_set_hl(0, 'TelescopeSelection', { bg = '#2d3149', fg = 'NONE', bold = true })
    vim.api.nvim_set_hl(0, 'TelescopeSelectionCaret', { fg = '#7aa2f7', bg = '#2d3149', bold = true })

    -- Match highlighting in results
    vim.api.nvim_set_hl(0, 'TelescopeMatching', { fg = '#ff9e64', bg = 'NONE', bold = true })
  end,
})

-- Apply telescope highlights immediately
vim.schedule(function()
  -- Make telescope prompt look like a clean input box
  vim.api.nvim_set_hl(0, 'TelescopePromptNormal', { bg = 'NONE', fg = 'NONE' })
  vim.api.nvim_set_hl(0, 'TelescopePromptBorder', { fg = '#565f89', bg = 'NONE' })
  vim.api.nvim_set_hl(0, 'TelescopePromptTitle', { fg = '#7aa2f7', bg = 'NONE', bold = true })
  vim.api.nvim_set_hl(0, 'TelescopePromptCounter', { fg = '#9ece6a', bg = 'NONE' })

  -- Clean results window
  vim.api.nvim_set_hl(0, 'TelescopeResultsNormal', { bg = 'NONE' })
  vim.api.nvim_set_hl(0, 'TelescopeResultsBorder', { fg = '#565f89', bg = 'NONE' })
  vim.api.nvim_set_hl(0, 'TelescopeResultsTitle', { fg = '#7aa2f7', bg = 'NONE', bold = true })

  -- Clean preview window
  vim.api.nvim_set_hl(0, 'TelescopePreviewNormal', { bg = 'NONE' })
  vim.api.nvim_set_hl(0, 'TelescopePreviewBorder', { fg = '#565f89', bg = 'NONE' })
  vim.api.nvim_set_hl(0, 'TelescopePreviewTitle', { fg = '#7aa2f7', bg = 'NONE', bold = true })

  -- Selection highlighting
  vim.api.nvim_set_hl(0, 'TelescopeSelection', { bg = '#2d3149', fg = 'NONE', bold = true })
  vim.api.nvim_set_hl(0, 'TelescopeSelectionCaret', { fg = '#7aa2f7', bg = '#2d3149', bold = true })

  -- Match highlighting in results
  vim.api.nvim_set_hl(0, 'TelescopeMatching', { fg = '#ff9e64', bg = 'NONE', bold = true })
end)

-- ========================================================================
-- OVERSEER INTEGRATION
-- ========================================================================

local overseer = require('overseer')

-- FIX FOR ERROR MESSAGE TRUNCATION IN QUICKFIX:
-- The root cause is that overseer's jobstart strategy constrains PTY width to vim.o.columns - 4
-- This causes compiler output to be truncated when Neovim window is narrow (~100 columns).
-- TEMPORARY: Monkey-patch for when use_terminal=true (affects templates that override strategy)
-- Issue #445: https://github.com/stevearc/overseer.nvim/issues/445
-- PR pending: https://github.com/timblaktu/overseer.nvim/tree/fix-pty-width-truncation
local JobstartStrategy = require('overseer.strategy.jobstart')
local original_start = JobstartStrategy.start
JobstartStrategy.start = function(self, task)
  -- Temporarily override vim.o.columns during jobstart
  local saved_columns = vim.o.columns
  vim.o.columns = 504  -- Will become 500 after "- 4" in the original code
  local result = original_start(self, task)
  vim.o.columns = saved_columns
  return result
end

-- Note: We're currently using use_terminal=false in overseer settings which avoids this issue
-- But some templates might override the strategy, so the monkey-patch helps those cases
-- Once PR is merged, can add pty_width=500 to strategy config and remove monkey-patch

-- Auto-run make on C/C++ file save
vim.api.nvim_create_autocmd("BufWritePost", {
  pattern = {"*.c", "*.cpp", "*.cc", "*.h", "*.hpp"},
  callback = function()
    local file_dir = vim.fn.expand('%:p:h')

    -- Check if Makefile exists in the current file's directory
    if vim.fn.filereadable(file_dir .. '/Makefile') == 1 or
       vim.fn.filereadable(file_dir .. '/makefile') == 1 then
      -- Run make using overseer (callback-based API, no return value)
      overseer.run_template({ name = "make" }, function(task, err)
        if task then
          -- Task started successfully, statusline will show progress
          vim.notify("Make task started", vim.log.levels.INFO)
        else
          vim.notify("Failed to start make task: " .. (err or "unknown error"), vim.log.levels.ERROR)
        end
      end)
    end
  end,
})

-- Auto-run cargo check on Rust file save
vim.api.nvim_create_autocmd("BufWritePost", {
  pattern = {"*.rs"},
  callback = function()
    -- Find Cargo.toml by walking up the directory tree
    local function find_cargo_toml(path)
      if path == "/" then return nil end
      if vim.fn.filereadable(path .. '/Cargo.toml') == 1 then
        return path
      end
      return find_cargo_toml(vim.fn.fnamemodify(path, ':h'))
    end

    local cargo_root = find_cargo_toml(vim.fn.expand('%:p:h'))
    if cargo_root then
      -- Run cargo check using overseer
      overseer.run_template({ name = "cargo", params = { task = "check" } }, function(task, err)
        if task then
          vim.notify("Cargo check started", vim.log.levels.INFO)
        else
          vim.notify("Failed to start cargo check: " .. (err or "unknown error"), vim.log.levels.ERROR)
        end
      end)
    end
  end,
})

-- ========================================================================
-- CUSTOM COMMANDS
-- ========================================================================

-- Simple make command using overseer
vim.api.nvim_create_user_command('Make', function(opts)
  local args = opts.args ~= "" and vim.split(opts.args, " ") or {}
  overseer.run_template({ name = "make", params = { args = args } })
end, { nargs = '*', desc = 'Run make with optional arguments' })

-- Simple cargo command using overseer
vim.api.nvim_create_user_command('Cargo', function(opts)
  local args = opts.args ~= "" and vim.split(opts.args, " ") or { "check" }
  local task = args[1] or "check"
  overseer.run_template({ name = "cargo", params = { task = task, args = vim.list_slice(args, 2) } })
end, { nargs = '*', desc = 'Run cargo with arguments (default: check)' })

-- ========================================================================
-- QUICKFIX ENHANCEMENTS
-- ========================================================================

-- Quickfix statusline with error/warning counts
vim.api.nvim_create_autocmd("FileType", {
  pattern = "qf",
  callback = function()
    local win = vim.api.nvim_get_current_win()
    local buf = vim.api.nvim_get_current_buf()

    -- Enable cursorline for better visibility
    vim.wo[win].cursorline = true

    -- Create a function to generate the statusline
    vim.b[buf].qf_statusline = function()
      local qflist = vim.fn.getqflist()
      local total = #qflist
      local current = vim.fn.line('.')

      -- Count errors, warnings, notes
      local errors, warnings, notes = 0, 0, 0
      for _, item in ipairs(qflist) do
        local t = (item.type or ""):lower()
        if t == 'e' then
          errors = errors + 1
        elseif t == 'w' then
          warnings = warnings + 1
        elseif t == 'n' or t == 'i' then
          notes = notes + 1
        end
      end

      -- Build status parts
      local parts = {}
      if errors > 0 then table.insert(parts, errors .. 'E') end
      if warnings > 0 then table.insert(parts, warnings .. 'W') end
      if notes > 0 then table.insert(parts, notes .. 'N') end

      local summary = #parts > 0 and table.concat(parts, ' ') or 'Empty'
      return string.format('[Quickfix] %s │ %d/%d', summary, current, total)
    end

    -- Set the statusline using the function
    vim.wo[win].statusline = '%!v:lua.vim.b[' .. buf .. '].qf_statusline()'
  end,
})

-- ========================================================================
-- OPTIONAL: NVIM-NOTIFY SETUP (COMMENTED OUT)
-- ========================================================================

-- Uncomment this section if you want rich notifications with nvim-notify plugin
-- Note: You'll need to add nvim-notify to your plugins first
--[[
local notify = require("notify")
notify.setup({
  stages = "slide",       -- Animation style: fade_in_slide_out, fade, slide, static
  timeout = 3000,         -- Default timeout for notifications
  render = "minimal",     -- Render style: default, minimal, compact
  max_width = 50,
  max_height = 10,
  on_open = function(win)
    vim.api.nvim_win_set_config(win, { focusable = false })
  end,
})
vim.notify = notify

-- Custom highlights for notification levels
vim.api.nvim_set_hl(0, 'NotifyINFOTitle', { fg = '#9ece6a' })
vim.api.nvim_set_hl(0, 'NotifyERRORTitle', { fg = '#f7768e' })
vim.api.nvim_set_hl(0, 'NotifyWARNTitle', { fg = '#e0af68' })
--]]
