use rnix::{Root, SyntaxKind, SyntaxNode};
use rowan::{GreenNodeBuilder, ast::AstNode, NodeOrToken};

/// Selective tree reconstruction implementation
/// 
/// Goal: Copy unchanged green nodes directly while rebuilding only modified portions
/// to enable precise URL replacement in complex flake structures.

/// Research how to copy unchanged green nodes using GreenNodeBuilder
pub fn research_green_node_copying() {
    println!("=== Green Node Copying Research ===");
    
    // Test case: Parse a complex structure and copy most of it unchanged
    let complex_example = r#"{ inputs = { nixpkgs.url = "old-url"; other = "unchanged"; }; }"#;
    println!("Test case: {}", complex_example);
    
    let parse_result = Root::parse(complex_example);
    let tree = parse_result.tree();
    
    if let Some(expr) = tree.expr() {
        println!("✅ Parsed complex structure");
        
        // Research: Can we copy the green node directly?
        research_direct_green_node_copying(expr.syntax());
        
        // Research: How to selectively reconstruct parts?
        research_selective_reconstruction_patterns(expr.syntax());
    }
}

fn research_direct_green_node_copying(node: &SyntaxNode) {
    println!("\n🔍 Researching direct green node copying...");
    
    // Get the green node data
    let green = node.green();
    println!("Green node kind: {:?}", green.kind());
    
    // Research: How do we add this green node to a GreenNodeBuilder?
    // Let's check the GreenNodeBuilder API for methods that accept green nodes
    
    println!("🔧 GreenNodeBuilder API research for green node insertion:");
    println!("  Methods we need to find:");
    println!("  - add_child(green: GreenNode) ?");
    println!("  - insert_node(green: GreenNode) ?");
    println!("  - copy_node(green: GreenNode) ?");
    
    // Let's try to create a simple example where we copy this node
    test_green_node_reuse(&*green);
}

fn test_green_node_reuse(green: &rowan::GreenNodeData) {
    println!("\n🧪 Testing green node reuse...");
    
    // Create a new GreenNodeBuilder
    let mut builder = GreenNodeBuilder::new();
    
    // Research question: How do we add the existing green node to the builder?
    // Let's check what methods are available...
    
    println!("Green node data:");
    println!("  kind: {:?}", green.kind());
    println!("  children: {}", green.children().len());
    
    // Let's try to understand the structure better
    for (i, child) in green.children().enumerate() {
        match child {
            NodeOrToken::Node(node) => {
                println!("  child[{}]: Node({:?})", i, node.kind());
            },
            NodeOrToken::Token(token) => {
                println!("  child[{}]: Token({:?}) = {:?}", i, token.kind(), token.text());
            }
        }
    }
    
    // Now let's research how to copy this structure
    attempt_green_node_copying(&mut builder, green);
}

fn attempt_green_node_copying(builder: &mut GreenNodeBuilder, green: &rowan::GreenNodeData) {
    println!("\n🔧 Attempting green node copying...");
    
    // Research approach 1: Can we clone the green node and add it directly?
    // Let's see if GreenNodeBuilder has a method for this
    
    // From rowan documentation, we might need to:
    // 1. Clone the green node
    // 2. Add it using builder methods
    
    // Let's first understand what kind of green node we have
    let kind = green.kind();
    println!("Copying node of kind: {:?}", kind);
    
    // Research approach: Try to reconstruct the node using GreenNodeBuilder
    // by traversing its structure and recreating it
    reconstruct_green_node_structure(builder, green);
}

fn reconstruct_green_node_structure(builder: &mut GreenNodeBuilder, green: &rowan::GreenNodeData) {
    println!("🔄 Reconstructing green node structure...");
    
    let kind = green.kind();
    let rowan_kind = rowan::SyntaxKind(kind.0);
    
    // Start the node with the same kind
    builder.start_node(rowan_kind);
    
    // Add all children in the same order
    for child in green.children() {
        match child {
            NodeOrToken::Node(child_node) => {
                // Recursively reconstruct child nodes
                reconstruct_green_node_structure(builder, child_node);
            },
            NodeOrToken::Token(token) => {
                // Add tokens directly
                let token_kind = rowan::SyntaxKind(token.kind().0);
                builder.token(token_kind, token.text());
            }
        }
    }
    
    builder.finish_node();
    
    println!("✅ Reconstructed node structure");
}

