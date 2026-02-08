# Comprehensive Nixvim configuration - Refactored with proper autoCmd usage
{ config, lib, pkgs, inputs, ... }:

{
  imports = [ inputs.nixvim.homeModules.nixvim ];

  programs.nixvim = {
    enable = true;
    defaultEditor = true;
    viAlias = true;
    vimAlias = true;

    # Fix VIMRUNTIME environment variable for LSP functionality
    env = {
      VIMRUNTIME = "${pkgs.neovim-unwrapped}/share/nvim/runtime";
    };

    # Core vim settings
    opts = {
      # Basic editor settings
      number = true;
      relativenumber = true;
      expandtab = true;
      shiftwidth = 2;
      shiftround = true;
      autoindent = true;
      smartindent = true;
      tabstop = 2;
      softtabstop = 2;
      modelines = 2;
      modeline = true;
      mouse = "a";

      # Search settings
      incsearch = true;
      hlsearch = true;
      ignorecase = true;
      smartcase = true;

      # UI settings
      showmatch = true;
      showcmd = true;
      signcolumn = "yes";
      ttyfast = true;
      scrolloff = 2;
      termguicolors = true;
      updatetime = 100;

      # Backup and undo
      backup = true;
      backupdir = "${config.xdg.stateHome}/nvim/backup,~/tmp/vim-backupdir,~/tmp";
      writebackup = true;
      backupcopy = "yes";
      undofile = true;
      undodir = "${config.xdg.stateHome}/nvim/undo";

      # Other settings
      hidden = true;
      backspace = "start,indent,eol";
      shortmess = "aFI"; # I = skip intro message
      completeopt = "menuone,noselect";
      timeout = true;
      timeoutlen = 150; # Reduced from 300ms for faster leader key response
      ttimeoutlen = 10; # Reduced from 250ms for faster escape key response
      clipboard = "unnamedplus";
      foldcolumn = "0";

      # Wildmenu settings
      wildmenu = true;
      wildmode = "longest:list";
      autoread = true;

      # Format options
      formatoptions = "croq";

      # Regex engine settings
      re = 0;
      regexpengine = 0;
    };

    globals = {
      mapleader = " ";
      maplocalleader = " ";
    };

    # Set default colorscheme explicitly to avoid conflicts
    colorscheme = lib.mkForce "gruvbox";

    colorschemes = {
      base16 = {
        enable = false; # Disabled to prevent conflicts with gruvbox
        colorscheme = "solarized-dark";
      };
      solarized-osaka = {
        enable = false; # Disabled - enable only when using this theme
        settings = {
          transparent = false;
          styles = {
            comments = { italic = true; };
            keywords = { italic = false; };
            functions = { bold = true; };
            variables = { };
          };
        };
      };
      tokyonight = {
        enable = false; # Disabled - enable only when using this theme
        settings = {
          style = "storm";
          transparent = false;
          terminal_colors = true;
        };
      };
      catppuccin = {
        enable = false; # Disabled - enable only when using this theme
        settings = {
          flavour = "mocha";
          transparent_background = false;
        };
      };
      gruvbox = {
        enable = true; # This is the active colorscheme
        settings = {
          contrast = "medium";
          transparent_mode = false;
        };
      };
    };

    # Core keymaps
    keymaps = [
      # Core navigation and editing
      { mode = "n"; key = "<Enter>"; action = ":nohlsearch<CR>"; options.silent = true; }
      { mode = "n"; key = "<F2>"; action = ":set number! relativenumber!<CR>"; options.silent = true; }
      { mode = "n"; key = "<F5>"; action = ":!%<CR>"; }
      { mode = "n"; key = "<F11>"; action = ":set paste!<CR>"; options.silent = true; }

      # Buffer navigation
      { mode = "n"; key = "<Tab>"; action = ":bnext<CR>"; options.silent = true; }
      { mode = "n"; key = "<S-Tab>"; action = ":bprevious<CR>"; options.silent = true; }
      { mode = "n"; key = "<leader>x"; action = ":bp<bar>sp<bar>bn<bar>bd<CR>"; options.silent = true; }

      # Quickfix navigation
      { mode = "n"; key = "]q"; action = ":cnext<CR>"; options.silent = true; }
      { mode = "n"; key = "[q"; action = ":cprevious<CR>"; options.silent = true; }
      { mode = "n"; key = "]Q"; action = ":clast<CR>"; options.silent = true; }
      { mode = "n"; key = "[Q"; action = ":cfirst<CR>"; options.silent = true; }
      { mode = "n"; key = "<leader>q"; action = ":copen<CR>"; options = { silent = true; desc = "Toggle quickfix window"; }; }

      # Help navigation
      { mode = "n"; key = "<Leader>K"; action = ":h expand(\"<cword>\")<cr>"; }

      # Scrollbind
      { mode = "n"; key = "<leader>r"; action = ":windo set scrollbind<CR>"; }
      { mode = "n"; key = "<leader>R"; action = ":windo set scrollbind!<CR>"; }

      # Visual search
      { mode = "v"; key = "//"; action = "y/<C-R>\"<CR>N"; }

      # Modern keymaps
      { mode = "n"; key = "<leader>e"; action = "<cmd>NvimTreeToggle<CR>"; options.silent = true; }
      { mode = "n"; key = "<leader>ff"; action = "<cmd>Telescope find_files<CR>"; options.silent = true; }
      { mode = "n"; key = "<leader>fg"; action = "<cmd>Telescope live_grep<CR>"; options.silent = true; }
      { mode = "n"; key = "<leader>fw"; action = "<cmd>Telescope grep_string<CR>"; options.silent = true; }
      { mode = "n"; key = "<leader>fb"; action = "<cmd>Telescope buffers<CR>"; options.silent = true; }
      { mode = "n"; key = "<leader>fh"; action = "<cmd>Telescope help_tags<CR>"; options.silent = true; }

      # Very magic regex by default
      { mode = "n"; key = "/"; action = "/\\v"; }
      { mode = "v"; key = "/"; action = "/\\v"; }

      # Diff/merge keybindings
      { mode = "n"; key = "<leader>dgl"; action = ":diffget LOCAL<CR>"; options.silent = true; }
      { mode = "n"; key = "<leader>dgb"; action = ":diffget BASE<CR>"; options.silent = true; }
      { mode = "n"; key = "<leader>dgr"; action = ":diffget REMOTE<CR>"; options.silent = true; }
      { mode = "n"; key = "<leader>du"; action = ":diffupdate<CR>"; options.silent = true; }
      { mode = "n"; key = "<leader>di"; action = "<cmd>DiffInfo<CR>"; options = { silent = true; desc = "Show diff context info"; }; }

      # Git conflict marker navigation
      { mode = "n"; key = "]x"; action = "/^\\(<\\{7\\}\\|=\\{7\\}\\|>\\{7\\}\\)<CR>"; options = { silent = true; desc = "Next conflict marker"; }; }
      { mode = "n"; key = "[x"; action = "?^\\(<\\{7\\}\\|=\\{7\\}\\|>\\{7\\}\\)<CR>"; options = { silent = true; desc = "Previous conflict marker"; }; }

      # Colorscheme group with which-key descriptions
      { mode = "n"; key = "<leader>cd"; action = ":colorscheme base16-solarized-dark<CR>"; options = { silent = true; desc = "Solarized Dark (Base16)"; }; }
      { mode = "n"; key = "<leader>cl"; action = ":colorscheme base16-solarized-light<CR>"; options = { silent = true; desc = "Solarized Light (Base16)"; }; }
      { mode = "n"; key = "<leader>co"; action = ":colorscheme solarized-osaka<CR>"; options = { silent = true; desc = "Solarized Osaka"; }; }
      { mode = "n"; key = "<leader>ct"; action = ":colorscheme tokyonight<CR>"; options = { silent = true; desc = "Tokyo Night"; }; }
      { mode = "n"; key = "<leader>cc"; action = ":colorscheme catppuccin<CR>"; options = { silent = true; desc = "Catppuccin"; }; }
      { mode = "n"; key = "<leader>cg"; action = ":colorscheme gruvbox<CR>"; options = { silent = true; desc = "Gruvbox"; }; }

      # Commenting with leader key
      { mode = "n"; key = "<leader>/"; action = "gcc"; options = { silent = true; desc = "Toggle line comment"; remap = true; }; }
      { mode = "v"; key = "<leader>/"; action = "gc"; options = { silent = true; desc = "Toggle comment"; remap = true; }; }
      { mode = "n"; key = "<leader>?"; action = "gbc"; options = { silent = true; desc = "Toggle block comment"; remap = true; }; }
      { mode = "v"; key = "<leader>?"; action = "gb"; options = { silent = true; desc = "Toggle block comment"; remap = true; }; }

      # Quitting
      { mode = "n"; key = "<leader><leader>q"; action = ":qa<CR>"; options.silent = true; }
      { mode = "n"; key = "<leader><leader>x"; action = ":xa<CR>"; options.silent = true; }
      { mode = "n"; key = "<leader><leader>c"; action = ":cq<CR>"; options.silent = true; }

      # Overseer task runner keymaps
      { mode = "n"; key = "<leader>tr"; action = "<cmd>OverseerRun<CR>"; options = { silent = true; desc = "Run task"; }; }
      { mode = "n"; key = "<leader>tt"; action = "<cmd>OverseerToggle<CR>"; options = { silent = true; desc = "Toggle task list"; }; }
      { mode = "n"; key = "<leader>ta"; action = "<cmd>OverseerTaskAction<CR>"; options = { silent = true; desc = "Task action"; }; }
      { mode = "n"; key = "<leader>tb"; action = "<cmd>OverseerBuild<CR>"; options = { silent = true; desc = "Build task"; }; }
      { mode = "n"; key = "<leader>tq"; action = "<cmd>OverseerQuickAction<CR>"; options = { silent = true; desc = "Quick action"; }; }
      { mode = "n"; key = "<leader>tc"; action = "<cmd>OverseerClearCache<CR>"; options = { silent = true; desc = "Clear cache"; }; }
    ];

    # Autocommand groups - organized by functionality
    autoGroups = {
      # File type specific settings
      filetype_settings = {
        clear = true;
      };
      # Diff mode enhancements
      diff_mode = {
        clear = true;
      };
      # Quickfix window customization
      quickfix_enhancements = {
        clear = true;
      };
      # Session management
      session_management = {
        clear = true;
      };
    };

    # Autocmds - using nixvim's native autoCmd option for simple cases
    autoCmd = [
      # ========================================================================
      # FILE TYPE SPECIFIC SETTINGS
      # ========================================================================

      # PowerShell BOM configuration
      {
        event = "BufWritePre";
        pattern = "*.ps1";
        group = "filetype_settings";
        callback = {
          __raw = ''
            function()
              vim.bo.bomb = true
            end
          '';
        };
        desc = "Set BOM flag for PowerShell files before writing";
      }

      # Help window configuration
      {
        event = "FileType";
        pattern = "help";
        group = "filetype_settings";
        callback = {
          __raw = ''
            function()
              vim.opt_local.helpheight = 9999
              vim.opt_local.relativenumber = true
              vim.keymap.set('n', 'q', ':q<cr>', { buffer = true, noremap = true })
            end
          '';
        };
        desc = "Help window settings";
      }

      # YAML-specific settings
      {
        event = "FileType";
        pattern = "yaml";
        group = "filetype_settings";
        callback = {
          __raw = ''
            function()
              vim.opt_local.tabstop = 2
              vim.opt_local.softtabstop = 2
              vim.opt_local.shiftwidth = 2
              vim.opt_local.expandtab = true
            end
          '';
        };
        desc = "YAML indentation settings";
      }

      # ========================================================================
      # QUICKFIX WINDOW CUSTOMIZATION
      # ========================================================================

      {
        event = "FileType";
        pattern = "qf";
        group = "quickfix_enhancements";
        callback = {
          __raw = ''
            function()
              vim.opt_local.number = false
              vim.opt_local.relativenumber = false
              
              -- Useful mappings for quickfix navigation
              local opts = { buffer = true, noremap = true, silent = true }
              vim.keymap.set('n', '<CR>', '<CR>', opts)
              vim.keymap.set('n', 'o', '<CR>', opts)
              vim.keymap.set('n', 's', '<C-W><CR>', opts)
              vim.keymap.set('n', 'v', '<C-W><CR><C-W>L', opts)
              vim.keymap.set('n', 't', '<C-W><CR><C-W>T', opts)
              
              -- Quicker.nvim context expansion/collapse
              vim.keymap.set('n', '>', ':lua require("quicker").expand({ before = 2, after = 2, add_to_existing = true })<CR>', opts)
              vim.keymap.set('n', '<', ':lua require("quicker").collapse()<CR>', opts)
            end
          '';
        };
        desc = "Quickfix window settings and keymaps";
      }

      # ========================================================================
      # SESSION MANAGEMENT
      # ========================================================================

      {
        event = "VimLeavePre";
        pattern = "*";
        group = "session_management";
        callback = {
          __raw = ''
            function()
              if vim.v.this_session ~= "" then
                vim.cmd("mksession! " .. vim.v.this_session)
              end
            end
          '';
        };
        desc = "Auto-save session on exit";
      }

      # ========================================================================
      # DIFF MODE ENHANCEMENTS
      # ========================================================================

      {
        event = [ "VimEnter" "WinEnter" ];
        pattern = "*";
        group = "diff_mode";
        callback = {
          __raw = ''
            function()
              if vim.o.diff then
                vim.wo.cursorline = true
              end
            end
          '';
        };
        desc = "Enable cursorline in diff mode";
      }

      {
        event = "OptionSet";
        pattern = "diff";
        group = "diff_mode";
        callback = {
          __raw = ''
            function()
              if vim.v.option_new then
                vim.wo.cursorline = true
              else
                vim.wo.cursorline = false
              end
            end
          '';
        };
        desc = "Toggle cursorline when diff mode changes";
      }
    ];

    # Basic plugins
    plugins = {
      web-devicons = {
        enable = true; # Keep enabled for other plugins that might use it
        settings = {
          # Use text fallbacks if icons aren't available
          default = true;
        };
      };
      which-key = {
        enable = true;
        settings = {
          spec = {
            __raw = ''
              {
                { "<leader>c", group = "Colorschemes" },
                { "<leader>f", group = "Find/Telescope" },
                { "<leader>d", group = "Diff/Git" },
                { "<leader>dg", group = "Diff Get" },
                { "<leader>dgl", desc = "Get from LOCAL (your changes)" },
                { "<leader>dgb", desc = "Get from BASE (common ancestor)" },
                { "<leader>dgr", desc = "Get from REMOTE (their changes)" },
                { "<leader>du", desc = "Update diff highlighting" },
                { "<leader>di", desc = "Show diff context info" },
                { "<leader>t", group = "Tasks/Overseer" },
                { "<leader>/", desc = "Toggle line comment" },
                { "<leader>?", desc = "Toggle block comment" },
                { "gc", desc = "Comment (motion)" },
                { "gb", desc = "Block comment (motion)" },
                { "gcc", desc = "Toggle line comment" },
                { "gbc", desc = "Toggle block comment" },
                { "]x", desc = "Next conflict marker" },
                { "[x", desc = "Previous conflict marker" },
                { "]c", desc = "Next diff change" },
                { "[c", desc = "Previous diff change" },
              }
            '';
          };
        };
      };
      comment = {
        enable = true;
        settings = {
          # Add padding space after comment delimiter
          padding = true;
          # Keep cursor position when commenting
          sticky = true;
          # Ignore empty lines when commenting
          ignore = "^$";
          # Configure toggler keymaps
          toggler = {
            line = "gcc";
            block = "gbc";
          };
          # Configure operator-pending keymaps
          opleader = {
            line = "gc";
            block = "gb";
          };
          # Extra keymaps
          extra = {
            above = "gcO";
            below = "gco";
            eol = "gcA";
          };
        };
      };
      tmux-navigator.enable = true;
      vim-surround.enable = true;

      # UI Enhancements
      lualine = {
        enable = true;
        settings = {
          options = {
            theme = "auto";
            component_separators = { left = "|"; right = "|"; };
            section_separators = { left = ""; right = ""; };
            globalstatus = false; # Per-window statuslines
          };
          sections = {
            # Left sections
            lualine_a = [ "mode" ];
            lualine_b = [
              {
                __raw = ''
                  {
                    'branch',
                    fmt = function(str)
                      -- Dynamic branch name truncation based on window width
                      local width = vim.fn.winwidth(0)
                      if width < 80 then
                        -- Very narrow: show only first letter of each path segment
                        if str:match('/') then
                          local parts = {}
                          for part in str:gmatch('[^/]+') do
                            if #parts < #vim.split(str, '/') - 1 then
                              table.insert(parts, part:sub(1, 1))
                            else
                              -- Keep last part fuller
                              table.insert(parts, part:sub(1, 10))
                            end
                          end
                          return table.concat(parts, '/')
                        else
                          return str:sub(1, 15)
                        end
                      elseif width < 120 then
                        -- Medium width: moderate truncation
                        return str:sub(1, 25)
                      else
                        -- Wide enough: show full branch
                        return str
                      end
                    end,
                    -- Hide completely on very narrow windows
                    cond = function()
                      return vim.fn.winwidth(0) > 60
                    end,
                  }
                '';
              }
              {
                __raw = ''
                  {
                    'diff',
                    -- Hide diff on narrow windows
                    cond = function()
                      return vim.fn.winwidth(0) > 90
                    end,
                  }
                '';
              }
              {
                __raw = ''
                  {
                    'diagnostics',
                    -- Only show if there are actual diagnostics
                    cond = function()
                      local width = vim.fn.winwidth(0)
                      if width < 70 then
                        return false
                      end
                      -- Also check if there are any diagnostics to show
                      local diagnostics = vim.diagnostic.get(0)
                      return #diagnostics > 0
                    end,
                    symbols = { error = 'E', warn = 'W', info = 'I', hint = 'H' },
                  }
                '';
              }
            ];
            lualine_c = [
              {
                __raw = ''
                  {
                    'filename',
                    path = 1,  -- 1 = relative path
                    fmt = function(str)
                      local width = vim.fn.winwidth(0)
                      -- Priority: always show filename
                      if width < 60 then
                        -- Very narrow: just filename
                        return vim.fn.fnamemodify(str, ':t')
                      elseif width < 100 then
                        -- Narrow: truncate path but keep filename visible
                        local fname = vim.fn.fnamemodify(str, ':t')
                        local path = vim.fn.fnamemodify(str, ':h')
                        if path ~= '.' then
                          -- Show abbreviated path
                          local parts = {}
                          for part in path:gmatch('[^/]+') do
                            table.insert(parts, part:sub(1, 1))
                          end
                          return table.concat(parts, '/') .. '/' .. fname
                        else
                          return fname
                        end
                      else
                        -- Wide enough: show relative path
                        return str
                      end
                    end,
                    symbols = {
                      modified = '[+]',
                      readonly = '[-]',
                      unnamed = '[No Name]',
                    },
                  }
                '';
              }
            ];
            # Right sections
            lualine_x = [
              {
                __raw = ''
                  {
                    -- Simple overseer status display
                    function()
                      local ok, overseer = pcall(require, "overseer")
                      if not ok then return "" end
                      
                      local tasks = overseer.list_tasks({ recent_first = true })
                      if #tasks == 0 then return "" end
                      
                      local task = tasks[1]
                      if not task then return "" end
                      
                      local STATUS = overseer.STATUS
                      local status_symbols = {
                        [STATUS.FAILURE] = "✘",
                        [STATUS.CANCELED] = "⊘",
                        [STATUS.SUCCESS] = "✓", 
                        [STATUS.RUNNING] = "⟳",
                        [STATUS.PENDING] = "⋯",
                      }
                      
                      local symbol = status_symbols[task.status] or "?"
                      return symbol .. " " .. task.name
                    end,
                    color = function()
                      local ok, overseer = pcall(require, "overseer")
                      if not ok then return {} end
                      
                      local tasks = overseer.list_tasks({ recent_first = true })
                      if #tasks == 0 then return {} end
                      
                      local task = tasks[1]
                      if not task then return {} end
                      
                      local STATUS = overseer.STATUS
                      local status_colors = {
                        [STATUS.FAILURE] = { fg = '#f7768e', gui = 'bold' },
                        [STATUS.CANCELED] = { fg = '#e0af68', gui = 'bold' },
                        [STATUS.SUCCESS] = { fg = '#9ece6a', gui = 'bold' },
                        [STATUS.RUNNING] = { fg = '#7aa2f7', gui = 'bold' },
                        [STATUS.PENDING] = { fg = '#bb9af7', gui = 'bold' },
                      }
                      
                      return status_colors[task.status] or {}
                    end,
                    on_click = function()
                      vim.cmd('OverseerToggle')
                    end,
                  }
                '';
              }
              {
                __raw = ''
                  {
                    -- Simple quickfix counter
                    function()
                      local qflist = vim.fn.getqflist()
                      if #qflist == 0 then return "" end
                      
                      local errors, warnings = 0, 0
                      for _, item in ipairs(qflist) do
                        local t = (item.type or ""):lower()
                        if t == 'e' then
                          errors = errors + 1
                        elseif t == 'w' then
                          warnings = warnings + 1
                        end
                      end
                      
                      local parts = {}
                      if errors > 0 then table.insert(parts, errors .. 'E') end
                      if warnings > 0 then table.insert(parts, warnings .. 'W') end
                      
                      return #parts > 0 and ('🗲 ' .. table.concat(parts, ' ')) or '🗲 ' .. #qflist
                    end,
                    color = { fg = '#f7768e', gui = 'bold' },
                    on_click = function()
                      vim.cmd('copen')
                    end,
                  }
                '';
              }
              {
                __raw = ''
                  {
                    'encoding',
                    -- Only show on wide terminals
                    cond = function()
                      return vim.fn.winwidth(0) > 120
                    end,
                  }
                '';
              }
              {
                __raw = ''
                  {
                    'fileformat',
                    -- Only show on wide terminals
                    cond = function()
                      return vim.fn.winwidth(0) > 110
                    end,
                  }
                '';
              }
              "filetype"
            ];
            lualine_y = [
              {
                __raw = ''
                  {
                    'progress',
                    -- Hide on very narrow windows
                    cond = function()
                      return vim.fn.winwidth(0) > 50
                    end,
                  }
                '';
              }
            ];
            lualine_z = [
              {
                __raw = ''
                  {
                    'location',
                    -- Always show but abbreviated on narrow windows
                    fmt = function(str)
                      local width = vim.fn.winwidth(0)
                      if width < 60 then
                        -- Just line number
                        local line = vim.fn.line('.')
                        return tostring(line)
                      else
                        return str
                      end
                    end,
                  }
                '';
              }
            ];
          };
          inactive_sections = {
            lualine_a = [ ];
            lualine_b = [ ];
            lualine_c = [
              {
                __raw = ''
                  {
                    'filename',
                    path = 1,  -- Show relative path
                    fmt = function(str)
                      local width = vim.fn.winwidth(0)
                      -- Same smart truncation for inactive windows
                      if width < 60 then
                        return vim.fn.fnamemodify(str, ':t')
                      elseif width < 100 then
                        local fname = vim.fn.fnamemodify(str, ':t')
                        local path = vim.fn.fnamemodify(str, ':h')
                        if path ~= '.' then
                          local parts = {}
                          for part in path:gmatch('[^/]+') do
                            table.insert(parts, part:sub(1, 1))
                          end
                          return table.concat(parts, '/') .. '/' .. fname
                        else
                          return fname
                        end
                      else
                        return str
                      end
                    end,
                    symbols = {
                      modified = '[+]',
                      readonly = '[-]',
                    },
                  }
                '';
              }
            ];
            lualine_x = [ "filetype" ];
            lualine_y = [ "progress" ];
            lualine_z = [ "location" ];
          };
        };
      };

      bufferline = {
        enable = false; # Disable tabs at the top
      };

      nvim-tree = {
        enable = true;
        settings = {
          disable_netrw = true;
          hijack_netrw = true;
          # Fix FileExplorer autocommand conflict
          hijack_unnamed_buffer_when_opening = false;
          view = {
            width = 50;
            side = "left";
          };
          renderer = {
            highlight_git = true;
            icons = {
              show = {
                git = true;
                folder = true;
                file = true;
                folder_arrow = true;
              };
            };
          };
        };
      };

      # Telescope
      telescope = {
        enable = true;
        extensions = {
          fzf-native = {
            enable = true;
            settings = {
              fuzzy = true;
              override_generic_sorter = true;
              override_file_sorter = true;
              case_mode = "smart_case";
            };
          };
        };
        settings = {
          defaults = {
            prompt_prefix = "› ";
            selection_caret = "▸ ";
            entry_prefix = "  "; # Two spaces for clean alignment
            multi_icon = "+ "; # Clear multi-select indicator
            path_display = [ "truncate" ];
            # Start selection at top instead of bottom
            sorting_strategy = "ascending";
            # Disable file icons to avoid font issues
            disable_devicons = true;
            # Show counter in prompt
            get_status_text = {
              __raw = ''
                function(self, opts)
                  local xx = (self.stats.processed or 0) - (self.stats.filtered or 0)
                  local yy = self.stats.processed or 0
                  if xx == 0 and yy == 0 then
                    return ""
                  end
                  return string.format("%s / %s", xx, yy)
                end
              '';
            };
            file_ignore_patterns = [
              "%.git/.*"
              "node_modules/.*"
              "%.npm/.*"
              "%.vscode/.*"
            ];
            layout_strategy = "vertical";
            layout_config = {
              vertical = {
                width = 0.9;
                height = 0.9;
                preview_height = 0.75;
                mirror = true;
                prompt_position = "top";
              };
            };
            # Clean visual separators
            borderchars = [ "─" "│" "─" "│" "┌" "┐" "┘" "└" ];
            mappings = {
              i = {
                "<C-k>" = {
                  __raw = "require('telescope.actions').move_selection_previous";
                };
                "<C-j>" = {
                  __raw = "require('telescope.actions').move_selection_next";
                };
                "<C-q>" = {
                  __raw = "require('telescope.actions').send_selected_to_qflist + require('telescope.actions').open_qflist";
                };
                "<esc>" = {
                  __raw = "require('telescope.actions').close";
                };
              };
              n = {
                "<esc>" = {
                  __raw = "require('telescope.actions').close";
                };
                "q" = {
                  __raw = "require('telescope.actions').close";
                };
              };
            };
          };
          pickers = {
            # Specific settings for grep_string picker
            grep_string = {
              sorting_strategy = "ascending";
              layout_config = {
                vertical = {
                  prompt_position = "top";
                  mirror = true;
                };
              };
            };
            # Apply same to live_grep for consistency
            live_grep = {
              sorting_strategy = "ascending";
              layout_config = {
                vertical = {
                  prompt_position = "top";
                  mirror = true;
                };
              };
            };
          };
        };
      };

      # Git integration
      gitsigns = {
        enable = true;
        settings = {
          current_line_blame = false;
          current_line_blame_opts = {
            virt_text = true;
            virt_text_pos = "eol";
            delay = 1000;
          };
          signs = {
            add = { text = "+"; };
            change = { text = "~"; };
            delete = { text = "_"; };
            topdelete = { text = "‾"; };
            changedelete = { text = "~"; };
          };
        };
      };

      fugitive.enable = true;

      # Treesitter
      treesitter = {
        enable = true;
        settings = {
          highlight = {
            enable = true;
            additional_vim_regex_highlighting = false;
          };
          indent = {
            enable = true;
          };
          ensure_installed = [
            "bash"
            "c"
            "cpp"
            "go"
            "json"
            "lua"
            "nix"
            "python"
            "rust"
            "typescript"
            "javascript"
            "vim"
            "yaml"
            "markdown"
            "html"
            "css"
          ];
        };
      };

      # LSP configuration
      lsp = {
        enable = true;
        servers = {
          # Nix
          nil_ls = {
            enable = true;
            settings = {
              formatting = {
                command = [ "nixpkgs-fmt" ];
              };
              nix = {
                flake = {
                  autoArchive = true;
                };
              };
            };
          };

          # Rust
          rust_analyzer = {
            enable = true;
            installCargo = false;
            installRustc = false;
            settings = {
              "rust-analyzer" = {
                cargo = {
                  allFeatures = true;
                };
                checkOnSave = {
                  command = "clippy";
                };
                rustfmt = {
                  extraArgs = [ "+nightly" ];
                };
              };
            };
          };

          # Python
          pyright.enable = true;

          # TypeScript/JavaScript
          ts_ls.enable = true;

          # Go
          gopls.enable = true;

          # Lua
          lua_ls = {
            enable = true;
            settings = {
              Lua = {
                diagnostics = {
                  globals = [ "vim" ];
                };
              };
            };
          };

          # Bash
          bashls.enable = true;

          # JSON
          jsonls.enable = true;

          # YAML
          yamlls.enable = true;

          # C/C++ with less aggressive diagnostics
          clangd = {
            enable = true;
            cmd = [
              "clangd"
              "--header-insertion=never"
              "--clang-tidy=false" # Disable clang-tidy for less red
              "--ranking-model=heuristics"
              "--completion-style=detailed"
              "--fallback-style=none" # Don't use any fallback style
              "--enable-config" # Explicitly enable .clang-format usage
            ];
          };
        };

        keymaps = {
          silent = true;
          lspBuf = {
            gd = "definition";
            gD = "declaration";
            gr = "references";
            gi = "implementation";
            gt = "type_definition";
            K = "hover";
            "<leader>ca" = "code_action";
            "<leader>rn" = "rename";
            "<leader>lf" = "format"; # Changed from <leader>f to avoid Telescope conflict
          };
          diagnostic = {
            "[d" = "goto_prev";
            "]d" = "goto_next";
            "<leader>d" = "open_float";
            "<leader>q" = "setloclist";
          };
        };
      };

      # Completion
      cmp = {
        enable = true;
        settings = {
          snippet = {
            expand = "function(args) require('luasnip').lsp_expand(args.body) end";
          };
          mapping = {
            "<C-d>" = "cmp.mapping.scroll_docs(-4)";
            "<C-f>" = "cmp.mapping.scroll_docs(4)";
            "<C-Space>" = "cmp.mapping.complete()";
            "<C-e>" = "cmp.mapping.close()";
            "<CR>" = "cmp.mapping.confirm({ select = true })";
            "<Tab>" = "cmp.mapping.select_next_item()";
            "<S-Tab>" = "cmp.mapping.select_prev_item()";
          };
          sources = [
            { name = "nvim_lsp"; }
            { name = "luasnip"; }
            { name = "buffer"; }
            { name = "path"; }
          ];
        };
      };

      # Command line completion
      cmp-cmdline.enable = true;

      # Snippets
      luasnip.enable = true;

      # Task runner and quickfix enhancements
      overseer = {
        enable = true;
        settings = {
          # Use jobstart strategy without terminal to prevent line wrapping
          # This avoids terminal emulation that wraps long lines at terminal width
          strategy = {
            "__unkeyed-1" = "jobstart";
            "__unkeyed-2" = {
              use_terminal = false; # Don't use terminal buffer, prevents line wrapping
              preserve_output = true; # Keep output when restarting tasks
            };
          };
          templates = [ "builtin" ];
          task_list = {
            direction = "bottom";
            height = 25;
            bindings = {
              "?" = "ShowHelp";
              "<CR>" = "RunAction";
              "<C-e>" = "Edit";
              "o" = "Open";
              "<C-v>" = "OpenVsplit";
              "<C-s>" = "OpenSplit";
              "<C-f>" = "OpenFloat";
              "p" = "TogglePreview";
              "<C-l>" = "IncreaseDetail";
              "<C-h>" = "DecreaseDetail";
              "L" = "IncreaseAllDetail";
              "H" = "DecreaseAllDetail";
              "[" = "DecreaseWidth";
              "]" = "IncreaseWidth";
              "{" = "PrevTask";
              "}" = "NextTask";
              "<C-k>" = "ScrollOutputUp";
              "<C-j>" = "ScrollOutputDown";
              "q" = "Close";
            };
          };
          # Configure components to populate quickfix on output
          component_aliases = {
            default = [
              "display_duration"
              { "__unkeyed-1" = "on_output_quickfix"; open_on_exit = "failure"; items_only = true; tail = false; }
              "on_exit_set_status"
              "on_complete_notify"
            ];
          };
        };
      };

      quicker = {
        enable = true;
        settings = {
          # Keys for expanding/collapsing context
          keys = [
            {
              __unkeyed-1 = ">";
              __unkeyed-2.__raw = ''function() require("quicker").expand({ before = 2, after = 2, add_to_existing = true }) end'';
              desc = "Expand quickfix context";
            }
            {
              __unkeyed-1 = "<";
              __unkeyed-2.__raw = ''function() require("quicker").collapse() end'';
              desc = "Collapse quickfix context";
            }
          ];
          # Follow cursor to show current item
          follow = {
            enabled = true;
          };
          # Enhanced highlighting
          highlight = {
            lsp = true;
            load = true;
          };
          # Display settings
          borders = {
            vert = "│";
          };
          # Type icons matching your current setup
          type_icons = {
            E = "E";
            W = "W";
            I = "I";
            N = "N";
            H = "H";
          };
          # Smart filename width - don't truncate filenames, let them use natural width
          max_filename_width.__raw = ''function() return 999 end'';
          # Enable editing capabilities
          edit = {
            enabled = true;
            autosave = true;
          };
        };
      };

      # Vim-repeat for enhanced dot command repetition
      repeat.enable = true;
    };


    # Essential extra config - SIMPLIFIED (autocmds moved to autoCmd or extraConfigLua)
    extraConfigVim = ''
      " Set up grep to use ripgrep
      set grepprg=rg\ --vimgrep\ --smart-case\ --follow
      set grepformat=%f:%l:%c:%m
      
      " Directory setup for backups/undo
      for bd in split(&backupdir, ',')
          execute 'silent !mkdir -p ' . bd
      endfor
      silent !mkdir -p ~/.vimundo
      
      " Enhanced diff mode highlighting (initial setup for when starting in diff mode)
      if &diff
        " Set cursor line highlighting in diff mode
        set cursorline
        
        " Define custom highlight groups for diff mode
        highlight DiffAdd    cterm=bold ctermfg=10 ctermbg=17 gui=bold guifg=#9ccc65 guibg=#13354a
        highlight DiffDelete cterm=bold ctermfg=10 ctermbg=17 gui=bold guifg=#ff5370 guibg=#13354a
        highlight DiffChange cterm=bold ctermfg=10 ctermbg=17 gui=bold guifg=#e2b93d guibg=#13354a
        highlight DiffText   cterm=bold ctermfg=10 ctermbg=88 gui=bold guifg=#000000 guibg=#f7ca88
        
        " Make cursor line very visible in diff mode
        highlight CursorLine cterm=underline,bold ctermbg=237 gui=underline,bold guibg=#3e4452
        highlight CursorLineNr cterm=bold ctermfg=yellow gui=bold guifg=#e2b93d
        
        " Better fold settings for diff mode
        set foldmethod=diff
        set foldcolumn=1
        
        " Ensure syntax highlighting is on
        syntax on
      endif
    '';

    # Additional Lua configuration for complex features
    extraConfigLua = ''
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
    '';

    # Additional packages for full functionality
    extraPackages = with pkgs; [
      # Language servers
      nil
      rust-analyzer
      gopls
      pyright
      typescript-language-server
      lua-language-server
      bash-language-server
      yaml-language-server

      # Formatters
      nixpkgs-fmt
      rustfmt
      black
      nodePackages.prettier

      # Tools
      ripgrep
      fd
      tree-sitter
      gcc # For treesitter compilation
      clang-tools # Provides clangd LSP server

      # Font with icon support (for devicons)
      # Note: You may need to configure your terminal to use a Nerd Font
      # such as "MesloLGS NF", "FiraCode Nerd Font", etc.
      nerd-fonts.meslo-lg
      nerd-fonts.fira-code
    ];
  };
}
