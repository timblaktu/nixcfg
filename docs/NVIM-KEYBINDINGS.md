#  🔍 How to Discover Keybindings at Any Moment

1. Which-Key Plugin (Your Best Friend)

You have which-key enabled, which is perfect! Just press:
- <Space> (your leader key) and wait - which-key will pop up showing all
leader-based keybindings
- Try pressing <Space> then c, f, d, or t to see categorized groups:
  - <leader>c - Colorschemes
  - <leader>f - Find/Telescope
  - <leader>d - Diff/Git
  - <leader>t - Tasks/Overseer

2. In Vim Commands

- :map - Shows all mappings
- :nmap - Normal mode mappings
- :vmap - Visual mode mappings
- :verbose map <key> - Shows where a specific mapping was defined

📍 Where to Look in Your Nix Config

Your keybindings are in three main locations in nixvim.nix:

1. Lines 131-208: Core keymaps array
2. Lines 223-241: Which-key group descriptions
3. Lines 843-862: LSP-specific keymaps

🧠 Best Practices for Learning & Remembering

Memory Technique: "Muscle Memory Layers"

1. Start with essentials (use these constantly for a week):
  - <Space>ff - Find files
  - <Space>fg - Live grep
  - <Tab>/<S-Tab> - Buffer navigation
  - <Enter> - Clear search highlight
2. Add one category per week:
  - Week 2: Git/Diff (<leader>d*)
  - Week 3: Tasks (<leader>t*)
  - Week 4: LSP (gd, gr, K)
3. Create a "cheat sheet" comment in your terminal:
# Add to your .bashrc/.zshrc
alias vimkeys='echo "
ESSENTIAL:
<Space>ff - Find files
<Space>fg - Live grep
<Tab> - Next buffer
gcc - Toggle comment
"'

⌨️ Your Key Bindings Reference

Essential Navigation

- <Enter> - Clear search highlight
- <Tab> - Next buffer
- <S-Tab> - Previous buffer
- <leader>x - Close buffer (smart)

File/Search (Telescope)

- <leader>e - File tree toggle
- <leader>ff - Find files
- <leader>fg - Live grep
- <leader>fw - Search current word
- <leader>fb - Browse buffers
- <leader>fh - Help tags

Quickfix Navigation

- ]q/[q - Next/previous quickfix
- ]Q/[Q - Last/first quickfix
- <leader>q - Toggle quickfix window

Comments

- gcc - Toggle line comment
- <leader>/ - Toggle line comment (alternative)
- <leader>? - Toggle block comment

Git/Diff

- ]c/[c - Next/previous diff change
- ]x/[x - Next/previous conflict marker
- <leader>dgl - Get LOCAL version
- <leader>dgr - Get REMOTE version

LSP (When attached)

- gd - Go to definition
- gr - Find references
- K - Hover documentation
- <leader>ca - Code actions
- <leader>rn - Rename symbol

Colorschemes

- <leader>cg - Gruvbox (current)
- <leader>cd - Solarized Dark
- <leader>ct - Tokyo Night
- <leader>cc - Catppuccin

Tasks (Overseer)

- <leader>tr - Run task
- <leader>tt - Toggle task list
- <leader>tb - Build task

💡 Pro Tips

1. Your timeoutlen is 150ms - Be quick with leader sequences!
2. Very magic regex - Your / search uses \v by default (more intuitive
regex)
3. Visual search - Select text and press // to search for it
4. Help on word - <Leader>K opens help for word under cursor

🎯 Quick Practice Session

Try this sequence right now to build muscle memory:
1. Open vim
2. Press <Space> and wait - see which-key
3. <Space>ff - find a file
4. <Tab> - cycle buffers
5. gcc - comment a line
6. <Space>fg - search for something
7. Press q in Telescope to quit

The key is consistent daily practice with a small set of bindings, then
gradually expanding!
