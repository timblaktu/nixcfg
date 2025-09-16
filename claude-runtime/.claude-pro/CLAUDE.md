# Claude Code Configuration for User tim

## ⚠️ CRITICAL: Git Commit Rules ⚠️

**These rules apply to ALL commits - NO EXCEPTIONS:**

- **NEVER** include Claude's identity, "Generated with Claude Code", 🤖, or "Co-Authored-By: Claude"
- **ALWAYS** write commit messages as if authored by the human user
- **NO AI attribution** in commit messages - they should appear human-authored
- **Focus on technical content** - describe what changed and why

**Examples:**
- ✅ GOOD: "Fix MCP server configuration enforcement"
- ❌ BAD: "Fix MCP server configuration enforcement 🤖 Generated with Claude Code"

## Custom Memory Management Commands (Implemented 2025-08-21)

### Available Commands
- `/nixmemory` - Opens user-global memory file in editor (like /memory but always user-scoped)
- `/nixremember <content>` - Appends content to memory (like # command but for Nix-managed memory)

### Command Aliases
- `/usermemory` → `/nixmemory`
- `/globalmemory` → `/nixmemory`  
- `/userremember` → `/nixremember`
- `/globalremember` → `/nixremember`

### Important Notes
- These commands write to `/home/tim/src/nixcfg/claude-runtime/.claude-max/CLAUDE.md` (this file)
- Changes auto-commit to git and rebuild to propagate to all accounts
- Built-in `/memory` and `#` commands will fail on read-only files - use the /nix* versions instead
- This file is the single source of truth for all Claude Code account configurations

## AI Guidance

### 🔥 CRITICAL: github.com/timblaktu Repository Ownership 🔥
- **ALL github.com/timblaktu repositories are USER-OWNED**
- When encountering issues with timblaktu repos, **NEVER work around the issue**
- **ALWAYS locate the local working tree** and work there in an appropriate branch
- **NEVER change flake inputs** to avoid timblaktu repos - we own them and should fix them

**Known Local Repository Locations:**
- home-manager: `~/src/home-manager` (work in fork remote branch)
- NixOS-WSL: Location TBD (if needed)
- Other timblaktu repos: Check ~/src/ directory

**Workflow for timblaktu repo issues:**
1. Identify the issue in the timblaktu repo
2. Navigate to local working tree (e.g., `cd ~/src/home-manager`)
3. Checkout appropriate branch (`git checkout fork/feature-test` or create new branch)
4. Fix the issue directly in the codebase
5. Test the fix
6. Commit and push to fork
7. Update flake.lock if needed

### General AI Guidance
- ALWAYS ensure any generated shell commands support both bash AND zsh syntaxes
- ALWAYS properly escape or quote special shell characters when generating commands
* After receiving tool results, carefully reflect on their quality and determine optimal next steps
* For maximum efficiency, invoke multiple independent tools simultaneously rather than sequentially
* Before finishing, verify your solution addresses all requirements
* Do what has been asked; nothing more, nothing less
* NEVER create files unless absolutely necessary
* ALWAYS prefer editing existing files to creating new ones
* ALWAYS use fd to find files and ripgrep (rg) to search files.
* ALWAYS add documentation to existing markdown files instead of creating new files 
* ALWAYS ASK where to add documentation if there is significant ambiguity or uncertainty
* ALWAYS use `echo "$WSL_DISTRO_NAME"` to determine if you're running in WSL, and what WSL instance you and/or your MCP servers are running in.
* If running in WSL, you can access other WSL instances' rootfs mounted at `/mnt/wsl/$WSL_DISTRO_NAME/`
* When I ask you to read screenshot(s), you read that most recent N image files from `/mnt/wsl/tblack-t14-nixos/mnt/c/Users/tblack/OneDrive/Pictures/Screenshots 1`

## CRITICAL RULE: Always Use MCP Tools for Nix Configuration (Added 2025-08-27)

**ALWAYS use mcp-nixos MCP server tools to verify NixOS and Home Manager options BEFORE making any configuration changes.**

### Why this is critical:
1. NixOS and Home Manager options change between versions
2. Options can be deprecated, renamed, or removed (e.g., `programs.zsh.initExtra` → `programs.zsh.initContent`)
3. Different modules may have different option names (e.g., bash uses `initExtra`, zsh uses `initContent`)
4. Making assumptions leads to evaluation warnings and errors

### Required workflow for Nix configuration changes:
1. **Before editing**: Use `mcp__mcp-nixos__home_manager_info` or `mcp__mcp-nixos__nixos_info` to check if option exists
2. **If not found**: Use `mcp__mcp-nixos__home_manager_search` or `mcp__mcp-nixos__nixos_search` to find correct option
3. **For exploration**: Use `mcp__mcp-nixos__home_manager_options_by_prefix` to browse available options
4. **Always verify**: The exact option name, type, and description before use

### Example of correct approach:
```
# Before using any option, verify it exists:
mcp__mcp-nixos__home_manager_info("programs.zsh.initExtra")
# Result: NOT FOUND
mcp__mcp-nixos__home_manager_options_by_prefix("programs.zsh")  
# Result: Shows programs.zsh.initContent is the correct option
```

## CRITICAL RULE: Development Environment Limitations (Added 2025-08-27)

**NEVER attempt to run commands through `nix develop` or `nixdev.sh` programmatically.**

### Why this fails:
1. The FHS environment runScript uses `exec "${pkgs.bashInteractive}/bin/bash" -l` at the end
2. This **replaces the entire process** with an interactive bash shell  
3. Any `-c` commands or programmatic execution gets lost when exec runs
4. The system is designed solely for human interactive use, not automation

### What I must do instead:
- **Build/check only**: Use `nix flake check`, `nix build`, etc. for validation
- **Ask user to test**: Request the user manually test commands that need the FHS environment
- **Document testing steps**: Provide clear instructions for manual testing
- **Never assume**: Don't try `nixdev.sh -c`, `nix develop -c`, or similar patterns

### Example of correct approach:
```
"I've consolidated the scripts and updated flake.nix. The build passes with `nix flake check`. 
Please test the consolidated script by entering the FHS environment and running:
  remote-wifi-analyzer --help
  remote-wifi-analyzer scan-rank -b 5g"
```

This rule prevents repeated failed assumptions about development environment capabilities.

## Active Configuration

### Model
- Default: sonnet
- Debug mode: disabled

### MCP Servers (Current Status - 2025-08-27)

**✅ ARCHITECTURE SIMPLIFICATION COMPLETE**

All three core MCP servers are now working with the simplified template-based architecture:

- **sequential-thinking**: ✅ **WORKING** - NPM template via `npx @modelcontextprotocol/server-sequential-thinking`
- **context7**: ✅ **WORKING** - NPM template via `npx @upstash/context7-mcp`
- **mcp-nixos**: ✅ **WORKING** - Nix run template via `nix run github:utensils/mcp-nixos --`

**Architectural Changes Completed (2025-08-27):**
1. ✅ **Removed nixmcp dependency** - Eliminated 45+ flake inputs and complex Python/uv2nix framework
2. ✅ **Implemented template-based architecture** - Using language-appropriate tools
3. ✅ **All servers operational** - Clean builds without dependency conflicts
4. ✅ **Configuration enforcement working** - Settings properly applied on `home-manager switch`

**Server Templates Now Available:**
- **NPM Template**: For TypeScript servers published to NPM (context7, sequential-thinking)
- **Nix Run Template**: For GitHub repos with flakes (mcp-nixos)
- **Direct Binary Template**: For future custom Nix packages

**Status**: Ready for live testing in Claude Code sessions


### Sub-Agents
- code-searcher


### Slash Commands
- /documentation generate-readme
    - /documentation api-docs
- /security audit
    - /security secrets-scan
- /refactor extract-function
    - /refactor rename-symbol
- /context cleanup
    - /context save
    - /context load


### Active Hooks
- Security checks: 
- Auto-formatting: 
- Linting: 
- Testing: 
- Git integration: 
- Logging: 
- Notifications: 

## Project-Specific Configuration

## Performance Tips

- Use sub-agents for specialized tasks to reduce token usage
- Leverage slash commands for common operations
- Enable caching where appropriate
- Use project overrides for context-specific settings

## Troubleshooting

- Check logs at: ~/.claude/logs/tool-usage.log
- Debug mode: Set `programs.claude-code.debug = true`
- MCP server issues: Check `/tmp/claude_desktop.log` and `~/AppData/Roaming/Claude/logs/`
- Hook failures: Review hook timeout settings
- MCP Documentation: See `home/modules/README-MCP.md` for detailed troubleshooting

## Recent MCP Fixes (2025-08-21 to 2025-08-23)

- **WSL Environment Variables**: Fixed by embedding env vars in shell commands
- **Context7 Package**: Fixed by using `@upstash/context7-mcp` instead of `context7`
- **Sequential-thinking Module**: Fixed path from `server_fastmcp` to `server`
- **CLI Server ALLOWED_DIR**: Fixed by properly passing env var through WSL wrapper

## Sequential-Thinking Complete Resolution (2025-08-23)

- **TaskGroup Runtime Issues**: Fixed MCP protocol compatibility in Python port (commit a4bc00f)
  - Fixed stdio_server() API usage for proper MCP communication
  - Corrected InitializationOptions parameter handling
- **Configuration Path Issue**: Updated `.claude.json` to working binary path
  - Old broken path: `/nix/store/qrnxh0qmmdwnnqxcilnqh6nzycnhw1n4-sequential-thinking-mcp-env/bin/sequential-thinking-mcp`
  - New working path: `/nix/store/09402xpiigl14mvazwcnssh68nkdfycc-sequential-thinking-mcp-env/bin/sequential-thinking-mcp`
- **Status**: Both context7 and sequential-thinking fully operational - restart Claude Code to apply changes

## STATUSLINE IMPLEMENTATION COMPLETE ✅ (2025-08-25)

### 🎯 Claude Code Statusline Integration - PRODUCTION READY & DEPLOYED

**Implementation Status**: ✅ **COMPLETE & VALIDATED** - All features implemented, tested, deployed, and verified working

**Update (2025-08-26)**: Comprehensive testing confirms all statusline components operational:
- Test command `test-claude-statusline` producing correct formatted output  
- All 5 statusline styles built and available via Nix
- CLI tool integration validated (jq, git, sha256sum, etc.)
- Multi-account configuration ready for live Claude Code integration

#### Major Achievement:
- **5 statusline styles implemented**: powerline, minimal, context-aware, box, fast
- **pkgs.writers integration**: Build-time validation with proper CLI tool dependencies  
- **Multi-account support**: Ready for both `claudepro` and `claudemax` commands
- **Production testing**: `test-claude-statusline` command working perfectly

#### ✅ TESTING COMPLETE - SUCCESSFUL DEPLOYMENT:
1. ✅ Local changes staged and committed
2. ✅ `home-manager switch --flake '.#tim@tblack-t14-nixos'` - SUCCESS
3. ✅ Statusline scripts built and installed successfully
4. ✅ Test command working: `test-claude-statusline` produces beautiful output
5. 🎯 Ready for Claude Code integration testing

**Working Test Output:**
```
◉ test@example.com ❯ ~/s…/nixcfg ⎇ thinky-nixos │ 4.1-O │ $0.42
```

**Build Issue Resolved:**
- **Root Cause**: Sequential-thinking MCP server enabled by default causing path hash mismatch
- **Resolution**: Set `sequentialThinking.enable = false` in `mcp-servers.nix`  
- **Result**: Home-manager switch successful, all statusline components built

**Files Successfully Deployed:**
- `claude-statusline-minimal` - Primary statusline script with full CLI tool integration
- `test-claude-statusline` - Testing command with mock JSON data  
- Settings integration through `_internal.statuslineSettings` system

#### Style Options Available:
- **minimal** (current): Clean single-line, smart abbreviations
- **powerline**: Segment-based with powerline separators
- **context**: Information-dense with git stats, session timing
- **box**: Multi-line Unicode box drawing with ahead/behind
- **fast**: Performance-optimized with 5-second caching

#### CLI Tools Leveraged:
- **jq**: JSON parsing (required)
- **git**: Branch detection, status, ahead/behind  
- **sha256sum/md5sum**: Consistent account colors
- **sed/awk**: Text processing, model abbreviation
- **bc**: Floating point calculations (box style)
- **python3**: Advanced hashing (box style)
- **find**: Caching system (fast style)

#### Next Phase: Advanced Features & Optimization
- **Ready for Live Testing**: Core statusline integration complete and operational
- **Account-Specific Styling**: Test differentiation between `claudepro` vs `claudemax` styling
- **Real-Time Validation**: Validate JSON data integration in live Claude Code sessions
- **Style Expansion**: Enable additional styles via `enableAllStyles = true` for user choice
- **Performance Monitoring**: Track statusline rendering performance in production usage

## FHS Environment Debugging Lessons (2025-08-29 - Updated 2025-08-31)

### Common Issues with buildFHSEnv and User .bashrc Interaction

When working with Nix buildFHSEnv and custom user .bashrc files:

1. **Unbound variable errors**: User's .bashrc with `set -u` may reference variables not set in FHS environment
   - Solution: Export required variables early in runScript before bash initialization
   - Common variables: `IN_NIX_SHELL`, `FHS_NAME`, custom environment indicators

2. **Multiple sourcing of initialization scripts**: 
   - `/etc/profile` sourced only by login shells (`bash -l`), not by `bash -c`
   - Interactive shells may source scripts multiple times through different paths
   - Solution: Add sourcing guards using environment variables

3. **Command execution in FHS environments**:
   - `"$@"` treats quoted strings with spaces as single command name
   - Solution: Detect and route through `bash -c` for proper shell parsing

4. **Critical insight**: `nix develop -c` runs in Nix shell environment, NOT in FHS namespace
   - FHS environment only exists when the FHS binary is executed
   - This is why wrappers like nixdev.sh remain necessary

### Debugging Approach
- Test both interactive (`./wrapper`) and command (`./wrapper cmd`) modes separately
- Use verbose flags to trace initialization sequence
- Check user's .bashrc for variable references and `set -u` usage
- Understand the shell initialization chain: runScript → bash -l → /etc/profile → /etc/profile.d/* → ~/.bashrc

### Additional FHS Environment Issues (2025-08-31)

1. **PS1 prompt not persisting in interactive shells**:
   - Setting PS1 in profile.d scripts gets overridden by bash
   - Setting PS1 in buildFHSEnv's `profile` option doesn't stick
   - ANSI-C quoting (`$'...'`) needed for escape sequences but still doesn't persist
   - Pragmatic solution: Set PS1 directly in runScript before exec bash

2. **Directory changes in buildprep.env not persisting**:
   - cd inside redirection blocks `{ }` doesn't affect parent shell
   - Profile.d context vs non-profile.d context creates different behaviors
   - Solution: Add cd AFTER redirection block completes

3. **Dual execution paths in complex scripts**:
   - Scripts that detect context (profile.d vs direct sourcing) are hard to debug
   - Both paths may execute in unexpected ways
   - Consider simplifying to single execution path where possible
## Memory Entry - 2025-08-31 14:02:29
Test memory entry from Claude Code

## Memory Entry - 2025-08-31 15:15:07
Test memory entry from Claude Code

## ✅ NIXMEMORY SLASH COMMANDS FIXED (2025-08-31)

**Problem Resolved**: /nixmemory and related commands were trying to open editors directly from Claude Code, which doesn't work due to terminal control limitations.

**Root Cause**: Current implementation in `memory-commands.nix` naively called `$EDITOR "$MEMORY_FILE"` which cannot take terminal control from Claude Code.

**Solution Applied**: Restored tmux integration from original design that we had previously implemented but was lost.

### Fixed Implementation Features:

**Tmux Integration** (`memory-commands.nix:36-48`):
- **In tmux session**: Opens editor in split pane using `tmux split-window -d -v -p 30`
- **Not in tmux**: Provides file location and manual editing instructions  
- **No tmux available**: Shows direct editing commands

**Smart Permission Management**:
- Background process monitors for editor closure in tmux pane
- Automatically restores read-only permissions when editor exits
- Manual file editing bypasses permission automation

**User Experience**:
```bash
# In tmux:
📝 Opening user-global memory file in tmux pane...
✅ Opened nvim in tmux pane below
💡 Tips: Switch panes: Ctrl-b then arrow keys

# Not in tmux:  
You're not in a tmux session. Options:
1. Start tmux first: tmux new -s claude
2. Edit directly in terminal: nvim /path/to/CLAUDE.md
3. Use /nixremember to append content
```

### Technical Details:

**Claude Code Limitations Confirmed**:
- Slash command hooks cannot take terminal control
- Interactive programs cannot run directly from Claude Code commands
- No capability to background/foreground processes within Claude Code

**Tmux Workaround Architecture**:
- `tmux split-window` creates new interactive pane outside Claude Code's control
- Original pane (Claude Code) remains responsive
- User can switch between panes for editing and Claude interaction

**Files Updated**:
- `/home/tim/src/nixcfg/home/modules/claude-code/memory-commands.nix` - Core implementation
- Command documentation updated to explain tmux integration approach
- Applied via `home-manager switch` on 2025-08-31

### Status: ✅ Ready for Testing

All /nixmemory family commands (/usermemory, /globalmemory) now properly handle editor opening via tmux integration. Test in tmux session for full functionality.


## Memory Entry - 2025-08-31 15:49:12
### Tmux Tips Updated (2025-08-31)

**Fix Applied**: Updated /nixmemory command tips to use "Prefix" instead of hardcoded "Ctrl-b" to respect user's tmux prefix remapping (Ctrl-a).

**File Updated**: `/home/tim/src/nixcfg/home/modules/claude-code/memory-commands.nix:46`

**Change**: `Switch panes: Ctrl-b then arrow keys` → `Switch panes: Prefix then arrow keys`


## Memory Entry - 2025-09-01 - Major Accomplishments

### WSL Tarball Distribution Enhancements
- Implemented comprehensive security checks module (wsl-tarball-checks.nix)
- Enhanced build-wsl-tarball script to accept configuration names as parameters
- Added automated scanning for personal identifiers, SSH keys, and sensitive environment variables
- Created documentation for anonymization and distribution best practices
- Script now supports timestamped output files and shows available configurations

### Slash Command Architecture Redesign  
- **Problem Solved**: Eliminated git churn from constantly changing symlink targets
- **Root Cause**: Home-manager symlinks to Nix store paths changed with every rebuild
- **Solution**: Static wrapper pattern - 3-line scripts that exec commands on PATH
- **Implementation**: memory-commands-static.nix with staticCommands.enable flag
- **Result**: Zero git changes after initial file creation while maintaining all functionality
- **Documentation**: Created comprehensive README, migration guide, and updated all related docs

### Key Technical Insights
- Symlinks in git repos cause unnecessary churn when pointing to Nix store
- Static wrappers with PATH-based execution provides clean separation
- Interface (static files) vs Implementation (PATH commands) pattern works well
- Standard Unix patterns (PATH resolution) solve modern problems elegantly

### Files Created/Modified Today
- modules/wsl-tarball-checks.nix - Security check implementation
- home/modules/claude-code/memory-commands-static.nix - Static wrapper implementation  
- home/modules/claude-code/README.md - Module documentation
- home/modules/claude-code/SLASH-COMMANDS-MIGRATION.md - Migration guide
- NIXOS-WSL-DISTRIBUTION.md - Enhanced with security checks documentation
- home/files/bin/build-wsl-tarball - Added parameter support

### Testing Status
- ✅ WSL tarball builds successfully with security checks
- ✅ Git status shows no changes after home-manager rebuild
- 🔄 Slash commands need testing in new Claude Code session

## Memory Entry - 2025-09-16 - Flake Input Repository Branching Workflows Research Complete

### Key Research Findings:
- **Original git worktree approach** with environment variables in flake.nix conflicts with Nix purity model
- **Refined approach** using AST-based manipulation maintains purity while achieving automation benefits
- **rnix-parser** provides foundation for safe Nix code manipulation preserving formatting  
- **nixfmt** is official formatter with rewrite capabilities
- **Git worktree patterns** for parallel development actively used in 2024-2025 AI workflows

### Technical Solutions Researched:
- **--override-input**: Changes flake inputs at flake level (implies --no-write-lock-file)
- **--redirect**: Redirects store paths to local directories at derivation level
- **rnix-parser**: Rust AST parser works on incomplete/broken code, preserves 100% formatting
- **Git metadata storage**: Use git config for workspace configuration (like git submodules pattern)

### Recommended Implementation Strategy:
1. **flake.nix always contains literal URLs** (no template variables)
2. **Workspace script manages URLs** via AST manipulation using rnix-parser
3. **Git config stores workspace metadata**: `git config workspace.feature.repo branch`
4. **Import/export API** converts existing flake.nix to workspace config  
5. **Maintains Nix purity** while eliminating URL switching friction

### Documentation Updated: 
- **FLAKE-SUPERPROJECT-WORKFLOW.md** with comprehensive refined approach section
- **Research insights** on Nix code manipulation ecosystem and git worktree patterns
