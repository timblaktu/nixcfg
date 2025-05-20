# Neovim configuration
{ config, lib, pkgs, inputs, ... }:

{
  programs.neovim = {
    enable = true;
    defaultEditor = true;
    viAlias = true;
    vimAlias = true;
    
    plugins = with pkgs.vimPlugins; [
      # Basic Functionality
      plenary-nvim
      nvim-web-devicons
      which-key-nvim
      
      # Color schemes
      tokyonight-nvim
      catppuccin-nvim
      onedark-nvim
      
      # UI Enhancements
      lualine-nvim
      bufferline-nvim
      nvim-tree-lua
      
      # Editor Enhancements
      telescope-nvim
      telescope-fzf-native-nvim
      comment-nvim
      vim-surround
      vim-repeat
      
      # Git integration
      gitsigns-nvim
      vim-fugitive
      
      # LSP
      nvim-lspconfig
      nvim-cmp
      cmp-nvim-lsp
      cmp-buffer
      cmp-path
      cmp-cmdline
      luasnip
      cmp_luasnip
      
      # Treesitter
      (nvim-treesitter.withPlugins (plugins: with plugins; [
        bash
        c
        cpp
        go
        json
        lua
        nix
        python
        rust
        typescript
        vim
        yaml
      ]))
    ];
    
    extraPackages = with pkgs; [
      # Language servers
      nil # Nix
      rust-analyzer
      gopls
      pyright
      typescript-language-server
      lua-language-server
      
      # Tools
      ripgrep
      fd
      tree-sitter
    ];
    
    extraLuaConfig = ''
      -- Basic settings
      vim.opt.number = true
      vim.opt.relativenumber = true
      vim.opt.shiftwidth = 2
      vim.opt.tabstop = 2
      vim.opt.expandtab = true
      vim.opt.smartindent = true
      vim.opt.termguicolors = true
      vim.opt.updatetime = 100
      vim.opt.timeout = true
      vim.opt.timeoutlen = 300
      vim.opt.completeopt = "menuone,noselect"
      vim.opt.mouse = "a"
      
      -- Set colorscheme
      vim.cmd("colorscheme tokyonight")
      
      -- Set leader key
      vim.g.mapleader = " "
      vim.g.maplocalleader = " "
      
      -- Basic keymaps
      vim.keymap.set("n", "<leader>e", ":NvimTreeToggle<CR>", { silent = true })
      vim.keymap.set("n", "<leader>ff", ":Telescope find_files<CR>", { silent = true })
      vim.keymap.set("n", "<leader>fg", ":Telescope live_grep<CR>", { silent = true })
      vim.keymap.set("n", "<leader>fb", ":Telescope buffers<CR>", { silent = true })
      
      -- Initialize plugins
      require("nvim-tree").setup()
      require("lualine").setup()
      require("bufferline").setup()
      require("gitsigns").setup()
      require("Comment").setup()
      
      -- LSP Configuration
      local lspconfig = require('lspconfig')
      local capabilities = require('cmp_nvim_lsp').default_capabilities()
      
      -- Setup language servers
      lspconfig.nil_ls.setup { capabilities = capabilities }
      lspconfig.rust_analyzer.setup { capabilities = capabilities }
      lspconfig.pyright.setup { capabilities = capabilities }
      lspconfig.tsserver.setup { capabilities = capabilities }
      lspconfig.gopls.setup { capabilities = capabilities }
      lspconfig.lua_ls.setup { capabilities = capabilities }
      
      -- Completion setup
      local cmp = require('cmp')
      local luasnip = require('luasnip')
      
      cmp.setup({
        snippet = {
          expand = function(args)
            luasnip.lsp_expand(args.body)
          end,
        },
        mapping = cmp.mapping.preset.insert({
          ['<C-d>'] = cmp.mapping.scroll_docs(-4),
          ['<C-f>'] = cmp.mapping.scroll_docs(4),
          ['<C-Space>'] = cmp.mapping.complete(),
          ['<CR>'] = cmp.mapping.confirm({ select = true }),
          ['<Tab>'] = cmp.mapping(function(fallback)
            if cmp.visible() then
              cmp.select_next_item()
            elseif luasnip.expand_or_jumpable() then
              luasnip.expand_or_jump()
            else
              fallback()
            end
          end, { 'i', 's' }),
          ['<S-Tab>'] = cmp.mapping(function(fallback)
            if cmp.visible() then
              cmp.select_prev_item()
            elseif luasnip.jumpable(-1) then
              luasnip.jump(-1)
            else
              fallback()
            end
          end, { 'i', 's' }),
        }),
        sources = cmp.config.sources({
          { name = 'nvim_lsp' },
          { name = 'luasnip' },
          { name = 'buffer' },
          { name = 'path' }
        })
      })
    '';
  };
}
