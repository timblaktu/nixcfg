# Multi-Context Nix Development System - Design Document

## Executive Summary

This document outlines the design of an AST-based multi-context Nix development system that enables seamless switching between local fork development and upstream package testing through surgical flake input modification and git worktree management.

## Problem Statement

### Core Challenge
Nix flake development with local forks creates friction:
- Manual flake.nix editing to switch between local forks and upstream packages
- Risk of accidentally committing local development paths
- Inability to test upstream compatibility without losing local development state
- No systematic way to manage multiple development contexts

### User Requirements
1. **Parallel Development**: Work on local forks while testing upstream compatibility
2. **Zero Manual Editing**: No manual flake.nix modifications
3. **Perfect Preservation**: Maintain all formatting, comments, and structure
4. **Context Isolation**: Clean separation between development contexts
5. **Instant Switching**: Fast context transitions without rebuild delays

## System Architecture

### Component Overview
```
nixcfg Multi-Context System
├── AST Modification Engine (rnix-test/)
│   ├── flake-input-modifier (Rust binary)
│   ├── rnix-parser integration
│   └── Comprehensive test suite (41 tests)
├── Workspace Management (workspace script)
│   ├── Enhanced git-worktree-superproject
│   ├── Context configuration system
│   └── AST engine integration
└── Context Definitions
    ├── Git config storage (workspace.flake.context.*)
    ├── Per-context input specifications
    └── Inheritance and override system
```

### Core Components

#### 1. AST Modification Engine
**Purpose**: Surgical modification of Nix flake inputs with perfect structure preservation

**Implementation**:
- **Language**: Rust with rnix-parser crate
- **Location**: `/home/tim/src/nixcfg/rnix-test/`
- **Binary**: `flake-input-modifier`
- **Core Function**: `modify_flake_input(flake_path, input_name, new_url)`

**Capabilities**:
- Parse any valid flake.nix without syntax errors
- Locate specific input definitions in complex nested structures
- Replace URLs while preserving all whitespace, comments, and formatting
- Handle both simple (`input.url = "..."`) and complex (`input = { url = "..."; }`) formats
- Validate modifications before writing changes

**Test Coverage**: 41 comprehensive tests covering:
- Basic and advanced flake patterns
- Real-world complex structures (flake-parts, nested flakes)
- Edge cases (Git+SSH, submodules, follows chains)
- Performance validation (sub-100ms for large flakes)

#### 2. Workspace Management System
**Purpose**: Git worktree management with flake context integration

**Implementation**:
- **Base**: Enhanced git-worktree-superproject pattern
- **Location**: `/home/tim/src/nixcfg/workspace` script
- **Integration**: Calls AST modification engine for input changes

**Key Functions**:
- `workspace flake context define <name> [input=url ...]` - Define context
- `workspace flake context <name>` - Switch to context
- `workspace flake context list` - Show available contexts
- `workspace flake context current` - Show active context

**Worktree Management**:
- Creates dedicated worktrees for each context (`worktrees/<context>/`)
- Each worktree has appropriate branch name (`workspace/<context>`)
- Automatic flake.nix modification during context creation
- Git config storage for context persistence

#### 3. Context Configuration System
**Purpose**: Persistent storage and management of input specifications

**Storage**: Git configuration system
```
workspace.flake.context.upstream.nixpkgs = github:NixOS/nixpkgs/nixos-unstable
workspace.flake.context.upstream.home-manager = github:nix-community/home-manager
workspace.flake.context.dev.nixpkgs = git+file:///home/tim/src/nixpkgs?ref=writers-auto-detection
workspace.flake.context.dev.home-manager = git+file:///home/tim/src/home-manager?ref=auto-validate-feature
```

**Features**:
- Per-context input URL specifications
- Inheritance from base context (TBD)
- Override system for partial context switching (TBD)
- Version controlled context definitions (via git config)

## Current Implementation Status

### ✅ Completed Components
1. **AST Modification Engine**: Production-ready with comprehensive testing
2. **Basic Workspace Integration**: Working context switching
3. **Live Validation**: Successfully deployed in nixcfg project
4. **Real-world Testing**: Handles complex flake structures correctly

### ✅ Validated Workflows
1. **Context Creation**: Define upstream and dev contexts
2. **Context Switching**: Switch from dev (local forks) to upstream
3. **AST Precision**: Perfect structure preservation confirmed
4. **Flake Evaluation**: Modified flakes evaluate correctly

### 🔧 Current Deployment
- **Main Development**: `/home/tim/src/nixcfg/` (dev branch, fork inputs)
- **Upstream Testing**: `/home/tim/src/nixcfg/worktrees/upstream/` (upstream inputs)
- **Working Features**: Context switching, AST modification, worktree management

## Outstanding Design Decisions

### 1. Context Configuration Management

**Question**: How should users define and manage contexts?

**Options**:
A. **Git Config Only** (Current)
   - Pros: Version controlled, simple storage
   - Cons: Not user-friendly for complex configurations

B. **YAML/TOML Configuration Files**
   - Pros: Better syntax, easier editing, comments
   - Cons: Additional file management, parsing complexity

