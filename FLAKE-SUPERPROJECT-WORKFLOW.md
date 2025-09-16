# Flake Superproject Development Workflow

This document describes development workflows for the nixcfg superproject, which manages multiple flake inputs that may need fixes during development.

## Overview

The nixcfg repository is a "superproject" that coordinates multiple flake inputs. When encountering build errors requiring fixes in flake input repositories, two workflows are available:

1. **Basic URL Switching Workflow** - Simple manual approach for occasional fixes
2. **Git Worktree Workflow** - Advanced automation for frequent multi-repository development

## Basic URL Switching Workflow (Recommended for Simple Fixes)

This workflow maintains Nix purity by keeping literal URLs in flake.nix while providing a systematic approach to fixing input issues.

### Core Principle: Maintain Literal URLs

The flake.nix file must always contain literal URL strings (no template variables) to maintain Nix evaluation purity.

### Quick Reference Process

1. **Fork & Clone** - Ensure you own forks of problematic inputs
2. **Create Branch** - Make feature branch in local input repository  
3. **Update URL** - Change flake.nix to point to local development path
4. **Develop & Test** - Iterate changes and test with superproject
5. **Merge & Push** - Squash merge to fork, push to remote
6. **Restore URL** - Update flake.nix to point to updated remote fork
7. **Final Validation** - Confirm fixes work with remote URLs

### Detailed Steps

**Step 1: Local Development Setup**
```bash
# Create fork if needed
gh repo fork nix-community/home-manager --remote --clone
cd ~/src/home-manager
git checkout -b fix-specific-issue
```

**Step 2: Redirect flake.nix to Local Path**
```nix
# Change from:
home-manager.url = "github:nix-community/home-manager";

# To:
home-manager.url = "git+file:///home/tim/src/home-manager?ref=fix-specific-issue";
```

**Step 3: Develop and Test Changes**
```bash
# Make changes, commit, test repeatedly
cd ~/src/home-manager
# Edit files...
git add . && git commit -m "Fix issue"
cd ~/src/nixcfg
nix flake lock --update-input home-manager
sudo nixos-rebuild switch --flake '.#thinky-nixos'
```

**Step 4: Finalize and Push**
```bash
cd ~/src/home-manager
git checkout master
git merge --squash fix-specific-issue
git commit -m "Fix issue with detailed explanation"
git push fork master
```

**Step 5: Update flake.nix to Remote**
```nix
# Change back to:
home-manager.url = "github:timblaktu/home-manager";
```

### When to Use This Workflow
- Occasional input fixes (< once per week)
- Single repository issues
- Simple bug fixes or compatibility updates
- Learning the flake input development process

## Git Worktree Workflow (Recommended for Frequent Multi-Repository Development)

### Overview

For frequent multi-repository development, a git worktree-based approach eliminates the friction of manual URL switching through automated AST-based flake.nix manipulation.

### Core Design Principles

1. **flake.nix Always Contains Literal URLs** - No template variables or environment interpolation
2. **AST-Based Manipulation** - Use rnix-parser to safely modify input URLs
3. **Git Metadata Storage** - Store workspace configurations in git config
4. **Workspace Isolation** - Each workspace maintains independent repository states
5. **Import/Export API** - Convert existing flake.nix to workspace management

### Pain Points Addressed

- **URL Switching Overhead** - Eliminated through automation
- **Lock File Churn** - Reduced through predictable workspace paths
- **Development Isolation** - Achieved through git worktrees
- **Parallel Development** - Multiple workspaces support concurrent features

### Architecture

```
nixcfg/
├── workspace                    # Worktree management script
├── flake.nix                   # Always valid - literal URLs only
├── .workspace/
│   ├── config                  # Workspace metadata (git config format)
│   └── templates/              # Import templates for different formats
├── repos/                      # Bare repository cache
│   ├── home-manager.git/
│   └── nixos-wsl.git/
└── worktrees/                  # Development workspaces
    ├── main/
    │   ├── home-manager/       # Worktree tracking main branch
    │   └── nixos-wsl/         # Worktree tracking main branch
    └── feature-auth/
        ├── home-manager/       # Worktree on feature branch
        └── nixos-wsl/         # Worktree tracking main branch
```

### Implementation Approach

