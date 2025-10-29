# Unified Home Files Module - Comprehensive Design Document

## Executive Summary

This document outlines the consolidation of `home/modules/files` and `home/modules/validated-scripts` into a single, comprehensive `home/files` module that provides validated file management for any file type, not just scripts. The unified module will maintain all existing functionality while eliminating coordination overhead and providing a more extensible architecture.

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

## Unified Architecture Design

### Module Structure
```
home/files/
├── default.nix              # Main module entry point
├── README.md                # This document
├── lib/
│   ├── file-validators.nix   # Validation functions by file type
│   ├── completion-generators.nix  # Shell completion generators
│   ├── test-frameworks.nix  # Testing framework
│   └── writers.nix          # File generation utilities
├── types/
│   ├── scripts.nix          # Script-specific validation (bash, python, etc.)
│   ├── configs.nix          # Configuration file validation
│   ├── data.nix             # Data file validation (JSON, YAML, etc.)
│   └── assets.nix           # Asset file handling (images, docs, etc.)
└── content/                 # Actual file content (replaces current bin/, lib/, etc.)
    ├── scripts/
    ├── configs/
    ├── data/
    └── assets/
```

### Core Concepts

#### 1. Validated File Types
Extend beyond scripts to support any file type:
- **Scripts**: bash, python, powershell, etc. (current functionality)
- **Configuration Files**: JSON, YAML, TOML, INI with schema validation
- **Data Files**: CSV, XML with format validation
- **Assets**: Images, documents with integrity checks
- **Static Files**: Direct file copying (current files module behavior)

#### 2. Universal File Definition Schema
```nix
mkValidatedFile = {
  name,                    # File name
  type,                    # File type (script, config, data, asset, static)
  lang ? null,             # Language/format (bash, json, yaml, etc.)
  content ? null,          # Inline content
  source ? null,           # Source file path
  target,                  # Target path in home directory
  executable ? false,      # Whether file should be executable
  deps ? [],              # Dependencies (packages, libraries)
  schema ? null,          # Validation schema
  tests ? {},             # Custom tests
  generateCompletions ? false,  # Generate shell completions
  extraChecks ? [],       # Additional validation checks
  metadata ? {}           # Custom metadata
}
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

### Phase 1: Foundation (Immediate)
1. **Create unified module structure**
   - New `home/files/default.nix` with modular imports
   - Move existing functionality into type-specific modules
   - Preserve all current behavior

2. **Implement core file definition system**
   - Universal `mkValidatedFile` function
   - Type registry and dispatcher
   - Backward compatibility layer

3. **Migrate existing scripts**
   - Convert all validated-scripts definitions to new format
   - Ensure identical output and functionality
   - Remove hardcoded exclusion lists

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

## Benefits

### Immediate Benefits
- **Elimination of coordination overhead** between modules
- **Dynamic script discovery** replaces hardcoded exclusion lists
- **Unified testing and validation** across all file types
- **Consistent API** for all home directory file management

### Long-term Benefits
- **Extensible architecture** for new file types
- **Enhanced validation capabilities** beyond scripts
- **Better development workflow** with unified tooling
- **Reduced complexity** through single responsibility

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
