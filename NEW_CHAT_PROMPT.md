# New Chat Session: Upgrade to Proper Nix Language AST Parsing

## 🎯 **MISSION STATEMENT**

Upgrade the enhanced git-worktree-superproject system from **text-processing approaches** to **proper Nix language AST parsing** for robust, production-grade flake input manipulation.

## 📊 **CURRENT STATUS: SUCCESSFUL PROOF-OF-CONCEPT**

### **✅ Working Implementation (Text-Processing Based)**
- **Location**: `/home/tim/src/nixcfg/workspace` and `/home/tim/src/git-worktree-superproject/workspace`
- **Success**: Industry-first git worktree + Nix flake integration achieved
- **Capability**: Per-workspace flake input overrides with automatic flake.nix generation

### **✅ Demonstrated Multi-Context Development**
```bash
# WORKING: Simple format input replacement
# Original flake.nix
nixpkgs.url = "git+file:///home/tim/src/nixpkgs?ref=writers-auto-detection"

# Generated upstream workspace flake.nix
nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable"

# Generated dev workspace flake.nix (unchanged)
nixpkgs.url = "git+file:///home/tim/src/nixpkgs?ref=writers-auto-detection"
```

### **❌ Current Limitation: Complex Format Handling**
```nix
# NOT WORKING: Complex format inputs remain unchanged
home-manager = {
  url = "git+file:///home/tim/src/home-manager?ref=feature-test-with-fcitx5-fix";
  inputs.nixpkgs.follows = "nixpkgs";
};
# Should become:
home-manager = {
  url = "github:nix-community/home-manager";  # <- URL not being replaced
  inputs.nixpkgs.follows = "nixpkgs";
};
```

## 🔬 **RESEARCH COMPLETED: NIX LANGUAGE PARSING TOOLS**

Based on comprehensive research conducted in previous session:

### **Primary Recommended Tools**

#### **1. rnix-parser (Rust - Most Mature)**
- **Repository**: `github.com/nix-community/rnix-parser`
- **Version**: 0.12.0 (January 2025) - actively maintained
- **Key Features**:
  - Complete Nix language parser with AST generation
  - 100% preserves original code structure (whitespace, comments)
  - Uses rowan crate for span-preserving parsing
  - Handles even invalid Nix code gracefully
  - Easy tree walking without recursion
- **Use Cases**: nixpkgs-fmt, identifier renaming, AST manipulation

#### **2. nixel (Rust/C++ - Performance-focused)**
- **Repository**: `github.com/kamadorueda/nixel`
- **Performance**: Parses all of Nixpkgs in under 25 seconds
- **Accuracy**: Copy-paste of original Nix lexer/parser
- **Features**: Comments, positions, automatic string unescaping

#### **3. Tree-sitter-nix (For Editor Integration)**
- **Repository**: `github.com/nix-community/tree-sitter-nix`
- **Used by**: canonix, format-nix formatters
- **Purpose**: Forgiving parser for syntax highlighting and editing

### **Language Servers & Formatters**
- **nixd**: Most advanced language server (2025)
- **alejandra**: "Semantically correct" Rust-based formatter
- **nixfmt**: Official standard formatter (Haskell)

### **Native Nix Commands for Input Management**
```bash
nix flake update nixpkgs                    # Update specific input
nix flake update --override-input nixpkgs github:NixOS/nixpkgs/staging
nix flake check                             # Validate after modifications
```

## 🎯 **IMMEDIATE PRIORITY TASKS**

### **Phase 1: Research & Tool Selection**
1. **Evaluate rnix-parser capabilities** for flake.nix AST manipulation
2. **Test structure preservation** with complex flake.nix modifications
3. **Compare performance** of rnix-parser vs nixel for our use case
4. **Design AST-based input replacement** strategy

### **Phase 2: Implementation Architecture**
1. **Replace Python/awk text processing** in `generate_workspace_flake()` function
2. **Implement proper AST parsing** with rnix-parser or similar
3. **Handle both simple and complex formats**:
   - Simple: `input.url = "url"`
   - Complex: `input = { url = "url"; ... }`
4. **Preserve all formatting and comments**

### **Phase 3: Integration & Testing**
1. **Integrate with native Nix tooling** (`nix flake update`, `nix flake check`)
2. **Test with complete nixcfg flake.nix** (all input formats)
3. **Validate workspace generation** for dev/upstream contexts
4. **Performance testing** with large flake files

### **Phase 4: Production Hardening**
1. **Error handling** for malformed flake.nix files
2. **Validation pipeline** integration
3. **Documentation** for AST-based approach
4. **Migration strategy** from text-processing implementation

## 🏗️ **TECHNICAL ARCHITECTURE GOALS**

### **Target Implementation Pattern**
```rust
// Conceptual approach using rnix-parser
use rnix::{Root, SyntaxNode};

fn modify_flake_inputs(source: &str, overrides: &HashMap<String, String>) -> Result<String> {
    let root = Root::parse(source);
    
    // 1. Parse AST while preserving structure
    // 2. Find inputs section
    // 3. Locate specific input nodes (both simple & complex formats)
    // 4. Replace URL values with overrides
    // 5. Generate modified flake.nix with preserved formatting
    
    Ok(modified_content)
}
```

### **Integration Points**
- **Current workspace script**: `/home/tim/src/nixcfg/workspace`
- **Function to replace**: `generate_workspace_flake()`
- **Configuration source**: Git config `workspace.flake.input.*` keys
- **Validation**: `nix flake check` after generation

## 📋 **VALIDATION CRITERIA**

### **Success Metrics**
1. **✅ Complex format handling**: `home-manager = { url = "..."; }` correctly replaced
2. **✅ Structure preservation**: Comments, whitespace, formatting unchanged
3. **✅ All input formats**: Both simple and complex patterns handled
4. **✅ Error tolerance**: Graceful handling of malformed Nix code
5. **✅ Performance**: Fast enough for interactive use
6. **✅ Integration**: Works with existing workspace configuration system

### **Test Cases**
- **nixcfg flake.nix**: Complex real-world flake with mixed input formats
- **Workspace generation**: dev (forks) vs upstream (github) contexts
- **Validation**: `nix flake check` passes after modification
- **Preservation**: Original structure, comments, formatting intact

## 🚀 **STRATEGIC IMPACT**

**Completion of this upgrade will deliver:**
- **Production-grade** Nix flake manipulation system
- **Complete coverage** of all flake input formats
- **Industry-leading** git worktree + Nix flake integration
- **Reusable foundation** for advanced Nix development workflows

## 📁 **KEY FILES & LOCATIONS**

### **Current Implementation**
- `/home/tim/src/nixcfg/workspace` - Working text-processing version
- `/home/tim/src/git-worktree-superproject/workspace` - Enhanced workspace script
- `/home/tim/src/nixcfg/flake.nix` - Source flake with mixed input formats

### **Generated Workspaces**
- `/home/tim/src/nixcfg/worktrees/dev/flake.nix` - Fork development context
- `/home/tim/src/nixcfg/worktrees/upstream/flake.nix` - Upstream development context

### **Configuration Storage**
- Git config: `workspace.flake.input.<name>.url` keys for overrides
- Priority: workspace-specific → default → original flake

## 🎯 **START HERE**

**Begin with**: Research and test rnix-parser capabilities for AST manipulation of the existing `/home/tim/src/nixcfg/flake.nix` file, focusing on preserving structure while modifying complex format inputs like `home-manager = { url = "..."; }`.

**Goal**: Replace the Python-based text processing in `generate_workspace_flake()` with robust AST-based Nix language manipulation.