fn research_selective_reconstruction_patterns(node: &SyntaxNode) {
    println!("\n🎯 Researching selective reconstruction patterns...");
    
    // Goal: Find the target string to replace and copy everything else unchanged
    
    println!("Original structure:");
    print_node_structure(node, 0);
    
    // Research question: How do we identify the target node to replace?
    if let Some(target_path) = find_url_string_path(node, "old-url") {
        println!("\n✅ Found target string path: {:?}", target_path);
        
        // Research: How do we reconstruct the tree with only this node changed?
        attempt_selective_replacement(node, &target_path, "new-url");
    } else {
        println!("\n❌ Could not find target string");
    }
}

fn print_node_structure(node: &SyntaxNode, depth: usize) {
    let indent = "  ".repeat(depth);
    println!("{}Node: {:?} = {:?}", indent, node.kind(), node.text());
    
    if depth < 3 { // Limit depth to avoid too much output
        for child in node.children() {
            print_node_structure(&child, depth + 1);
        }
    }
}

/// Find the path to a specific string value in the tree
pub fn find_url_string_path(node: &SyntaxNode, target_value: &str) -> Option<Vec<usize>> {
    // Search for a string node containing the target value
    if node.kind() == SyntaxKind::NODE_STRING {
        let text = node.text().to_string();
        if text.contains(target_value) {
            return Some(vec![]); // Found at this level
        }
    }
    
    // Search in children
    for (i, child) in node.children().enumerate() {
        if let Some(mut path) = find_url_string_path(&child, target_value) {
            path.insert(0, i);
            return Some(path);
        }
    }
    
    None
}

fn attempt_selective_replacement(original: &SyntaxNode, target_path: &[usize], new_value: &str) {
    println!("\n🔧 Attempting selective replacement...");
    println!("Target path: {:?}", target_path);
    println!("New value: {}", new_value);
    
    // Create a new tree with only the target node replaced
    let mut builder = GreenNodeBuilder::new();
    
    // This is the core challenge: How do we copy the entire tree structure
    // but replace only the node at the target path?
    
    if reconstruct_with_replacement(&mut builder, original, target_path, 0, new_value).is_ok() {
        let result = builder.finish();
        
        println!("✅ Selective replacement successful!");
        
        // Create a new syntax tree from the result
        let new_syntax_node = SyntaxNode::new_root(result);
        println!("Result: {}", new_syntax_node.text());
        
        // Validate that only the target changed
        validate_selective_replacement(original, &new_syntax_node, new_value);
    } else {
        println!("❌ Selective replacement failed");
    }
}

pub fn reconstruct_with_replacement(
    builder: &mut GreenNodeBuilder,
    node: &SyntaxNode,
    target_path: &[usize],
    current_depth: usize,
    new_value: &str
) -> Result<(), String> {
    
    let kind = node.kind();
    let rowan_kind = rowan::SyntaxKind(kind as u16);
    
    // Check if this is the target node to replace
    if target_path.len() == current_depth && kind == SyntaxKind::NODE_STRING {
        // This is the target string node - replace it
        println!("🎯 Replacing target string at depth {}", current_depth);
        create_replacement_string_node(builder, new_value)?;
        return Ok(());
    }
    
    // Not the target - copy this node and process children/tokens
    builder.start_node(rowan_kind);
    
    // CRITICAL FIX: Process children_with_tokens instead of just children
    // This ensures we preserve all tokens (whitespace, operators, etc.)
    if target_path.len() > current_depth {
        // We're on the path to the target - need to process children selectively
        let next_child_index = target_path[current_depth];
        let mut child_node_count = 0;
        
        for child in node.children_with_tokens() {
            match child {
                NodeOrToken::Node(child_node) => {
                    if child_node_count == next_child_index {
                        // This child is on the path to target - process recursively
                        reconstruct_with_replacement(builder, &child_node, target_path, current_depth + 1, new_value)?;
                    } else {
                        // This child is not on the path - copy it unchanged
                        copy_node_unchanged(builder, &child_node);
                    }
                    child_node_count += 1;
                },
                NodeOrToken::Token(token) => {
                    // Always copy tokens to preserve structure
                    let token_kind = rowan::SyntaxKind(token.kind() as u16);
                    builder.token(token_kind, token.text());
                }
            }
        }
    } else {
        // We're past the target path - copy all children and tokens unchanged
        for child in node.children_with_tokens() {
            match child {
                NodeOrToken::Node(child_node) => {
                    copy_node_unchanged(builder, &child_node);
                },
                NodeOrToken::Token(token) => {
                    let token_kind = rowan::SyntaxKind(token.kind() as u16);
                    builder.token(token_kind, token.text());
                }
            }
        }
    }
    
    builder.finish_node();
    Ok(())
}