**Phase 1: Setup and Import**
```bash
./workspace init                    # Initialize workspace system
./workspace import flake.nix        # Import existing configuration
./workspace switch main             # Create main workspace
```

**Phase 2: Feature Development**
```bash
./workspace switch feature-auth     # Create feature workspace
./workspace config set home-manager feature-auth-fixes
./workspace sync                    # Updates flake.nix via AST manipulation
nix develop                         # Uses correct branches per workspace
```

**Phase 3: Integration**
```bash
cd worktrees/feature-auth/home-manager
git push origin feature-auth-fixes
./workspace switch main             # Switch back to main
./workspace sync                    # Updates flake.nix to main branches
./workspace update                  # Pulls latest changes
```

### When to Use This Workflow
- Frequent multi-repository development (> once per week)
- Parallel feature development across inputs
- Complex dependency management scenarios
- Teams needing shared workspace configurations

## Technical Implementation Research

### Flake Input URL Specification Methods

Based on 2025 Nix documentation, flake inputs support multiple URL specification formats. **The workspace tool should leverage standard Nix parsing and validation mechanisms rather than implementing custom URL parsing**:

#### 1. Direct URL Formats
- **GitHub**: `github:NixOS/nixpkgs`, `github:NixOS/nixpkgs/nixos-20.09`
- **Git**: `git+https://github.com/NixOS/patchelf`, `git+ssh://git@github.com/user/repo.git`
- **Local**: `path:/path/to/repo`, `git+file:///absolute/path`
- **Archives**: `https://github.com/user/repo/archive/master.tar.gz`

#### 2. External Configuration Methods
- **Registry System**: Flake registries for symbolic identifiers (see detailed analysis below)
- **Import from Files**: Using `import ./inputs.nix` patterns
- **nixConfig**: Flake-specific Nix configuration overrides
- **Relative Paths**: Nix 2.26+ supports relative flake references

#### 3. CLI Override Methods
- **--override-input**: Override specific inputs (implies --no-write-lock-file)
- **--override-flake**: Registry redirection at command level
- **--redirect**: Store path redirection (different from input URL changes)

#### 4. Standard Nix Validation Integration
**Recommendation**: Use Nix's built-in flake URL validation through:
- **`nix flake info`**: Validates and resolves flake URLs
- **`nix flake check`**: Schema validation against flake outputs
- **Flake checker tools**: Third-party tools like DeterminateSystems' flake-checker
- **Registry resolution**: Automatic URL resolution through registry system

This approach ensures the workspace tool stays compatible with Nix URL specification changes without requiring custom parsing logic.

### Flake Registries: Deep Dive and Impact Analysis

#### What Are Flake Registries?

Flake registries are a convenience system that maps symbolic identifiers (like `nixpkgs`) to full flake URLs (like `github:NixOS/nixpkgs`). They operate as a hierarchical lookup system with three levels:

1. **Global Registry**: Downloaded from NixOS/flake-registry, cached locally, auto-updated
2. **System Registry**: Per-NixOS system configuration 
3. **User Registry**: `~/.config/nix/registry.json`, managed via `nix registry` commands

#### Registry Format and Resolution

Registries use JSON format mapping indirect references to concrete URLs:
```json
{
  "version": 2,
  "flakes": [
    {
      "from": { "type": "indirect", "id": "nixpkgs" },
      "to": { "type": "github", "owner": "NixOS", "repo": "nixpkgs" }
    }
  ]
}
```

#### Critical Impact on Workspace Management (2025 Update)

**Major Change**: Registry usage in flake.nix inputs is being **deprecated in 2025**:
- **Reason**: User confusion from inconsistent resolution based on local registry state
- **Impact**: `inputs.nixpkgs.url = "nixpkgs"` will be discouraged in favor of explicit URLs
- **Timeline**: Progressive deprecation over coming months
- **Command-line**: Registry shortcuts (`nix run nixpkgs#hello`) remain supported

#### Implications for Workspace Tool Design

1. **Avoid Registry Dependencies**: The workspace tool should manipulate explicit URLs, not registry references
2. **Lock File Clarity**: Registry-free flake.nix files produce more predictable lock files
3. **Reproducibility**: Eliminates hidden dependencies on local registry state
4. **URL Canonicalization**: Tool should convert registry references to explicit URLs during workspace operations

#### Registry Integration Strategy

