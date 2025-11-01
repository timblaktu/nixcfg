# New Chat Session: Implement Selective Tree Reconstruction Using Green Node Copying

## 🎯 **MISSION STATEMENT**

Build upon the major breakthrough in understanding string literal token structure to implement selective tree reconstruction that can copy unchanged portions and rebuild only modified nodes using GreenNodeBuilder.

## ✅ **MAJOR BREAKTHROUGH ACHIEVED**

### **String Literal Token Structure - DISCOVERED**
- **✅ Complete token breakdown**: String literals = `NODE_STRING` containing:
  - `TOKEN_STRING_START` = `"`
  - `TOKEN_STRING_CONTENT` = actual content (without quotes)
  - `TOKEN_STRING_END` = `"`
- **✅ SyntaxKind conversion working**: `NODE_STRING` = `SyntaxKind(65)`, direct casting via `as u16` successful
- **✅ GreenNodeBuilder token creation**: Confirmed `builder.token(kind, text)` API usage
- **✅ Green node access validated**: `node.green()` provides direct access to underlying GreenNodeData

### **Current Working Capabilities (rnix-test/)**
- **✅ Perfect structure preservation**: IDENTICAL regeneration confirmed (2285 bytes)
- **✅ Token-level structure analysis**: Complete decomposition of string literals
- **✅ SyntaxKind conversion**: rnix→rowan casting patterns established
- **✅ GreenNodeBuilder basics**: Construction workflow verified
- **✅ Green node access**: `node.green()` method confirmed for copying unchanged portions

## 🎯 **IMMEDIATE TASK: Implement Selective Tree Reconstruction (rnix-test/ ONLY)**

### **Goal**
Implement the core tree reconstruction capability that can:
1. **Copy unchanged green nodes directly** using `node.green()`
2. **Reconstruct only modified nodes** using GreenNodeBuilder with correct token structure
3. **Assemble complete trees** maintaining perfect structure preservation

### **⚠️ CRITICAL CONSTRAINT**
**CONTINUE WORKING ONLY WITHIN `rnix-test/` SUBPROJECT**. Do NOT integrate with root nixcfg until we have comprehensive cargo test validation of all reconstruction capabilities.

### **Strategic Technical Approach**

Based on discovered capabilities, implement this reconstruction pattern:

```rust
fn reconstruct_tree_with_url_replacement(
    original: &Root,
    target_input: &str,
    new_url: &str
) -> Result<Root, Error> {
    // 1. Traverse tree to identify target string node
    // 2. Use GreenNodeBuilder to reconstruct tree:
    //    - Copy unchanged portions via node.green()
    //    - Rebuild only the target string using TOKEN_STRING_* structure
    // 3. Assemble complete tree with perfect preservation
    // 4. Validate only target URL changed
}
```

## 🔬 **TECHNICAL IMPLEMENTATION PRIORITIES**

### **Priority 1: Green Node Copying Research (THIS SESSION)**
1. **Understand green node copying**: How to reuse `node.green()` in GreenNodeBuilder
2. **Research GreenNodeBuilder node insertion**: How to add existing green nodes to builder
3. **Test selective copying**: Copy most of tree, rebuild only specific string literal
4. **Validate copying fidelity**: Ensure copied portions remain byte-identical

### **Priority 2: Targeted String Replacement (THIS SESSION)**
1. **Implement target node identification**: Locate specific URL string within complex flake structure
2. **Build replacement logic**: Use discovered TOKEN_STRING_* pattern for URL reconstruction
3. **Test with real flake data**: Replace `home-manager` URL using actual nixcfg flake.nix
4. **Character-level validation**: Verify only target URL changed, everything else identical

### **Priority 3: Complete Tree Assembly (THIS SESSION)**
1. **Full tree reconstruction**: Handle complex AttrSet structures around string literals
2. **Context preservation**: Maintain all surrounding structure during selective modification
3. **Multiple input support**: Ensure approach works for different flake input formats
4. **Error handling**: Graceful failure for malformed inputs or missing targets

### **Priority 4: Comprehensive Test Suite (THIS SESSION)**
1. **Convert to cargo tests**: Transform demo code into proper test infrastructure
2. **Edge case coverage**: Various input formats, nested structures, error conditions
3. **Performance validation**: Ensure reconstruction efficiency for large flakes
4. **API stabilization**: Clean public interfaces ready for future integration

## 🧪 **SPECIFIC RESEARCH QUESTIONS FOR SESSION START**

### **Green Node Copying Mechanics**
1. **GreenNodeBuilder insertion**: Can we use `builder.add_child(green_node)` or similar?
2. **Green node compatibility**: Are green nodes from different trees compatible for copying?
3. **Tree assembly patterns**: How to efficiently copy large unchanged tree sections?
4. **Context preservation**: How to maintain exact spacing/formatting when copying?

### **Selective Reconstruction Strategy**
1. **Traversal patterns**: How to identify path to specific string literals in complex trees?
2. **Reconstruction boundaries**: What's the minimal tree section to rebuild for URL changes?
3. **Parent context handling**: How to preserve parent AttrSet structure around modified strings?
4. **Multiple modifications**: How to handle multiple URL changes in single reconstruction pass?

## 📁 **CURRENT WORKING ENVIRONMENT**

