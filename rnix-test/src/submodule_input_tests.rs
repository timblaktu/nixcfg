use crate::selective_reconstruction::{find_url_string_path, reconstruct_with_replacement};
use rnix::{Root, SyntaxNode};
use rowan::{GreenNodeBuilder, ast::AstNode};

#[test]
fn test_submodule_url_parameters() {
    let input = r#"{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    
    # Git repository with submodules enabled
    project-with-submodules = {
      url = "git+https://github.com/user/project?submodules=1";
      flake = true;
    };
    
    # Another repository with submodules and ref
    repo-with-subs-and-ref = {
      url = "git+https://github.com/org/repo?submodules=1&ref=main";
      flake = true;
    };
  };
}"#;

    let parse_result = Root::parse(input);
    assert!(parse_result.errors().is_empty(), "Parse errors: {:?}", parse_result.errors());
    
    if let Some(expr) = parse_result.tree().expr() {
        let node = expr.syntax();
        
        // Test replacement of URL with submodules parameter
        if let Some(path) = find_url_string_path(node, "git+https://github.com/user/project?submodules=1") {
            let mut builder = GreenNodeBuilder::new();
            assert!(reconstruct_with_replacement(&mut builder, node, &path, 0, "git+file:///local/project?submodules=1").is_ok());
            
            let result = builder.finish();
            let new_tree = SyntaxNode::new_root(result);
            let result_text = new_tree.text().to_string();
            
            // Verify replacement occurred while preserving structure
            assert!(result_text.contains("git+file:///local/project?submodules=1"));
            assert!(!result_text.contains("git+https://github.com/user/project?submodules=1"));
            
            // Verify other URL with submodules remains unchanged
            assert!(result_text.contains("git+https://github.com/org/repo?submodules=1&ref=main"));
            
            // Verify flake attributes preserved
            assert!(result_text.contains("flake = true;"));
            
            // Verify syntax is valid
            let validation = Root::parse(&result_text);
            assert!(validation.errors().is_empty(), "Result syntax errors: {:?}", validation.errors());
        } else {
            panic!("Failed to find URL path for submodule URL");
        }
    } else {
        panic!("Failed to parse expression");
    }
}

#[test]
fn test_manual_submodule_inputs() {
    let input = r#"{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    
    # Local submodule reference (non-flake)
    config-submodule = {
      url = "./config";
      flake = false;
    };
    
    # Local path with subdirectory
    docs-submodule = {
      url = "./docs/guide"; 
      flake = false;
    };
    
    # Git submodule reference
    external-config = {
      url = "git+https://github.com/team/config?dir=modules";
      flake = false;
    };
  };
}"#;

    let parse_result = Root::parse(input);
    assert!(parse_result.errors().is_empty(), "Parse errors: {:?}", parse_result.errors());
    
    if let Some(expr) = parse_result.tree().expr() {
        let node = expr.syntax();
        
        // Test replacement of local submodule path
        if let Some(path) = find_url_string_path(node, "./config") {
            let mut builder = GreenNodeBuilder::new();
            assert!(reconstruct_with_replacement(&mut builder, node, &path, 0, "./new-config").is_ok());
            
            let result = builder.finish();
            let new_tree = SyntaxNode::new_root(result);
            let result_text = new_tree.text().to_string();
            
            // Verify replacement occurred
            assert!(result_text.contains("./new-config"));
            assert!(!result_text.contains("url = \"./config\""));
            
            // Verify other local paths unchanged
            assert!(result_text.contains("./docs/guide"));
            
            // Verify flake = false preserved
            assert!(result_text.contains("flake = false;"));
            
            // Verify git URL with dir parameter unchanged
            assert!(result_text.contains("git+https://github.com/team/config?dir=modules"));
            
            // Verify syntax is valid
            let validation = Root::parse(&result_text);
            assert!(validation.errors().is_empty(), "Result syntax errors: {:?}", validation.errors());
        } else {
            panic!("Failed to find URL path for local submodule");
        }
    } else {
        panic!("Failed to parse expression");
    }
}

#[test]
fn test_local_submodule_references() {
    let input = r#"{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    
    # File-based submodule with parameters
    local-with-subs = {
      url = "git+file:///home/user/repo?submodules=1&ref=main";
      flake = true;
    };
    
    # Local git repository with submodules
    local-git-repo = {
      url = "git+file:///opt/projects/myproject?submodules=1";
      flake = true;
    };
    
    # Complex local with multiple parameters
    complex-local = {
      url = "git+file:///workspace/project?submodules=1&ref=develop&dir=packages";
      flake = true;
    };
  };
}"#;

    let parse_result = Root::parse(input);
    assert!(parse_result.errors().is_empty(), "Parse errors: {:?}", parse_result.errors());
    
    if let Some(expr) = parse_result.tree().expr() {
        let node = expr.syntax();
        
        // Test replacement of complex local URL with multiple parameters
        if let Some(path) = find_url_string_path(node, "git+file:///workspace/project?submodules=1&ref=develop&dir=packages") {
            let mut builder = GreenNodeBuilder::new();
            assert!(reconstruct_with_replacement(&mut builder, node, &path, 0, "git+file:///new-workspace/project?submodules=1&ref=develop&dir=packages").is_ok());
            
            let result = builder.finish();
            let new_tree = SyntaxNode::new_root(result);
            let result_text = new_tree.text().to_string();
            
            // Verify replacement occurred with parameter preservation
            assert!(result_text.contains("git+file:///new-workspace/project?submodules=1&ref=develop&dir=packages"));
            assert!(!result_text.contains("git+file:///workspace/project?submodules=1&ref=develop&dir=packages"));
            
            // Verify other local git URLs unchanged
            assert!(result_text.contains("git+file:///home/user/repo?submodules=1&ref=main"));
            assert!(result_text.contains("git+file:///opt/projects/myproject?submodules=1"));
            
            // Verify syntax is valid
            let validation = Root::parse(&result_text);
            assert!(validation.errors().is_empty(), "Result syntax errors: {:?}", validation.errors());
        } else {
            panic!("Failed to find URL path for complex local submodule");
        }
    } else {
        panic!("Failed to parse expression");
    }
}

