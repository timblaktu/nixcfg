use std::fs;
use rnix::{Root, SyntaxKind};
use rowan::{GreenNodeBuilder, ast::AstNode};
use crate::selective_reconstruction::{find_url_string_path, reconstruct_with_replacement};

/// Comprehensive test suite for selective tree reconstruction capabilities
/// 
/// This module provides thorough validation of:
/// 1. String literal reconstruction with perfect preservation
/// 2. Complex structure navigation and path finding
/// 3. Selective replacement maintaining structure integrity
/// 4. Real-world flake.nix handling
/// 5. Error conditions and edge cases

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_basic_string_replacement() {
        let input = r#""old-value""#;
        let expected = r#""new-value""#;
        
        let parse_result = Root::parse(input);
        let tree = parse_result.tree();
        
        if let Some(expr) = tree.expr() {
            let node = expr.syntax();
            
            if let Some(path) = find_url_string_path(node, "old-value") {
                let mut builder = GreenNodeBuilder::new();
                
                assert!(reconstruct_with_replacement(&mut builder, node, &path, 0, "new-value").is_ok());
                
                let result = builder.finish();
                let new_tree = rnix::SyntaxNode::new_root(result);
                let result_text = new_tree.text().to_string();
                
                assert_eq!(result_text, expected);
            } else {
                panic!("Could not find target string");
            }
        } else {
            panic!("Could not parse input");
        }
    }
    
    #[test]
    fn test_complex_attrset_replacement() {
        let input = r#"{ inputs = { nixpkgs.url = "old-url"; other = "unchanged"; }; }"#;
        let expected_pattern = r#"{ inputs = { nixpkgs.url = "new-url"; other = "unchanged"; }; }"#;
        
        let parse_result = Root::parse(input);
        let tree = parse_result.tree();
        
        if let Some(expr) = tree.expr() {
            let node = expr.syntax();
            
            if let Some(path) = find_url_string_path(node, "old-url") {
                let mut builder = GreenNodeBuilder::new();
                
                assert!(reconstruct_with_replacement(&mut builder, node, &path, 0, "new-url").is_ok());
                
                let result = builder.finish();
                let new_tree = rnix::SyntaxNode::new_root(result);
                let result_text = new_tree.text().to_string();
                
                assert_eq!(result_text, expected_pattern);
                assert!(result_text.contains("new-url"));
                assert!(!result_text.contains("old-url"));
                assert!(result_text.contains("unchanged"));
            } else {
                panic!("Could not find target string");
            }
        } else {
            panic!("Could not parse input");
        }
    }
    
    #[test]
    fn test_nested_structure_replacement() {
        let input = r#"{ inputs = { home-manager = { url = "github:old/repo"; inputs.nixpkgs.follows = "nixpkgs"; }; }; }"#;
        
        let parse_result = Root::parse(input);
        let tree = parse_result.tree();
        
        if let Some(expr) = tree.expr() {
            let node = expr.syntax();
            
            if let Some(path) = find_url_string_path(node, "github:old/repo") {
                let mut builder = GreenNodeBuilder::new();
                
                assert!(reconstruct_with_replacement(&mut builder, node, &path, 0, "github:new/repo").is_ok());
                
                let result = builder.finish();
                let new_tree = rnix::SyntaxNode::new_root(result);
                let result_text = new_tree.text().to_string();
                
                assert!(result_text.contains("github:new/repo"));
                assert!(!result_text.contains("github:old/repo"));
                assert!(result_text.contains("inputs.nixpkgs.follows"));
                assert!(result_text.contains("home-manager"));
            } else {
                panic!("Could not find target string");
            }
        } else {
            panic!("Could not parse input");
        }
    }
    
    #[test]
    fn test_multiple_urls_selective_replacement() {
        let input = r#"{ inputs = { nixpkgs.url = "github:nixos/nixpkgs"; home-manager.url = "github:old/repo"; }; }"#;
        
        let parse_result = Root::parse(input);
        let tree = parse_result.tree();
        
        if let Some(expr) = tree.expr() {
            let node = expr.syntax();
            
            // Test that we can selectively replace only the home-manager URL
            if let Some(path) = find_url_string_path(node, "github:old/repo") {
                let mut builder = GreenNodeBuilder::new();
                
                assert!(reconstruct_with_replacement(&mut builder, node, &path, 0, "github:new/repo").is_ok());
                
                let result = builder.finish();
                let new_tree = rnix::SyntaxNode::new_root(result);
                let result_text = new_tree.text().to_string();
                
                // Verify selective replacement
                assert!(result_text.contains("github:new/repo"));
                assert!(!result_text.contains("github:old/repo"));
                assert!(result_text.contains("github:nixos/nixpkgs")); // Should be unchanged
            } else {
                panic!("Could not find target string");
            }
        } else {
            panic!("Could not parse input");
        }
    }
    
    #[test]
    fn test_structure_preservation_with_comments() {
        let input = r#"{
  # This is a comment
  inputs = {
    nixpkgs.url = "old-url"; # inline comment
    # Another comment
    other = "value";
  };
}"#;
        
        let parse_result = Root::parse(input);
        let tree = parse_result.tree();
        
        if let Some(expr) = tree.expr() {
            let node = expr.syntax();
            
            if let Some(path) = find_url_string_path(node, "old-url") {
                let mut builder = GreenNodeBuilder::new();
                
                assert!(reconstruct_with_replacement(&mut builder, node, &path, 0, "new-url").is_ok());
                
                let result = builder.finish();
                let new_tree = rnix::SyntaxNode::new_root(result);
                let result_text = new_tree.text().to_string();
                
                // Verify URL change
                assert!(result_text.contains("new-url"));
                assert!(!result_text.contains("old-url"));
                
                // Verify comment preservation
                assert!(result_text.contains("# This is a comment"));
                assert!(result_text.contains("# inline comment"));
                assert!(result_text.contains("# Another comment"));
                
                // Verify structure preservation
                assert!(result_text.contains("other = \"value\""));
            } else {
                panic!("Could not find target string");
            }
        } else {
            panic!("Could not parse input");
        }
    }
    
    #[test]
    fn test_nonexistent_string_handling() {
        let input = r#"{ inputs = { nixpkgs.url = "github:nixos/nixpkgs"; }; }"#;
        
        let parse_result = Root::parse(input);
        let tree = parse_result.tree();
        
        if let Some(expr) = tree.expr() {
            let node = expr.syntax();
            
            // Should return None for non-existent string
            let path = find_url_string_path(node, "nonexistent-url");
            assert!(path.is_none());
        } else {
            panic!("Could not parse input");
        }
    }
    
    #[test]
    fn test_syntax_validation_after_replacement() {
        let test_cases = vec![
            (r#""simple""#, "replacement"),
            (r#"{ url = "old"; }"#, "new"),
            (r#"{ inputs = { test.url = "old-url"; }; }"#, "new-url"),
        ];
        
        for (input, new_value) in test_cases {
            let parse_result = Root::parse(input);
            let tree = parse_result.tree();
            
            if let Some(expr) = tree.expr() {
                let node = expr.syntax();
                
                // Find any string in the input
                if let Some(path) = find_first_string_path(node) {
                    let mut builder = GreenNodeBuilder::new();
                    
                    assert!(reconstruct_with_replacement(&mut builder, node, &path, 0, new_value).is_ok());
                    
                    let result = builder.finish();
                    let new_tree = rnix::SyntaxNode::new_root(result);
                    let result_text = new_tree.text().to_string();
                    
                    // Validate that result is still valid Nix syntax
                    let validation_result = Root::parse(&result_text);
                    let errors: Vec<_> = validation_result.errors().into_iter().collect();
                    
                    assert!(errors.is_empty(), "Syntax errors after replacement: {:?}", errors);
                }
            }
        }
    }
    
    #[test]
    fn test_real_flake_comprehensive() {
        // Test with actual nixcfg flake.nix if available
        if let Ok(content) = fs::read_to_string("../flake.nix") {
            let parse_result = Root::parse(&content);
            let tree = parse_result.tree();
            
            if let Some(expr) = tree.expr() {
                let node = expr.syntax();
                
                // Test finding home-manager URL
                let hm_url = "git+file:///home/tim/src/home-manager?ref=feature-test-with-fcitx5-fix";
                if let Some(path) = find_url_string_path(node, hm_url) {
                    let mut builder = GreenNodeBuilder::new();
                    
                    assert!(reconstruct_with_replacement(&mut builder, node, &path, 0, "github:nix-community/home-manager").is_ok());
                    
                    let result = builder.finish();
                    let new_tree = rnix::SyntaxNode::new_root(result);
                    let result_text = new_tree.text().to_string();
                    
                    // Validate syntax
                    let validation_result = Root::parse(&result_text);
                    let errors: Vec<_> = validation_result.errors().into_iter().collect();
                    assert!(errors.is_empty(), "Real flake syntax errors: {:?}", errors);
                    
                    // Validate replacement
                    assert!(result_text.contains("github:nix-community/home-manager"));
                    assert!(!result_text.contains(hm_url));
                }
            }
        }
    }
    
    #[test]
    fn test_performance_with_large_structure() {
        // Create a larger structure to test performance
        let mut large_input = String::from("{\n  inputs = {\n");
        
        for i in 0..50 {
            large_input.push_str(&format!("    input{}.url = \"github:example/repo{}\";\n", i, i));
        }
        
        large_input.push_str("    target.url = \"old-target-url\";\n");
        large_input.push_str("  };\n}");
        
        let parse_result = Root::parse(&large_input);
        let tree = parse_result.tree();
        
        if let Some(expr) = tree.expr() {
            let node = expr.syntax();
            
            if let Some(path) = find_url_string_path(node, "old-target-url") {
                let mut builder = GreenNodeBuilder::new();
                
                // Time the reconstruction
                let start = std::time::Instant::now();
                assert!(reconstruct_with_replacement(&mut builder, node, &path, 0, "new-target-url").is_ok());
                let duration = start.elapsed();
                
                let result = builder.finish();
                let new_tree = rnix::SyntaxNode::new_root(result);
                let result_text = new_tree.text().to_string();
                
                // Should complete quickly (under 100ms for 50 inputs)
                assert!(duration.as_millis() < 100, "Performance test failed: took {}ms", duration.as_millis());
                
                // Validate result
                assert!(result_text.contains("new-target-url"));
                assert!(!result_text.contains("old-target-url"));
                
                // Validate syntax
                let validation_result = Root::parse(&result_text);
                let errors: Vec<_> = validation_result.errors().into_iter().collect();
                assert!(errors.is_empty());
            } else {
                panic!("Could not find target in large structure");
            }
        }
    }
}

/// Helper function to find the first string literal in a tree (for testing)
fn find_first_string_path(node: &rnix::SyntaxNode) -> Option<Vec<usize>> {
    if node.kind() == SyntaxKind::NODE_STRING {
        return Some(vec![]);
    }
    
    for (i, child) in node.children().enumerate() {
        if let Some(mut path) = find_first_string_path(&child) {
            path.insert(0, i);
            return Some(path);
        }
    }
    
    None
}

/// Utility function for validating reconstruction results
pub fn validate_reconstruction_result(
    original: &str,
    result: &str,
    old_value: &str,
    new_value: &str
) -> Result<(), String> {
    
    // Check URL replacement
    if result.contains(old_value) {
        return Err(format!("Old value '{}' still present in result", old_value));
    }
    
    if !result.contains(new_value) {
        return Err(format!("New value '{}' not found in result", new_value));
    }
    
    // Check syntax validity
    let parse_result = Root::parse(result);
    let errors: Vec<_> = parse_result.errors().into_iter().collect();
    if !errors.is_empty() {
        return Err(format!("Syntax errors in result: {:?}", errors));
    }
    
    // Check length consistency
    let expected_length_diff = new_value.len() as i32 - old_value.len() as i32;
    let actual_length_diff = result.len() as i32 - original.len() as i32;
    
    if (actual_length_diff - expected_length_diff).abs() > 1 {
        return Err(format!("Unexpected length change: expected {}, got {}", 
                          expected_length_diff, actual_length_diff));
    }
    
    Ok(())
}