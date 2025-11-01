use std::fs;
use rnix::{ast, ast::HasEntry};

mod mutation_research;
mod greennode_research;
mod simple_reconstruction;
mod selective_reconstruction;
mod real_flake_test;
mod comprehensive_tests;
mod advanced_flake_patterns_tests;
mod flake_parts_advanced_tests;
mod nested_flake_tests;

fn main() {
    println!("=== rnix-parser flake.nix evaluation ===");
    
    // Read the actual nixcfg flake.nix
    let flake_path = "../flake.nix";
    let content = match fs::read_to_string(flake_path) {
        Ok(content) => content,
        Err(e) => {
            eprintln!("Error reading {}: {}", flake_path, e);
            return;
        }
    };
    
    println!("✅ Successfully read flake.nix ({} bytes)", content.len());
    
    // Parse with rnix
    let parse_result = rnix::Root::parse(&content);
    
    // Check for parsing errors
    let errors: Vec<_> = parse_result.errors().into_iter().collect();
    if !errors.is_empty() {
        println!("⚠️  Parsing errors found:");
        for error in &errors {
            println!("   {}", error);
        }
    } else {
        println!("✅ No parsing errors");
    }
    
    // Get the syntax tree
    let tree = parse_result.tree();
    
    // Test structure preservation using the tree directly
    let regenerated = format!("{}", tree);
    let is_identical = content == regenerated;
    
    println!("✅ Structure preservation test: {}", 
        if is_identical { "IDENTICAL" } else { "DIFFERS" }
    );
    
    if !is_identical {
        println!("   Original length: {}", content.len());
        println!("   Regenerated length: {}", regenerated.len());
        
        // Show a sample of differences
        let orig_lines: Vec<&str> = content.lines().take(5).collect();
        let regen_lines: Vec<&str> = regenerated.lines().take(5).collect();
        
        println!("   Original first 5 lines:");
        for (i, line) in orig_lines.iter().enumerate() {
            println!("     {}: {}", i+1, line);
        }
        
        println!("   Regenerated first 5 lines:");
        for (i, line) in regen_lines.iter().enumerate() {
            println!("     {}: {}", i+1, line);
        }
    }
    
    // Basic AST information
    println!("\n=== Basic AST Information ===");
    println!("Root node type: {:?}", tree);
    
    // Try to show some basic structure
    println!("\n=== Testing AST traversal capabilities ===");
    if let Some(expr) = tree.expr() {
        println!("✅ Successfully accessed root expression");
        println!("Expression type: {:?}", expr);
        
        // Test finding inputs section
        println!("\n=== Searching for inputs section ===");
        if let Some(inputs_section) = find_inputs_section(&expr) {
            println!("✅ Found inputs section");
            
            // Test finding home-manager input
            println!("\n=== Searching for home-manager input ===");
            if let Some(home_manager_input) = find_input_by_name(&inputs_section, "home-manager") {
                println!("✅ Found home-manager input");
                
                // Test extracting URL
                if let Some(url) = extract_url_value(&home_manager_input) {
                    println!("✅ Extracted URL: {}", url);
                    
                    // Test URL replacement
                    println!("\n=== Testing URL replacement ===");
                    let new_url = "github:nix-community/home-manager";
                    test_url_replacement(&content, &tree, "home-manager", new_url);
                    
                    // Test multiple inputs to validate approach
                    println!("\n=== Testing multiple input detection ===");
                    test_multiple_inputs(&inputs_section);
                } else {
                    println!("❌ Could not extract URL from home-manager input");
                }
            } else {
                println!("❌ Could not find home-manager input");
            }
        } else {
            println!("❌ Could not find inputs section");
        }
    } else {
        println!("❌ Could not access root expression");
    }
}

/// Find the inputs section in a flake expression (simplified approach)
fn find_inputs_section(expr: &ast::Expr) -> Option<ast::AttrSet> {
    if let ast::Expr::AttrSet(attr_set) = expr {
        // Use string representation to find inputs section for now
        let full_text = format!("{}", attr_set);
        if full_text.contains("inputs = {") {
            println!("✅ Found inputs section in AttrSet");
            return Some(attr_set.clone());
        }
    }
    None
}

/// Find a specific input by name within the inputs section (simplified approach)
fn find_input_by_name(inputs: &ast::AttrSet, target_name: &str) -> Option<ast::Entry> {
    let inputs_text = format!("{}", inputs);
    println!("  DEBUG: Searching for '{}' in inputs section", target_name);
    
    // Look for the target name in the inputs text
    if inputs_text.contains(&format!("{} =", target_name)) {
        println!("  ✅ Found '{}' in inputs text", target_name);
        // For now, return the first entry as a placeholder
        // TODO: Implement proper entry matching
        for entry in inputs.entries() {
            let entry_text = format!("{}", entry);
            if entry_text.contains(&format!("{} =", target_name)) {
                return Some(entry);
            }
        }
    }
    None
}

