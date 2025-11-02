# AST-Based Flake Input Modification for git-worktree-superproject - Integration Design

## Executive Summary

This document outlines the integration of surgical AST-based flake input modification into the existing git-worktree-superproject system. The goal is to replace sed-based text manipulation with precise AST modification while leveraging the already-implemented multi-context architecture.

## Problem Statement

### Current Implementation Limitation
The git-worktree-superproject already has comprehensive flake integration with:
- ✅ Git config-based input management (`workspace.flake.input.$input.url`)
- ✅ Workspace-specific input overrides and context switching
- ✅ Complete CLI interface for flake input management
- ❌ **Sed-based text manipulation** that lacks precision and structure preservation

### Core Challenge
Replace fragile sed-based flake modification with surgical AST-based modification while preserving the existing architecture and workflows.

### Integration Requirements
1. **Preserve Existing Architecture**: Maintain all current git-worktree-superproject functionality
2. **Replace sed with AST**: Surgical modification instead of text manipulation
3. **Perfect Structure Preservation**: Maintain all formatting, comments, and whitespace
4. **Backward Compatibility**: Existing workflows continue working unchanged
5. **Performance**: Fast modification without regression

## Current Architecture (Already Implemented)

### git-worktree-superproject Flake Integration
```
git-worktree-superproject (EXISTING)
├── Configuration Management
│   ├── workspace config set-flake-input <workspace> <input> <url>
│   ├── workspace config show-flake-inputs [workspace]
│   └── workspace config set-flake-input-default <input> <url>
├── Priority System (Source of Truth: Git Config)
│   ├── 1. Workspace-specific: workspace.flake.input.$input.url
│   ├── 2. Superproject default: workspace.flake.input.$input.url
│   └── 3. Original flake.nix (fallback)
├── Flake Generation (INTEGRATION POINT)
│   ├── generate_workspace_flake() function
│   ├── ❌ Current: sed-based text replacement
│   └── ✅ Target: AST-based surgical modification
└── Workflow Integration
    ├── Automatic flake.nix generation during workspace creation
    ├── Manual regeneration via regenerate-flake command
    └── Input override management per workspace
```

## Integration Design

### AST Modification Engine (Proven Component)
**Status**: ✅ Production-ready with comprehensive testing

**Current State**:
- **Language**: Rust with rnix-parser crate  
- **Location**: `/home/tim/src/nixcfg/rnix-test/`
- **Binary**: `flake-input-modifier`
- **API**: `modify_flake_input(flake_path, input_name, new_url)`

**Validated Capabilities**:
- ✅ Parse any valid flake.nix without syntax errors
- ✅ Locate input definitions in complex nested structures  
- ✅ Replace URLs with perfect whitespace/comment preservation
- ✅ Handle simple (`input.url = "..."`) and complex (`input = { url = "..."; }`) formats
- ✅ Sub-100ms performance for large flakes

**Test Coverage**: 41 comprehensive tests validating all real-world patterns

### Integration Point Analysis

#### Current sed-based Implementation (Lines 190-196 in workspace script)
```bash
# Extract and process inputs
while IFS= read -r input_line; do
    local input_name url_part
    read -r input_name url_part <<< "$input_line"
    
    local override_url
    override_url=$(get_flake_input_url "$input_name" "$workspace")
    
    if [[ -n "$override_url" ]]; then
        # ❌ FRAGILE: sed-based text replacement
        modified_content=$(echo "$modified_content" | sed -E "s|(^\s*$input_name\.url\s*=\s*\")[^\"]+(\";.*$)|\1$override_url\2|")
    fi
done < <(parse_flake_inputs "$source_flake")
```

#### Proposed AST-based Implementation
```bash
# Same input processing loop, but replace sed with AST modification
while IFS= read -r input_line; do
    local input_name url_part
    read -r input_name url_part <<< "$input_line"
    
    local override_url
    override_url=$(get_flake_input_url "$input_name" "$workspace")
    
    if [[ -n "$override_url" ]]; then
        # ✅ SURGICAL: AST-based modification
        if ! "$WORKSPACE_ROOT/rnix-test/target/release/flake-input-modifier" \
             "$target_flake" "$input_name" "$override_url"; then
            echo "Error: Failed to modify input '$input_name' in $target_flake" >&2
            return 1
        fi
    fi
done < <(parse_flake_inputs "$source_flake")
```

