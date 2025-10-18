# Fix: Make PTY width configurable to prevent output truncation

## Problem
When overseer runs tasks with `use_terminal=true` (the default), it sets a PTY width of `vim.o.columns - 4`. This causes compiler output and other program output to be truncated when the Neovim window is narrow (~100 columns or less), as programs detect the terminal width and adjust their output accordingly.

This is especially problematic for compiler error messages that get cut off in the quickfix window, making debugging difficult.

## Solution
This PR adds a new `pty_width` option to the jobstart strategy that allows users to configure the PTY width behavior:

- `"auto"` (default): Current behavior - uses `vim.o.columns - 4`
- `<number>`: Set a fixed width (e.g., `500`) to prevent truncation
- `nil`: Don't specify any width constraint, letting the PTY use its default

## Usage Examples

### Prevent truncation with a fixed width:
```lua
require("overseer").setup({
  strategy = { 
    "jobstart",
    {
      use_terminal = true,
      pty_width = 500,  -- Fixed width prevents truncation
    }
  }
})
```

### Disable width specification entirely:
```lua
require("overseer").setup({
  strategy = { 
    "jobstart",
    {
      use_terminal = true,
      pty_width = nil,  -- No width constraint
    }
  }
})
```

### Keep current behavior (default):
```lua
require("overseer").setup({
  strategy = { 
    "jobstart",
    {
      use_terminal = true,
      pty_width = "auto",  -- Same as vim.o.columns - 4
    }
  }
})
```

## Testing
Tested with narrow Neovim windows (~100 columns) running C++ compilation with long error messages. With `pty_width = 500`, error messages are no longer truncated in the quickfix window.

## Breaking Changes
None - the default behavior remains unchanged. This is a backward-compatible enhancement.

## Related Issues
- Fixes #445 - Compiler output truncated when Neovim window is narrow
- Related to #202 - General discussion of line truncation in Neovim terminal buffers

## Notes
This change gives users control over the PTY width to work around the terminal width detection that many programs (compilers, linters, formatters) perform, ensuring their output isn't truncated based on the current window size.