/// Extract URL value from an input entry (handles both simple and complex formats)
fn extract_url_value_for_input(input: &ast::Entry, input_name: &str) -> Option<String> {
    let value_str = format!("{}", input);
    
    // Look for specific input in complex format: input-name = { url = "..."; ... }
    let complex_pattern = format!("{} = {{", input_name);
    if value_str.contains(&complex_pattern) {
        if let Some(input_start) = value_str.find(&complex_pattern) {
            let after_input = &value_str[input_start..];
            if let Some(url_start_pos) = after_input.find("url = \"") {
                let url_start = url_start_pos + 7; // length of "url = \""
                if let Some(url_end_pos) = after_input[url_start..].find('"') {
                    let url = &after_input[url_start..url_start + url_end_pos];
                    return Some(url.to_string());
                }
            }
        }
    }
    
    // Look for simple format: input-name.url = "..."
    let simple_pattern = format!("{}.url = \"", input_name);
    if value_str.contains(&simple_pattern) {
        if let Some(url_start_pos) = value_str.find(&simple_pattern) {
            let url_start = url_start_pos + simple_pattern.len();
            if let Some(url_end_pos) = value_str[url_start..].find('"') {
                let url = &value_str[url_start..url_start + url_end_pos];
                return Some(url.to_string());
            }
        }
    }
    
    None
}

/// Extract URL value from an input entry (handles both simple and complex formats)
fn extract_url_value(input: &ast::Entry) -> Option<String> {
    // This function is used specifically for home-manager, so hardcode that for now
    extract_url_value_for_input(input, "home-manager")
}

/// Test URL replacement while preserving structure
fn test_url_replacement(_original_content: &str, tree: &ast::Root, input_name: &str, new_url: &str) {
    println!("🔧 Testing URL replacement for input '{}' -> '{}'", input_name, new_url);
    
    // For now, let's just validate that we can find and extract the current URL
    // In a real implementation, we would modify the AST and regenerate
    
    if let Some(expr) = tree.expr() {
        if let Some(inputs_section) = find_inputs_section(&expr) {
            if let Some(input_entry) = find_input_by_name(&inputs_section, input_name) {
                if let Some(current_url) = extract_url_value(&input_entry) {
                    println!("  Current URL: {}", current_url);
                    println!("  Target URL:  {}", new_url);
                    
                    // TODO: Implement actual AST modification
                    // For now, demonstrate that we have the foundation for replacement
                    if current_url != new_url {
                        println!("  ✅ URLs differ - replacement would be needed");
                        println!("  📋 TODO: Implement AST node modification");
                    } else {
                        println!("  ℹ️  URLs are identical - no replacement needed");
                    }
                } else {
                    println!("  ❌ Could not extract current URL");
                }
            } else {
                println!("  ❌ Could not find input '{}'", input_name);
            }
        } else {
            println!("  ❌ Could not find inputs section");
        }
    } else {
        println!("  ❌ Could not access root expression");
    }
}

/// Test detection of multiple inputs to validate the approach
fn test_multiple_inputs(inputs: &ast::AttrSet) {
    let test_inputs = vec!["nixpkgs", "nixvim", "darwin", "nixpkgs-esp-dev"];
    
    for input_name in test_inputs {
        if let Some(input_entry) = find_input_by_name(inputs, input_name) {
            if let Some(url) = extract_url_value_for_input(&input_entry, input_name) {
                println!("✅ {}: {}", input_name, url);
            } else {
                println!("❌ {}: Could not extract URL", input_name);
            }
        } else {
            println!("❌ {}: Not found", input_name);
        }
    }
    
    // Research rnix AST modification capabilities
    println!("\n=== AST Modification Research ===");
    mutation_research::demonstrate_rnix_immutability();
    mutation_research::test_tree_reconstruction_approach();
    
    // Research GreenNodeBuilder API for tree reconstruction
    println!("\n=== GreenNodeBuilder API Research ===");
    greennode_research::research_greennode_builder_api();
    
    // Test simple string reconstruction
    println!("\n=== Simple String Reconstruction Tests ===");
    simple_reconstruction::research_string_literal_structure();
    simple_reconstruction::test_simple_string_reconstruction();
    
    // Test selective reconstruction using green node copying
    println!("\n=== Selective Reconstruction Research ===");
    selective_reconstruction::research_green_node_copying();
    selective_reconstruction::test_selective_reconstruction();
    
    // Test with real flake.nix
    println!("\n=== Real Flake.nix Test ===");
    real_flake_test::test_real_flake_reconstruction();
}