C. **Nix-based Configuration**
   - Pros: Native Nix syntax, type checking
   - Cons: Evaluation complexity, circular dependencies

**Recommendation**: Start with git config, add YAML option later

### 2. Context Inheritance Strategy

**Question**: How should contexts inherit and override input specifications?

**Options**:
A. **No Inheritance** (Current)
   - Each context specifies all inputs explicitly
   - Simple but verbose

B. **Base Context Inheritance**
   - Define base context, others inherit and override
   - More complex but reduces duplication

C. **Layered Context System**
   - Multiple inheritance layers (base → team → personal)
   - Maximum flexibility but complexity

**Recommendation**: Implement base inheritance as next step

### 3. Error Handling and Recovery

**Question**: How should the system handle modification failures?

**Current State**: Basic error reporting, no automatic recovery

**Required Decisions**:
- Automatic backup and rollback strategy
- Validation before and after modifications
- User notification and intervention points
- Integration with git worktree cleanup

### 4. Integration Testing Strategy

**Question**: How should we test the complete workflow?

**Options**:
A. **Manual Testing Only** (Current)
   - Simple but not scalable

B. **Automated Integration Tests**
   - Test context switching end-to-end
   - Validate flake evaluation after modification
   - Check git worktree state consistency

C. **Property-Based Testing**
   - Generate random contexts and test invariants
   - Comprehensive but complex

**Recommendation**: Implement basic automated integration tests

### 5. User Experience and Documentation

**Question**: What level of user-friendliness should we target?

**Current State**: Working prototype, minimal documentation

**Required Decisions**:
- Command-line interface design
- Error message quality and helpfulness
- Documentation depth and examples
- Integration with existing Nix workflows

### 6. Performance and Scalability

**Question**: How should the system handle large flakes and many contexts?

**Current Performance**: Sub-100ms for complex flakes

**Considerations**:
- Caching of parsed AST structures
- Incremental updates vs full regeneration
- Context switching performance with many worktrees
- Disk usage with multiple worktrees

## Implementation Roadmap

### Phase 1: Design Finalization (Next 2-3 Sessions)
1. **Create comprehensive design document** (This document)
2. **Review design decisions with user**
3. **Finalize architecture and configuration approach**
4. **Document user workflows and error handling**

### Phase 2: Polish and Documentation (2-3 Sessions)
1. **Implement chosen configuration management approach**
2. **Add comprehensive error handling and recovery**
3. **Create user documentation and examples**
4. **Implement integration testing framework**

### Phase 3: Advanced Features (Future)
1. **Context inheritance system**
2. **Performance optimizations**
3. **Integration with other Nix tools**
4. **Community packaging and distribution**

## Risk Assessment

### Technical Risks
1. **AST Parser Changes**: rnix-parser updates could break compatibility
   - Mitigation: Pin versions, comprehensive test suite
2. **Flake Format Evolution**: Nix flake syntax changes
   - Mitigation: Monitor Nix development, update parsers
3. **Git Worktree Limitations**: Complex git states
   - Mitigation: Robust cleanup, state validation

### User Experience Risks
1. **Complexity**: System too complex for daily use
   - Mitigation: Simple defaults, clear documentation
2. **Reliability**: Context switching failures
   - Mitigation: Backup/rollback, extensive testing
3. **Performance**: Slow context switching
   - Mitigation: Performance testing, optimization

## Success Metrics

### Technical Metrics
- [ ] Zero flake parsing errors across test suite
- [ ] Sub-100ms context switching performance
- [ ] 100% structure preservation validation
- [ ] Zero data loss during context switching

### User Experience Metrics
- [ ] Single command context switching
- [ ] Clear error messages with recovery suggestions
- [ ] Comprehensive documentation with examples
- [ ] Integration with existing Nix workflows

## Next Steps

1. **Review this design document** with user to validate approach
2. **Make final decisions** on outstanding configuration questions
3. **Create detailed implementation plan** for chosen approach
4. **Begin systematic implementation** of polish and documentation
5. **Only then proceed** to deployment and advanced features

## Appendix: Technical Specifications

### AST Modification API
```rust
// Core modification function
pub fn modify_flake_input(
    flake_path: &Path,
    input_name: &str, 
    new_url: &str
) -> Result<(), ModificationError>

// Supporting functions
pub fn find_url_string_path(root: &SyntaxNode, input_name: &str) -> Option<TextRange>
pub fn reconstruct_with_replacement(root: &SyntaxNode, range: TextRange, new_url: &str) -> String
```

### Workspace Script Interface
```bash
# Context management
workspace flake context define <name> [input=url ...]
workspace flake context <name>
workspace flake context list
workspace flake context current

# Legacy git-worktree-superproject commands (unchanged)
workspace repo add <url> [name]
workspace checkout <name> [branch]
```

### Git Configuration Schema
```
workspace.flake.context.<context>.<input> = <url>
workspace.flake.context.<context>.inherit = <base-context>
workspace.flake.active-context = <current-context>
```