## Implementation Plan

### Phase 1: Binary Integration (Immediate)
1. **Copy AST binary**: Move `flake-input-modifier` to git-worktree-superproject
2. **Modify generate_workspace_flake()**: Replace sed with AST calls
3. **Add error handling**: Graceful fallback and error reporting
4. **Test integration**: Verify existing workflows continue working

### Phase 2: Optimization (Follow-up)
1. **Performance profiling**: Measure AST vs sed performance impact
2. **Binary location**: Determine optimal placement and distribution
3. **Caching**: Consider AST caching for repeated modifications
4. **Integration testing**: Comprehensive workflow validation

### Phase 3: Documentation and Distribution (Future)
1. **Document AST integration**: Update git-worktree-superproject docs
2. **Distribution strategy**: Package binary with git-worktree-superproject
3. **Upstream consideration**: Evaluate contribution to official project

## Current Status

### ✅ Proven Components
1. **AST Modification Engine**: Production-ready (41 comprehensive tests)
2. **git-worktree-superproject**: Extensive flake integration already implemented
3. **Configuration System**: Git config-based input management working
4. **CLI Interface**: Complete command set for flake input management

### ✅ Integration Ready
- **AST binary**: `flake-input-modifier` ready for integration
- **Target function**: `generate_workspace_flake()` identified for modification
- **Existing workflows**: All current functionality to be preserved
- **Test coverage**: Comprehensive validation of AST modification capabilities

## Simplified Design Decisions (User Feedback Applied)

### ✅ RESOLVED: Configuration Management
**Decision**: Git config (already implemented in git-worktree-superproject)
- Uses existing `workspace.flake.input.$input.url` pattern
- Leverages worktree-specific and superproject default configuration
- No additional configuration files needed

### ✅ RESOLVED: Context Inheritance  
**Decision**: No inheritance - keep it simple (user feedback)
- Workspace-specific input overrides only
- No complex inheritance patterns
- Simple and predictable behavior

### ✅ RESOLVED: Error Handling, Testing, UX
**Decision**: Leverage git-worktree-superproject patterns (user feedback)
- Follow existing error handling approaches
- Use established testing methodologies  
- Maintain consistent CLI patterns and documentation style

### ✅ RESOLVED: Performance Priority
**Decision**: Efficiency important but simplicity trumps performance (user feedback)
- Focus on reliable integration over optimization
- Acceptable performance already demonstrated (sub-100ms)
- Simplicity and correctness are higher priorities

## Integration Considerations

### Binary Distribution
- **Option 1**: Include binary in git-worktree-superproject repository
- **Option 2**: Build binary during installation/setup
- **Option 3**: Separate package with dependency management

### Fallback Strategy
- Graceful degradation to sed-based approach if AST binary unavailable
- Clear error reporting when AST modification fails
- Validation that output is syntactically correct

### Testing Integration
- Validate that all existing git-worktree-superproject workflows continue working
- Test AST modification with various flake structures
- Performance comparison between sed and AST approaches

## Next Steps (Revised Scope)

### Immediate Actions
1. **Complete AST integration** into git-worktree-superproject `generate_workspace_flake()`
2. **Test integration** with existing workflows to ensure backward compatibility
3. **Add error handling** and fallback mechanisms for robustness
4. **Document changes** for git-worktree-superproject users

### Success Criteria
- [ ] AST binary successfully replaces sed-based text manipulation
- [ ] All existing git-worktree-superproject flake workflows continue working
- [ ] Perfect structure preservation validated in real-world usage
- [ ] Performance comparable or better than sed-based approach
- [ ] Clear error reporting when AST modification fails

### Future Considerations
- **Binary distribution**: Determine best approach for packaging AST binary
- **Upstream contribution**: Evaluate contributing changes to official git-worktree-superproject
- **Additional features**: Only after integration is stable and well-tested

## Conclusion

This is an **integration project**, not a new system design. The goal is to enhance the existing, working git-worktree-superproject flake integration by replacing fragile sed-based text manipulation with surgical AST-based modification.

**Key Insight**: The architectural decisions have already been made and implemented. The focus should be on seamless integration that preserves all existing functionality while improving reliability and precision.

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