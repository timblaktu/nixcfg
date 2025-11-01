# New Chat Session: Enhance git-worktree-superproject for Nix Flake Support

## 🎯 **MISSION STATEMENT**

Extend the existing git-worktree-superproject tool to support **Nix flakes as first-class superprojects**, enabling sophisticated per-workspace flake input management for multi-fork development scenarios.

## 📋 **IMMEDIATE PRIORITY TASKS**

1. **Implement Nix flake detection in wt-super**
   - Add flake.nix detection to workspace script
   - Parse flake inputs and extract repository specifications
   - Integrate with existing git config-based repository management

2. **Add flake input configuration commands**
   - Extend `workspace config` subcommands for flake inputs
   - Support commands like `workspace config set-flake-input <workspace> <input> <url> [ref]`
   - Store flake input overrides in git config (`workspace.flake.input.*`)

3. **Create per-workspace flake input override system**
   - Generate workspace-specific flake.nix files with appropriate inputs
   - Support mixing upstream and fork inputs per workspace
   - Maintain backwards compatibility with existing wt-super functionality

4. **Test with nixcfg multi-fork development**
   - Apply enhanced wt-super to nixcfg project
   - Create workspaces for different input combinations (upstream, all-forks, nixpkgs-only)
   - Validate parallel development workflow

## 🏗️ **TECHNICAL ARCHITECTURE**

### **Current nixcfg Challenge**
- Fork development (nixpkgs, home-manager, NixOS-WSL) blocks other work
- Manual flake.nix input switching is error-prone and friction-heavy
- Need parallel development: fork work AND mainstream development

### **Enhanced wt-super Solution**
```
nixcfg/                         # Enhanced with wt-super
├── workspace                   # Enhanced script with flake support
├── .git/config                 # Flake input preferences stored here
├── flake.nix                   # Template flake (source of truth)
└── worktrees/                  # Isolated workspace environments
    ├── upstream/               # Uses upstream inputs
    │   ├── flake.nix          # Generated with upstream inputs
    │   └── ...                # Full nixcfg working tree
    ├── dev/                   # Uses all forks
    │   ├── flake.nix          # Generated with fork inputs
    │   └── ...
    └── nixpkgs-dev/           # Mixed: nixpkgs fork + upstream others
        ├── flake.nix          # Generated with mixed inputs
        └── ...
```

### **Git Config Schema**
```bash
# Default flake inputs (inherited by all workspaces)
git config workspace.flake.input.nixpkgs "github:NixOS/nixpkgs/nixos-unstable"
git config workspace.flake.input.home-manager "github:nix-community/home-manager"

# Workspace-specific overrides (stored in worktree config)
cd worktrees/dev
git config --worktree workspace.flake.input.nixpkgs "git+file:///home/tim/src/nixpkgs?ref=writers-auto-detection"
git config --worktree workspace.flake.input.home-manager "git+file:///home/tim/src/home-manager?ref=feature-test-with-fcitx5-fix"
```

## 🔍 **RESEARCH FOUNDATION**

**Location**: `~/src/git-worktree-superproject` (owned by user)
**Status**: Researched and analyzed (completed in previous session)

**Key Patterns Identified**:
- Git config-based repository specification system
- Per-workspace override mechanisms via worktree config
- Template and inheritance patterns for configuration
- Proven multi-workspace isolation architecture

## 🚀 **STRATEGIC IMPACT**

**Immediate Benefits**:
- Eliminate fork development blocking other nixcfg work
- Enable parallel upstream and fork development
- Version-controlled workspace configurations
- Reusable pattern for any Nix flake multi-repo development

**Innovation Opportunity**: Create industry-first integration of git worktrees with Nix flake input management

## 📚 **CONTEXT FILES TO REVIEW**

1. `~/src/git-worktree-superproject/workspace` - Base script to enhance
2. `~/src/git-worktree-superproject/README.md` - Architecture documentation  
3. `/home/tim/src/nixcfg/flake.nix` - Current flake structure to work with
4. `/home/tim/src/nixcfg/CLAUDE.md` - Updated project memory with design

## 🎯 **SUCCESS CRITERIA**

- [ ] Enhanced workspace script supports flake input detection and management
- [ ] Per-workspace flake input overrides work via git config
- [ ] nixcfg can be developed with parallel upstream/fork contexts
- [ ] All existing wt-super functionality remains intact
- [ ] Clean, documented, and reusable implementation

**Start with**: Begin implementing Nix flake detection in the workspace script at `~/src/git-worktree-superproject/workspace`.