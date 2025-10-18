# Compiler output truncated when Neovim window is narrow

## Problem

When running compilation tasks through overseer with the default `jobstart` strategy and `use_terminal=true`, compiler error messages get truncated based on the width of the Neovim window at the time the task starts.

## Steps to Reproduce

1. Open Neovim in a narrow window (~100 columns or less)
2. Create a C++ file with a compilation error that produces a long error message:
```cpp
// test.cpp
#include <iostream>
int main() {
    st << "This should cause a very long error message about 'st' not being declared in this scope" << std::endl;
    return 0;
}
```
3. Run `:OverseerRun` and select "make" or compile the file
4. Check the quickfix window - the error message is truncated (e.g., `error: 'st' was no...` instead of the full message)

## Expected Behavior

Compiler error messages should appear in full in the quickfix window, regardless of Neovim's window width.

## Actual Behavior

Error messages are truncated at the column width of the Neovim window when the task was started.

## Root Cause

The `jobstart` strategy sets a PTY width of `vim.o.columns - 4` when `use_terminal=true`:
https://github.com/stevearc/overseer.nvim/blob/6fe36fc338fbeaf35b0f801c25f7f231c431a64b/lua/overseer/strategy/jobstart.lua#L138-L140

This causes programs (compilers, linters, etc.) to detect the narrow terminal width and truncate their output accordingly.

## Workarounds

1. Maximize the Neovim window before running compilation
2. Use `use_terminal=false` in the strategy configuration (loses terminal highlighting)
3. Set environment variables `COLUMNS=500` and `TERM=dumb` (not all programs respect these)

## Proposed Solution

Make the PTY width configurable in the `jobstart` strategy options, allowing users to:
- Keep the current auto behavior (default)
- Set a fixed width to prevent truncation
- Disable width constraints entirely

This would give users control over the trade-off between terminal display aesthetics and output completeness.

## Environment

- Neovim version: v0.10.0+
- overseer.nvim version: latest
- OS: Linux (WSL2)

## Related

This is related to #202 which discusses general Neovim terminal buffer truncation issues, but this specific issue is about the configurable PTY width constraint that overseer applies.