#[test]
fn test_nested_submodule_patterns() {
    let input = r#"{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    
    # Main project flake
    main-project = {
      url = "git+https://github.com/org/main?submodules=1";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    
    # Dependency with submodules 
    project-deps = {
      url = "git+https://github.com/org/deps?submodules=1&ref=v2.0";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        utils.follows = "main-project/utils";
      };
    };
    
    # Local development with submodules
    dev-env = {
      url = "git+file:///home/dev/environment?submodules=1";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };
}"#;

    let parse_result = Root::parse(input);
    assert!(parse_result.errors().is_empty(), "Parse errors: {:?}", parse_result.errors());
    
    if let Some(expr) = parse_result.tree().expr() {
        let node = expr.syntax();
        
        // Test replacement of nested project URL
        if let Some(path) = find_url_string_path(node, "git+https://github.com/org/deps?submodules=1&ref=v2.0") {
            let mut builder = GreenNodeBuilder::new();
            assert!(reconstruct_with_replacement(&mut builder, node, &path, 0, "git+https://github.com/org/deps?submodules=1&ref=v2.1").is_ok());
            
            let result = builder.finish();
            let new_tree = SyntaxNode::new_root(result);
            let result_text = new_tree.text().to_string();
            
            // Verify replacement occurred
            assert!(result_text.contains("git+https://github.com/org/deps?submodules=1&ref=v2.1"));
            assert!(!result_text.contains("git+https://github.com/org/deps?submodules=1&ref=v2.0"));
            
            // Verify follows structures preserved
            assert!(result_text.contains("inputs.nixpkgs.follows = \"nixpkgs\";"));
            assert!(result_text.contains("utils.follows = \"main-project/utils\";"));
            
            // Verify other submodule URLs unchanged
            assert!(result_text.contains("git+https://github.com/org/main?submodules=1"));
            assert!(result_text.contains("git+file:///home/dev/environment?submodules=1"));
            
            // Verify syntax is valid
            let validation = Root::parse(&result_text);
            assert!(validation.errors().is_empty(), "Result syntax errors: {:?}", validation.errors());
        } else {
            panic!("Failed to find URL path for nested submodule pattern");
        }
    } else {
        panic!("Failed to parse expression");
    }
}

#[test]
fn test_submodule_error_handling() {
    let input = r#"{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    
    # Valid submodule URL
    valid-submodule = {
      url = "git+https://github.com/user/valid?submodules=1";
      flake = true;
    };
    
    # Another valid URL
    another-valid = {
      url = "git+file:///local/repo?submodules=1";
      flake = true;
    };
  };
}"#;

    let parse_result = Root::parse(input);
    assert!(parse_result.errors().is_empty(), "Parse errors: {:?}", parse_result.errors());
    
    if let Some(expr) = parse_result.tree().expr() {
        let node = expr.syntax();
        
        // Test search for non-existent URL returns None gracefully
        let non_existent_path = find_url_string_path(node, "git+https://github.com/nonexistent/repo?submodules=1");
        assert!(non_existent_path.is_none(), "Should not find non-existent URL");
        
        // Test that valid URLs can still be found and replaced
        if let Some(path) = find_url_string_path(node, "git+https://github.com/user/valid?submodules=1") {
            let mut builder = GreenNodeBuilder::new();
            let result = reconstruct_with_replacement(&mut builder, node, &path, 0, "git+https://github.com/user/updated?submodules=1");
            assert!(result.is_ok(), "Reconstruction should succeed for valid path");
            
            let new_tree = SyntaxNode::new_root(builder.finish());
            let result_text = new_tree.text().to_string();
            
            // Verify replacement worked
            assert!(result_text.contains("git+https://github.com/user/updated?submodules=1"));
            assert!(!result_text.contains("git+https://github.com/user/valid?submodules=1"));
            
            // Verify other URL unchanged
            assert!(result_text.contains("git+file:///local/repo?submodules=1"));
            
            // Verify syntax is valid
            let validation = Root::parse(&result_text);
            assert!(validation.errors().is_empty(), "Result syntax should be valid");
        } else {
            panic!("Should find valid submodule URL");
        }
    } else {
        panic!("Failed to parse expression");
    }
}