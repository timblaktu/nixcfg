# Unified Home Files Module - Comprehensive Design Document

## Executive Summary

**REVISED APPROACH**: This document outlines a **hybrid unified files module** that leverages nixpkgs `autoWriter` as the foundation while preserving unique high-value components from `validated-scripts`. Analysis revealed that nixpkgs `autoWriter` provides 90% of the proposed functionality out-of-the-box, enabling a **70% code reduction** while maintaining all unique capabilities.

**Key Strategy**: Build a thin integration layer around `autoWriter` + retain script library system, enhanced testing, and domain-specific generators that provide genuine value beyond autoWriter's scope.

## Current State Analysis

### Existing Modules
1. **home/modules/files/default.nix** (422 lines)
   - Simple file copying from `home/files/` to `~/`
   - Auto-generated shell completions for scripts
   - Hardcoded exclusion list for validated scripts

2. **home/modules/validated-scripts/** (2700+ lines across multiple files)
   - Type-safe script generation with nix-writers
   - Validation and testing framework
   - Library dependency injection
   - Language-specific handlers (bash, python, powershell)

### Coordination Issues
- Hardcoded `validatedScriptNames` list requires manual maintenance
- Duplicate completion generation logic
- Split responsibility for script management
- No validation for non-script files

## Hybrid Architecture Design (REVISED)

### Module Structure
```
home/files/
├── default.nix              # Main module entry point - thin wrapper around autoWriter
├── README.md                # This document
├── lib/
│   ├── autowriter-helpers.nix  # Extensions to nixpkgs autoWriter
│   ├── script-libraries.nix    # Non-executable script library system  
│   ├── enhanced-testing.nix    # Testing beyond autoWriter validation
│   ├── domain-generators.nix   # Claude wrappers, tmux helpers, etc.
│   └── config-validation.nix   # Schema validation for JSON/YAML/TOML
└── content/                 # Actual file content (replaces current bin/, lib/, etc.)
    ├── scripts/             # Auto-detected via autoWriter
    ├── libraries/           # Non-executable, for sourcing
    ├── configs/             # JSON/YAML with schema validation
    └── assets/              # Static files
```

**Key Change**: Eliminated custom file type detection, writer dispatch, and validation logic - **nixpkgs autoWriter handles this better**.

### Core Concepts

#### 1. Validated File Types
Extend beyond scripts to support any file type:
- **Scripts**: bash, python, powershell, etc. (current functionality)
- **Configuration Files**: JSON, YAML, TOML, INI with schema validation
- **Data Files**: CSV, XML with format validation
- **Assets**: Images, documents with integrity checks
- **Static Files**: Direct file copying (current files module behavior)

#### 2. Hybrid File Definition Schema (REVISED)
```nix
# For scripts - leverage autoWriter directly
mkScript = {
  target,                  # Target path in home directory  
  content ? null,          # Inline content
  source ? null,           # Source file path
  deps ? [],              # Dependencies
  tests ? {},             # Enhanced tests beyond autoWriter
  options ? {}            # Writer-specific options
}:
pkgs.writers.autoWriter {
  path = target;
  content = if source != null then builtins.readFile source else content;
  inherit deps options;
} // { passthru = { inherit tests; }; };

# For script libraries - unique to our system
mkScriptLibrary = {
  name,
  content ? null,
  source ? null,
  deps ? [],
  tests ? {}
}:
pkgs.writeText name (if source != null then builtins.readFile source else content);

# For configs - extend autoWriter with schema validation
mkConfig = {
  target,
  content,
  schema ? null,
  tests ? {}
}:
let validated = if schema != null then validateSchema schema content else content;
in (detectConfigWriter target).generate target validated;
```

#### 3. Type-Specific Validators
Each file type gets its own validation logic:
```nix
validators = {
  script = { lang, content, deps, ... }: 
    # Use nix-writers for syntax validation
    # Dependency injection for libraries
    # Automatic test generation
  
  config = { lang, content, schema, ... }:
    # JSON/YAML schema validation
    # Format-specific linting
    # Configuration drift detection
  
  data = { lang, content, schema, ... }:
    # Data format validation
    # Referential integrity checks
    # Size and performance constraints
  
  asset = { content, metadata, ... }:
    # File integrity verification
    # Metadata extraction and validation
    # Compression optimization
  
  static = { source, target, ... }:
    # Simple file copying (current behavior)
    # Permission handling
    # Symlink resolution
};
```

## Implementation Strategy

### Phase 1: Foundation (Immediate) - REVISED
1. **Create hybrid module structure**
   - New `home/files/default.nix` as thin wrapper around autoWriter
   - Preserve script library system from validated-scripts
   - Preserve enhanced testing framework
   - Preserve domain-specific generators

2. **Implement autoWriter integration**
   - Replace `mkValidatedScript` with `autoWriter` calls
   - Migrate all scripts to use auto-detection
   - Eliminate manual language specification
   - Maintain all current script functionality

3. **Preserve unique components**
   - Keep `mkScriptLibrary` for non-executable scripts
   - Keep cross-reference library injection pattern
   - Keep enhanced testing beyond syntax validation
   - Keep Claude wrapper and domain-specific generators

### Phase 2: Enhancement (Next Sprint)
1. **Add configuration file support**
   - JSON/YAML schema validation
   - Configuration template generation
   - Environment-specific config handling

2. **Implement data file validation**
   - CSV/XML format checking
   - Data quality constraints
   - Automated data pipeline tests

3. **Enhanced testing framework**
   - Type-specific test generators
   - Integration test support
   - Performance benchmarking

### Phase 3: Optimization (Future)
1. **Advanced shell completions**
   - Dynamic completion based on file content
   - Context-aware suggestions
   - Multi-language completion support

2. **File relationship management**
   - Dependency tracking between files
   - Automatic regeneration on changes
   - Conflict detection and resolution

3. **Development workflow integration**
   - File watching and auto-validation
   - IDE integration hooks
   - Continuous validation in development

## Migration Plan

### Breaking Changes
- **Module Import Path**: `home/modules/validated-scripts` → `home/files`
- **Configuration Options**: `validatedScripts.*` → `homeFiles.*`
- **Function Names**: `mkValidatedScript` → `mkValidatedFile`

### Compatibility Strategy
1. **Deprecation Period**: Keep old module as deprecated wrapper
2. **Automatic Migration**: Provide script to convert existing configurations
3. **Documentation**: Clear migration guide with examples

### Migration Steps
1. Create new unified module alongside existing modules
2. Add compatibility layer in old modules pointing to new module
3. Update all configurations to use new module
4. Remove old modules after verification
5. Update documentation and examples

## Benefits (REVISED)

### Immediate Benefits
- **70% code reduction** (2700 → 800 lines) by leveraging autoWriter
- **Mature file type detection** from nixpkgs instead of custom implementation
- **Upstream maintenance** of core writer functionality
- **Elimination of coordination overhead** between modules
- **Preservation of all unique value** (libraries, enhanced testing, generators)

### Long-term Benefits
- **Future compatibility** with nixpkgs writer improvements
- **Community contributions** flow upstream to file detection
- **Reduced maintenance burden** - focus on unique functionality
- **Better performance** from optimized nixpkgs implementations
- **Strategic value preservation** while eliminating redundant code

## Configuration Examples

### Migrated Script (Backward Compatible)
```nix
homeFiles.scripts.tmux-session-picker = {
  type = "script";
  lang = "bash";
  source = ./content/scripts/tmux-session-picker.sh;
  deps = [ tmuxPlugins.resurrect ];
  libraries = [ terminalUtils colorUtils ];
  generateCompletions = true;
  tests = {
    syntax = "echo 'Syntax validation passed'";
    integration = "./test-tmux-integration.sh";
  };
};
```

### New Configuration File Support
```nix
homeFiles.configs.vscode-settings = {
  type = "config";
  lang = "json";
  target = ".config/Code/User/settings.json";
  content = {
    "editor.fontSize" = 14;
    "workbench.colorTheme" = "Dark+";
  };
  schema = ./schemas/vscode-settings.json;
  tests = {
    validation = "jq empty"; # JSON validation
  };
};
```

### Data File with Validation
```nix
homeFiles.data.bookmarks = {
  type = "data";
  lang = "yaml";
  target = ".config/browser/bookmarks.yml";
  source = ./content/data/bookmarks.yml;
  schema = ./schemas/bookmarks-schema.yml;
  tests = {
    linkValidation = "./scripts/validate-bookmark-links.sh";
  };
};
```

## Implementation Timeline

### Week 1: Foundation
- [ ] Create new module structure
- [ ] Implement core mkValidatedFile function
- [ ] Add type registry and dispatching
- [ ] Create compatibility layer

### Week 2: Migration
- [ ] Migrate all existing scripts to new format
- [ ] Update all references and imports
- [ ] Verify identical functionality
- [ ] Update documentation

### Week 3: Enhancement
- [ ] Add configuration file support
- [ ] Implement enhanced completions
- [ ] Add data file validation
- [ ] Performance optimization

### Week 4: Finalization
- [ ] Remove deprecated modules
- [ ] Complete test coverage
- [ ] Update examples and documentation
- [ ] Production deployment

## Success Criteria

1. **Functional Equivalence**: All existing functionality preserved
2. **Zero Coordination Overhead**: No hardcoded cross-module dependencies
3. **Extensibility**: Easy addition of new file types
4. **Performance**: No degradation in build or runtime performance
5. **Developer Experience**: Improved API consistency and documentation

## Risk Mitigation

### Technical Risks
- **Complex Migration**: Staged rollout with compatibility layer
- **Performance Impact**: Benchmarking at each phase
- **Regression Risk**: Comprehensive test coverage

### Operational Risks
- **User Disruption**: Clear communication and migration tools
- **Documentation Lag**: Parallel documentation updates
- **Support Burden**: Maintain old module during transition

## Conclusion

The unified home/files module represents a natural evolution of the existing architecture, eliminating artificial boundaries while preserving all current functionality. The modular design enables future extension to any file type while maintaining the validation and testing capabilities that make the current system robust.

This consolidation aligns with the principle of cohesive responsibility - all home directory file management under a single, well-designed module with clear extension points for future growth.
