use rnix::{Root, SyntaxKind, SyntaxNode};
use rowan::{GreenNodeBuilder, ast::AstNode, NodeOrToken};

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
        create_replacement_string_node(builder, new_value)?;
        return Ok(());
    }
    
    // Not the target - copy this node and process children/tokens
    builder.start_node(rowan_kind);
    
    // Process children_with_tokens to preserve all tokens (whitespace, operators, etc.)
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

fn create_replacement_string_node(builder: &mut GreenNodeBuilder, new_value: &str) -> Result<(), String> {
    // Create string node structure: NODE_STRING containing three tokens
    let string_node_kind = rowan::SyntaxKind(SyntaxKind::NODE_STRING as u16);
    builder.start_node(string_node_kind);
    
    // Add the three tokens that make up a string literal
    builder.token(rowan::SyntaxKind(SyntaxKind::TOKEN_STRING_START as u16), "\"");
    builder.token(rowan::SyntaxKind(SyntaxKind::TOKEN_STRING_CONTENT as u16), new_value);
    builder.token(rowan::SyntaxKind(SyntaxKind::TOKEN_STRING_END as u16), "\"");
    
    builder.finish_node();
    Ok(())
}

fn copy_node_unchanged(builder: &mut GreenNodeBuilder, node: &SyntaxNode) {
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

/// Public API function to replace a URL in a flake.nix file
pub fn replace_flake_input_url(flake_content: &str, input_name: &str, old_url: &str, new_url: &str) -> Result<String, String> {
    let parse_result = Root::parse(flake_content);
    let tree = parse_result.tree();
    
    if let Some(expr) = tree.expr() {
        // Find the target URL string
        if let Some(path) = find_url_string_path(expr.syntax(), old_url) {
            // Perform the replacement
            let mut builder = GreenNodeBuilder::new();
            
            if reconstruct_with_replacement(&mut builder, expr.syntax(), &path, 0, new_url).is_ok() {
                let result = builder.finish();
                let new_syntax_node = SyntaxNode::new_root(result);
                return Ok(new_syntax_node.text().to_string());
            } else {
                return Err("Failed to reconstruct with replacement".to_string());
            }
        } else {
            return Err(format!("URL '{}' not found in flake content", old_url));
        }
    } else {
        return Err("Failed to parse flake content".to_string());
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_simple_url_replacement() {
        let flake_content = r#"{ inputs = { nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable"; }; }"#;
        let result = replace_flake_input_url(
            flake_content, 
            "nixpkgs", 
            "github:NixOS/nixpkgs/nixos-unstable", 
            "git+file:///home/tim/src/nixpkgs"
        ).unwrap();
        
        assert!(result.contains("git+file:///home/tim/src/nixpkgs"));
        assert!(!result.contains("github:NixOS/nixpkgs/nixos-unstable"));
    }
    
    #[test]
    fn test_complex_url_replacement() {
        let flake_content = r#"{ inputs = { home-manager = { url = "github:nix-community/home-manager"; inputs.nixpkgs.follows = "nixpkgs"; }; }; }"#;
        let result = replace_flake_input_url(
            flake_content,
            "home-manager",
            "github:nix-community/home-manager",
            "git+file:///home/tim/src/home-manager?ref=feature"
        ).unwrap();
        
        assert!(result.contains("git+file:///home/tim/src/home-manager?ref=feature"));
        assert!(!result.contains("github:nix-community/home-manager"));
        assert!(result.contains("inputs.nixpkgs.follows = \"nixpkgs\""));
    }
}