- **Input Processing**: Resolve any registry references to explicit URLs before workspace management
- **URL Validation**: Use `nix flake info` to validate and canonicalize URLs
- **CLI Bridge**: Leverage registry for user convenience in workspace commands (`workspace add nixpkgs`)
- **Lock File Impact**: Ensure registry-independent lock file generation

This registry evolution aligns with the workspace tool's goal of maintaining explicit, deterministic flake input management.

### AST Manipulation Tool Analysis

#### nixfmt Capabilities
**Research Finding**: nixfmt is primarily a formatter, not a selective modification tool.

- **Purpose**: Official Nix code formatter maintaining consistent style
- **Approach**: Parses entire file, discards formatting, regenerates with standard rules
- **Limitation**: No selective modification - only whole-file reformatting
- **Architecture**: Haskell-based, designed for zero-configuration formatting

**Conclusion**: nixfmt is unsuitable for selective URL modification - it's a formatter, not an editor.

#### rnix-parser Capabilities
**Research Finding**: rnix-parser provides excellent foundation for non-destructive AST manipulation.

- **Lossless Parsing**: "Printing out the AST prints out 100% the original code" - preserves ALL syntax including whitespace/comments
- **Complete Preservation**: Even completely invalid Nix code remains intact after parsing
- **Error Handling**: Marks erroneous nodes without losing original structure  
- **Tree Walking**: Easy traversal without recursion using rowan crate architecture
- **Rust-based**: Modern, performant implementation with span information
- **Use Cases**: Formatters, linters, refactoring tools, identifier renaming
- **Debugging**: nix-explorer tool demonstrates AST preservation in practice

**Critical Capability for Workspace Tool**: rnix-parser's design philosophy ensures that:
1. **File Structure Preservation**: Original directory/file structure maintained
2. **Formatting Retention**: Indentation, spacing, comments preserved exactly
3. **Minimal Modification**: Only targeted URL strings change, everything else untouched
4. **Error Safety**: Syntax errors don't prevent parsing or preservation
5. **Span Tracking**: Byte-level position information for precise modifications

**Implementation Strategy**: rnix-parser is specifically designed for the workspace tool's use case - selective URL modifications while preserving complete file structure and formatting, equivalent to a surgical `sed -i` operation but with full Nix syntax awareness.

#### AST-Based Implementation Approach

```rust
// Conceptual approach using rnix-parser
1. Parse flake.nix with rnix-parser
2. Walk AST to find input attribute sets
3. Modify specific url attributes
4. Serialize back to original file structure
5. Validate syntax before writing
```

### Implementation Considerations by URL Method

#### Direct URLs in flake.nix
- **Simple Case**: Direct string replacement in AST
- **AST Target**: Look for `url = "...";` patterns
- **Validation**: Ensure URL format correctness

#### Imported Configurations
- **Complex Case**: May require parsing multiple files
- **AST Challenge**: Following import paths and modifying imported content
- **Strategy**: Support common patterns, document limitations

#### Registry Overrides
- **Alternative Approach**: Use CLI overrides instead of file modification
- **Implementation**: Generate --override-input flags for workspace commands
- **Benefit**: No file modification required

### Recommended Implementation Strategy

1. **Start Simple**: Focus on direct URL patterns in flake.nix
2. **Use rnix-parser**: Rust-based AST manipulation with guaranteed formatting preservation
3. **Leverage Standard Nix Tools**: Use `nix flake info` for URL validation and canonicalization
4. **Registry-Aware Processing**: Convert indirect registry references to explicit URLs before manipulation
5. **Validate Changes**: Ensure syntax correctness with `nix flake check` after modifications
6. **Support Common Patterns**: Handle 80% of use cases initially, document limitations clearly
7. **CLI Fallback Strategy**: Use `--override-input` for complex cases or unsupported patterns

**Key Advantages of This Approach**:
- **Non-Destructive**: rnix-parser's 100% preservation guarantee ensures workspace operations are safe
- **Future-Proof**: Relying on standard Nix tooling for URL validation adapts to Nix specification changes
- **Registry Compatible**: Handles 2025 registry deprecation gracefully by canonicalizing URLs
- **Practical**: Balances implementation complexity with utility while maintaining Nix purity constraints

This strategy positions the workspace tool as a reliable, surgical manipulation system that enhances the development workflow without compromising code integrity or reproducibility.