### **Test Project Status**
- **Location**: `/home/tim/src/nixcfg/rnix-test/` (enhanced with comprehensive research)
- **Dependencies**: rnix 0.12.0, rowan 0.15.17 (confirmed compatible)
- **Research modules**:
  - `mutation_research.rs` - immutability findings and reconstruction approach
  - `greennode_research.rs` - GreenNodeBuilder API analysis  
  - `simple_reconstruction.rs` - token structure discovery and basic reconstruction

### **Discovered Token Structure (Working)**
```rust
// CONFIRMED working pattern for string literal construction:
builder.start_node(string_node_kind);  // NODE_STRING = SyntaxKind(65)
builder.token(SyntaxKind(TOKEN_STRING_START as u16), "\"");
builder.token(SyntaxKind(TOKEN_STRING_CONTENT as u16), content);  
builder.token(SyntaxKind(TOKEN_STRING_END as u16), "\"");
builder.finish_node();
```

### **Target Test Case (Real Data)**
- **Source file**: `/home/tim/src/nixcfg/flake.nix` (2285 bytes, IDENTICAL regeneration confirmed)
- **Target input**: `home-manager` with complex format
- **Current URL**: `git+file:///home/tim/src/home-manager?ref=feature-test-with-fcitx5-fix`
- **Target URL**: `github:nix-community/home-manager`
- **Context structure**: `home-manager = { url = "..."; inputs.nixpkgs.follows = "nixpkgs"; }`

## 🎯 **SUCCESS CRITERIA FOR THIS SESSION**

### **Core Achievements (rnix-test/ ONLY)**
1. **✅ Green node copying mastery**: Successfully reuse unchanged portions via `node.green()`
2. **✅ Selective reconstruction**: Replace only target URL while preserving all other content
3. **✅ Real-world validation**: Demonstrate with actual nixcfg flake.nix (2285 bytes)
4. **✅ Character-perfect preservation**: Everything except target URL completely unchanged
5. **✅ Comprehensive test coverage**: Robust cargo test suite validating all capabilities

### **Expected Technical Outcomes**
- **Working selective reconstruction**: Actual tree modification with perfect preservation
- **Efficient green node reuse**: Copy unchanged portions without rebuilding
- **Production-ready URL replacement**: Handle complex flake input structures  
- **Complete test foundation**: Comprehensive validation for future integration
- **Clear implementation patterns**: Reusable approach for any AST modifications

## 🔧 **IMPLEMENTATION FOCUS FOR SESSION START**

### **Immediate Research Priorities**
1. **Green node copying**: Investigate how to add existing green nodes to GreenNodeBuilder
2. **Tree traversal**: Implement path finding to specific string literals in complex structures  
3. **Reconstruction boundaries**: Determine minimal rebuild scope for URL replacement
4. **Assembly validation**: Ensure reconstructed trees maintain perfect structure preservation

### **Starting Implementation Pattern**
```rust
// Target research pattern for this session:
fn selective_url_reconstruction(
    original_flake: &Root,
    input_name: &str,
    new_url: &str
) -> Result<Root, Error> {
    // 1. Parse and locate target string node path
    let (parent_context, string_node) = find_url_string_node(original_flake, input_name)?;
    
    // 2. Use GreenNodeBuilder for selective reconstruction
    let mut builder = GreenNodeBuilder::new();
    
    // 3. Copy unchanged tree portions using green node access
    copy_unchanged_portions(&mut builder, original_flake, parent_context)?;
    
    // 4. Rebuild only the target string with new URL
    rebuild_string_literal(&mut builder, new_url)?;
    
    // 5. Complete tree assembly and validation
    let new_tree = complete_tree_assembly(builder)?;
    validate_selective_changes(&new_tree, original_flake, input_name, new_url)?;
    
    Ok(new_tree)
}
```

## 🚀 **STRATEGIC IMPACT UPON COMPLETION**

### **This Session Will Enable (Future Sessions)**
- **Production-ready flake modification**: Complete tree reconstruction with perfect preservation
- **Enhanced workspace script integration**: Replace text processing with AST-based precision
- **Scalable multi-input modification**: Support for complex development environments
- **Foundation for advanced features**: Multi-file coordination, conditional modifications, etc.

### **Integration Timeline Preview**
After comprehensive cargo test validation within `rnix-test/`, FUTURE sessions will focus on **replacing the current text-processing approach in the workspace script** with these AST reconstruction capabilities, finally completing the git-worktree-superproject enhancement for Nix flakes.

## 🎯 **START HERE (rnix-test/ ONLY)**

**Begin with**: Research how to copy unchanged green nodes using GreenNodeBuilder. Focus on understanding the `node.green()` → `builder` integration patterns.

**Target outcome**: Successfully demonstrate selective reconstruction where only the target URL changes while all other content (including formatting, comments, spacing) remains byte-identical.

**⚠️ WORKSPACE CONSTRAINT**: Continue working ONLY within `/home/tim/src/nixcfg/rnix-test/` directory. Do NOT modify any files in the root nixcfg project.

**Research focus**: Green node copying and selective tree reconstruction:
1. How to integrate existing green nodes into GreenNodeBuilder
2. Efficient traversal patterns for complex tree structures
3. Minimal reconstruction scope for targeted modifications
4. Validation approaches for perfect structure preservation

**Milestone target**: Working selective URL replacement using green node copying with comprehensive cargo test validation, preparing for final integration phase.