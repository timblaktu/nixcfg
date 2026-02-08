# modules/programs/neovim/neovim.nix
# Neovim/Nixvim configuration for all platforms [NDnd]
#
# Provides:
#   flake.modules.homeManager.neovim - Full nixvim config (LSP, treesitter, plugins)
#   flake.modules.nixos.neovim - Basic system-level neovim defaults
#   flake.modules.darwin.neovim - Basic system-level neovim defaults
#
# Features:
#   - Comprehensive nixvim configuration
#   - LSP support for multiple languages (Nix, Rust, Python, TypeScript, Go, etc.)
#   - Treesitter syntax highlighting
#   - Telescope fuzzy finder
#   - Git integration (gitsigns, fugitive)
#   - Tmux-navigator integration
#   - Overseer task runner
#   - Multiple colorscheme options
#   - WSL clipboard integration
#
# Usage in host config:
#   imports = [ inputs.self.modules.homeManager.neovim ];
{ config, lib, inputs, ... }:
{
  flake.modules = {
    # === Home Manager Module ===
    # Full neovim/nixvim configuration for user environment
    homeManager.neovim = { config, pkgs, lib, ... }:
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
          extraConfigLua = builtins.readFile ./extraConfigLua.lua;

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
      };

    # === NixOS Module ===
    # Basic system-level neovim configuration
    nixos.neovim = { pkgs, lib, ... }: {
      programs.neovim = {
        enable = lib.mkDefault true;
        defaultEditor = lib.mkDefault true;
        viAlias = lib.mkDefault true;
        vimAlias = lib.mkDefault true;
      };
    };

    # === Darwin Module ===
    # Basic system-level neovim configuration for Darwin
    darwin.neovim = { pkgs, lib, ... }: {
      # Darwin doesn't have programs.neovim at system level
      # Users should use the homeManager.neovim module
      environment.systemPackages = with pkgs; [
        neovim
      ];
    };
  };
}