fn create_replacement_string_node(_builder: &mut GreenNodeBuilder, new_value: &str) -> Result<(), String> {
    println!("🔧 Creating replacement string: {}", new_value);
    
    // Create string node structure: NODE_STRING containing three tokens
    let string_node_kind = rowan::SyntaxKind(SyntaxKind::NODE_STRING as u16);
    _builder.start_node(string_node_kind);
    
    // Add the three tokens that make up a string literal
    _builder.token(rowan::SyntaxKind(SyntaxKind::TOKEN_STRING_START as u16), "\"");
    _builder.token(rowan::SyntaxKind(SyntaxKind::TOKEN_STRING_CONTENT as u16), new_value);
    _builder.token(rowan::SyntaxKind(SyntaxKind::TOKEN_STRING_END as u16), "\"");
    
    _builder.finish_node();
    Ok(())
}

fn copy_node_unchanged(builder: &mut GreenNodeBuilder, node: &SyntaxNode) {
    // This is the critical research question: How do we efficiently copy an unchanged node?
    // 
    // Approach 1: Reconstruct it token by token (slower but should work)
    // Approach 2: Copy the green node directly (faster, need to research how)
    
    // For now, use approach 1 - reconstruct token by token
    reconstruct_node_exactly(builder, node);
}

fn reconstruct_node_exactly(builder: &mut GreenNodeBuilder, node: &SyntaxNode) {
    let kind = node.kind();
    let rowan_kind = rowan::SyntaxKind(kind as u16);
    
    builder.start_node(rowan_kind);
    
    // Add all children with tokens in exact order
    for child in node.children_with_tokens() {
        match child {
            NodeOrToken::Node(child_node) => {
                reconstruct_node_exactly(builder, &child_node);
            },
            NodeOrToken::Token(token) => {
                let token_kind = rowan::SyntaxKind(token.kind() as u16);
                builder.token(token_kind, token.text());
            }
        }
    }
    
    builder.finish_node();
}

fn validate_selective_replacement(original: &SyntaxNode, result: &SyntaxNode, expected_new_value: &str) {
    println!("\n🧪 Validating selective replacement...");
    
    let original_text = original.text().to_string();
    let result_text = result.text().to_string();
    
    println!("Original: {}", original_text);
    println!("Result:   {}", result_text);
    
    // Check that the new value appears in the result
    if result_text.contains(expected_new_value) {
        println!("✅ New value found in result");
    } else {
        println!("❌ New value not found in result");
    }
    
    // Check that the structure is preserved (same token count, etc.)
    // This is a basic validation - in a real implementation we'd be more thorough
    if original_text.len() != result_text.len() {
        println!("ℹ️  Text length changed: {} -> {} (expected for URL replacement)", 
                original_text.len(), result_text.len());
    }
}

/// Test the complete selective reconstruction workflow
pub fn test_selective_reconstruction() {
    println!("=== Testing Complete Selective Reconstruction Workflow ===");
    
    // Test with a realistic flake input structure
    let test_flake = r#"{ inputs = { home-manager = { url = "git+file:///home/tim/src/home-manager?ref=feature"; inputs.nixpkgs.follows = "nixpkgs"; }; }; }"#;
    
    println!("Test flake: {}", test_flake);
    
    let parse_result = Root::parse(test_flake);
    let tree = parse_result.tree();
    
    if let Some(expr) = tree.expr() {
        println!("✅ Parsed test flake");
        
        // Test selective reconstruction
        test_url_replacement_in_complex_structure(expr.syntax(), "git+file:///home/tim/src/home-manager?ref=feature", "github:nix-community/home-manager");
    } else {
        println!("❌ Failed to parse test flake");
    }
}

fn test_url_replacement_in_complex_structure(node: &SyntaxNode, old_url: &str, new_url: &str) {
    println!("\n🎯 Testing URL replacement in complex structure...");
    println!("Replacing: {} -> {}", old_url, new_url);
    
    if let Some(path) = find_url_string_path(node, old_url) {
        println!("✅ Found target URL at path: {:?}", path);
        
        // Attempt the replacement
        let mut builder = GreenNodeBuilder::new();
        
        if reconstruct_with_replacement(&mut builder, node, &path, 0, new_url).is_ok() {
            let result = builder.finish();
            let new_syntax_node = SyntaxNode::new_root(result);
            let result_text = new_syntax_node.text().to_string();
            
            println!("✅ Replacement successful!");
            println!("Result: {}", result_text);
            
            // Validate the replacement
            if result_text.contains(new_url) && !result_text.contains(old_url) {
                println!("✅ URL replacement validated!");
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
        println!("❌ Could not find target URL in structure");
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_green_node_copying_research() {
        research_green_node_copying();
    }
    
    #[test]
    fn test_complete_selective_reconstruction() {
        test_selective_reconstruction();
    }
}