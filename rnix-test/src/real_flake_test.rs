use std::fs;
use rnix::Root;
use crate::selective_reconstruction::{find_url_string_path, reconstruct_with_replacement};
use rowan::{GreenNodeBuilder, ast::AstNode};

/// Test selective reconstruction with the actual nixcfg flake.nix
pub fn test_real_flake_reconstruction() {
    println!("=== Real Flake Reconstruction Test ===");
    
    // Read the actual flake.nix
    let flake_path = "../flake.nix";
    let content = match fs::read_to_string(flake_path) {
        Ok(content) => content,
        Err(e) => {
            println!("❌ Error reading {}: {}", flake_path, e);
            return;
        }
    };
    
    println!("✅ Read flake.nix ({} bytes)", content.len());
    
    // Parse the flake
    let parse_result = Root::parse(&content);
    let tree = parse_result.tree();
    
    if let Some(expr) = tree.expr() {
        println!("✅ Parsed flake.nix successfully");
        
        // Test replacing home-manager URL
        test_home_manager_url_replacement(expr.syntax(), &content);
        
        // Test with a non-existent URL to ensure it fails gracefully
        test_nonexistent_url_replacement(expr.syntax());
    } else {
        println!("❌ Failed to parse flake.nix");
    }
}

fn test_home_manager_url_replacement(node: &rnix::SyntaxNode, original_content: &str) {
    println!("\n🎯 Testing home-manager URL replacement in real flake...");
    
    let old_url = "git+file:///home/tim/src/home-manager?ref=feature-test-with-fcitx5-fix";
    let new_url = "github:nix-community/home-manager";
    
    println!("Replacing: {} -> {}", old_url, new_url);
    
    if let Some(path) = find_url_string_path(node, old_url) {
        println!("✅ Found home-manager URL at path: {:?}", path);
        
        let mut builder = GreenNodeBuilder::new();
        
        if reconstruct_with_replacement(&mut builder, node, &path, 0, new_url).is_ok() {
            let result = builder.finish();
            let new_syntax_node = rnix::SyntaxNode::new_root(result);
            let result_text = new_syntax_node.text().to_string();
            
            println!("✅ Replacement successful!");
            
            // Validate the replacement
            if result_text.contains(new_url) && !result_text.contains(old_url) {
                println!("✅ URL replacement validated!");
                
                // Validate structure preservation
                validate_structure_preservation(original_content, &result_text, old_url, new_url);
            } else {
                println!("❌ URL replacement validation failed");
                if result_text.contains(old_url) {
                    println!("   - Old URL still present");
                }
                if !result_text.contains(new_url) {
                    println!("   - New URL not found");
                }
            }
        } else {
            println!("❌ Replacement failed");
        }
    } else {
        println!("❌ Could not find home-manager URL in flake");
    }
}

fn test_nonexistent_url_replacement(node: &rnix::SyntaxNode) {
    println!("\n🧪 Testing with non-existent URL (should fail gracefully)...");
    
    let nonexistent_url = "github:does-not-exist/fake-repo";
    
    if let Some(path) = find_url_string_path(node, nonexistent_url) {
        println!("❌ Unexpectedly found non-existent URL at path: {:?}", path);
    } else {
        println!("✅ Correctly identified that non-existent URL is not present");
    }
}

fn validate_structure_preservation(original: &str, result: &str, old_url: &str, new_url: &str) {
    println!("\n🔍 Validating structure preservation...");
    
    // Calculate expected length change
    let url_length_diff = new_url.len() as i32 - old_url.len() as i32;
    let expected_length = (original.len() as i32 + url_length_diff) as usize;
    
    println!("Original length: {}", original.len());
    println!("Result length: {}", result.len());
    println!("Expected length: {} (diff: {})", expected_length, url_length_diff);
    
    if result.len() == expected_length {
        println!("✅ Length change matches expectation");
    } else {
        println!("⚠️  Length change differs from expectation");
        println!("   Actual diff: {}", result.len() as i32 - original.len() as i32);
        println!("   Expected diff: {}", url_length_diff);
    }
    
    // Check that all other content is preserved
    let original_without_old_url = original.replace(old_url, "PLACEHOLDER");
    let result_without_new_url = result.replace(new_url, "PLACEHOLDER");
    
    if original_without_old_url == result_without_new_url {
        println!("✅ All non-target content perfectly preserved");
    } else {
        println!("❌ Some non-target content changed unexpectedly");
        
        // Show a sample of the differences for debugging
        let orig_lines: Vec<&str> = original_without_old_url.lines().take(5).collect();
        let result_lines: Vec<&str> = result_without_new_url.lines().take(5).collect();
        
        println!("   First 5 lines of original (with placeholder):");
        for (i, line) in orig_lines.iter().enumerate() {
            println!("     {}: {}", i+1, line);
        }
        
        println!("   First 5 lines of result (with placeholder):");
        for (i, line) in result_lines.iter().enumerate() {
            println!("     {}: {}", i+1, line);
        }
    }
    
    // Parse both to ensure they're still valid Nix
    validate_nix_syntax(original, "original");
    validate_nix_syntax(result, "result");
}

fn validate_nix_syntax(content: &str, label: &str) {
    let parse_result = Root::parse(content);
    let errors: Vec<_> = parse_result.errors().into_iter().collect();
    
    if errors.is_empty() {
        println!("✅ {} has valid Nix syntax", label);
    } else {
        println!("❌ {} has syntax errors:", label);
        for error in errors.iter().take(3) { // Show max 3 errors
            println!("   - {}", error);
        }
        if errors.len() > 3 {
            println!("   ... and {} more errors", errors.len() - 3);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_real_flake_url_replacement() {
        test_real_flake_reconstruction();
    }
}