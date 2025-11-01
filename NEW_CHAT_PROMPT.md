# NEXT Session Focus: Implement Expanded rnix-test Coverage

## ✅ **COMPLETED IN PREVIOUS SESSION**

**Critical Analysis Task Completed Successfully**:
1. ✅ **Current test coverage analysis**: 26 passing tests across 8 files with comprehensive basic coverage
2. ✅ **flake-parts research**: Advanced patterns including module input access, perSystem distinctions, custom module arguments  
3. ✅ **Nested flake research**: Direct flake references, transitive input chains, complex follows patterns
4. ✅ **Coverage gap identification**: 4 specific pattern categories needing test implementation

## 🎯 **IMMEDIATE PRIORITY FOR THIS SESSION**

### **Priority 1: Implement Test Coverage for Discovered Patterns** 🔥 **START HERE**

**Mission**: Implement comprehensive test coverage for the 4 discovered pattern categories that are missing from current test suite.

**Implementation Strategy**: Create focused test files for each pattern category with production-realistic test cases.

### **Required Test Implementation** (Choose ONE to start):

#### **Option A: flake-parts Advanced Patterns** 
**File**: `src/flake_parts_advanced_tests.rs`
**Test Cases**:
1. **Module Input Access Pattern**: Test `_module.args.origInputs = inputs` pattern for passing inputs to separate modules
2. **perSystem Input Distinction**: Test `inputs'` vs `inputs` access patterns within perSystem modules  
3. **Custom Module Arguments**: Test custom pkgs definitions with overlays via module arguments

#### **Option B: Nested Flake Input Patterns**
**File**: `src/nested_flake_tests.rs` 
**Test Cases**:
1. **Direct Flake Reference**: Test flakes referencing other repositories that are themselves flakes
2. **Transitive Input Chains**: Test flake A → flake B → flake C dependency patterns
3. **Complex Follows Chains**: Test `mynixpkgs.follows = "dotfiles/nixpkgs"` transitivity patterns

#### **Option C: Git Submodule Patterns** 
**File**: `src/submodule_input_tests.rs`
**Test Cases**:
1. **Submodule URL Parameters**: Test `git+https://...?submodules=1` pattern
2. **Manual Submodule Inputs**: Test `{ url = "./sub"; flake = false; }` patterns
3. **Local Submodule References**: Test `git+file://...?submodules=1` patterns

#### **Option D: Self-Reference Patterns**
**File**: `src/self_reference_tests.rs` 
**Test Cases**:
1. **Output Composition**: Test `${self.packages.x86_64-linux.base}` references
2. **Self Input Access**: Test `self` special input handling in AST modification
3. **Recursive Reference Chains**: Test when outputs reference other outputs from same flake

## 📋 **SPECIFIC TASKS FOR THIS SESSION**

### **Task 1: Choose Implementation Focus** (START HERE)
1. Select ONE of the 4 pattern categories above (recommend starting with Option A - flake-parts advanced)
2. Navigate to `/home/tim/src/nixcfg/rnix-test/src/`
3. Create the new test file for chosen pattern category
4. Implement first test case with AST-based URL replacement validation

### **Task 2: Test Implementation Standards**
**Critical Requirements**:
- Use existing `find_url_string_path` and `reconstruct_with_replacement` functions from selective_reconstruction.rs
- Test both structure preservation AND successful URL replacement
- Validate syntax with `Root::parse()` after modification
- Include realistic flake patterns based on research findings
- Test edge cases and error conditions

**Test Template Pattern**:
```rust
#[test]
fn test_pattern_name() {
    let input = r#"{ /* realistic flake pattern */ }"#;
    let parse_result = Root::parse(input);
    let tree = parse_result.tree();
    
    if let Some(expr) = tree.expr() {
        let node = expr.syntax();
        
        if let Some(path) = find_url_string_path(node, "target-url") {
            let mut builder = GreenNodeBuilder::new();
            assert!(reconstruct_with_replacement(&mut builder, node, &path, 0, "new-url").is_ok());
            
            let result = builder.finish();
            let new_tree = rnix::SyntaxNode::new_root(result);
            let result_text = new_tree.text().to_string();
            
            // Verify replacement + structure preservation + syntax validation
        }
    }
}
```

### **Task 3: Integration Readiness Validation**
After implementing test coverage:
1. Run `cargo test` to ensure all tests pass
2. Validate that AST system handles the new patterns correctly
3. Update CLAUDE.md with implementation progress
4. Assess readiness for workspace script integration

## 🔧 **CONTEXT: Integration Work Status**

**What's Already Done**: Complete AST-based flake input modification integration (commit 895f70c on dev branch)
- ✅ **flake-input-modifier binary**: Production-ready standalone tool
- ✅ **workspace script integration**: Enhanced wt-super with Nix flake support  
- ✅ **AST capabilities**: Perfect structure preservation for existing test patterns

**What's Missing**: Validation that AST system handles ALL real-world flake patterns, not just the basic ones currently tested.

**Why This Matters**: The workspace integration is functional but premature without comprehensive test validation. Must ensure robustness before considering it production-ready.

## 🎯 **SUCCESS CRITERIA**

### **Session Goals**:
1. **✅ Implement expanded test coverage**: At least ONE complete pattern category with multiple test cases
2. **✅ Validate AST robustness**: Ensure AST system handles advanced patterns correctly  
3. **📋 Clear implementation roadmap**: Updated task queue for remaining pattern categories
4. **📊 Integration readiness assessment**: Determine if workspace integration is truly production-ready

### **Quality Standards**:
- Tests must use realistic, production-based flake patterns
- All tests must validate both replacement success AND structure preservation
- Test implementation must follow existing patterns and coding standards
- Error conditions and edge cases must be covered

## 🎯 **START HERE**

Begin with **Option A: flake-parts Advanced Patterns** - create `src/flake_parts_advanced_tests.rs` and implement the Module Input Access Pattern test case using the research findings from the previous session.

**Remember**: The goal is validation and robustness testing, not new feature development. The AST system is already complete - we're proving it works correctly with advanced real-world patterns.