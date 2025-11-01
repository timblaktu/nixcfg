use crate::selective_reconstruction::{find_url_string_path, reconstruct_with_replacement};
use rnix::{Root, SyntaxNode};
use rowan::{GreenNodeBuilder, ast::AstNode};

/// Test direct flake reference pattern where one flake references another repository that is itself a flake
#[test]
fn test_direct_flake_reference() {
    let input = r#"{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    devenv = {
      url = "github:cachix/devenv";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Another flake that has its own input system
    dotfiles = {
      url = "github:user/dotfiles";
      # This dotfiles repository is itself a flake with inputs
    };
  };
}"#;

    let parse_result = Root::parse(input);
    assert!(parse_result.errors().is_empty(), "Parse errors: {:?}", parse_result.errors());
    
    if let Some(expr) = parse_result.tree().expr() {
        let node = expr.syntax();
        
        // Test replacing the devenv URL (nested flake with follows)
        if let Some(path) = find_url_string_path(node, "github:cachix/devenv") {
            let mut builder = GreenNodeBuilder::new();
            assert!(reconstruct_with_replacement(&mut builder, node, &path, 0, "git+file:///home/tim/src/devenv").is_ok());
            
            let result = builder.finish();
            let new_tree = SyntaxNode::new_root(result);
            let result_text = new_tree.text().to_string();
            
            // Verify replacement occurred
            assert!(result_text.contains("git+file:///home/tim/src/devenv"));
            assert!(!result_text.contains("github:cachix/devenv"));
            
            // Verify follows structure preserved
            assert!(result_text.contains("inputs.nixpkgs.follows = \"nixpkgs\""));
            
            // Verify other inputs preserved
            assert!(result_text.contains("github:NixOS/nixpkgs/nixos-unstable"));
            assert!(result_text.contains("github:user/dotfiles"));
            
            // Verify syntax is valid
            let reparse = Root::parse(&result_text);
            assert!(reparse.errors().is_empty(), "Reparsing failed: {:?}", reparse.errors());
        } else {
            panic!("Could not find target URL in direct flake reference test");
        }
    }
}

/// Test transitive input chains where flake A depends on flake B which depends on flake C
#[test]
fn test_transitive_input_chains() {
    let input = r#"{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    
    # Flake B - middle of chain
    intermediate-flake = {
      url = "github:user/intermediate";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    
    # Flake A - depends on flake B
    main-flake = {
      url = "github:user/main";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        intermediate.follows = "intermediate-flake";
      };
    };
    
    # Flake C - leaf dependency  
    leaf-flake = {
      url = "github:user/leaf";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };
}"#;

    let parse_result = Root::parse(input);
    assert!(parse_result.errors().is_empty(), "Parse errors: {:?}", parse_result.errors());
    
    if let Some(expr) = parse_result.tree().expr() {
        let node = expr.syntax();
        
        // Test replacing the intermediate flake URL (middle of transitive chain)
        if let Some(path) = find_url_string_path(node, "github:user/intermediate") {
            let mut builder = GreenNodeBuilder::new();
            assert!(reconstruct_with_replacement(&mut builder, node, &path, 0, "git+file:///home/tim/src/intermediate").is_ok());
            
            let result = builder.finish();
            let new_tree = SyntaxNode::new_root(result);
            let result_text = new_tree.text().to_string();
            
            // Verify replacement occurred
            assert!(result_text.contains("git+file:///home/tim/src/intermediate"));
            assert!(!result_text.contains("github:user/intermediate"));
            
            // Verify transitive chain structure preserved
            assert!(result_text.contains("intermediate.follows = \"intermediate-flake\""));
            assert!(result_text.contains("inputs.nixpkgs.follows = \"nixpkgs\""));
            
            // Verify other chain elements preserved
            assert!(result_text.contains("github:user/main"));
            assert!(result_text.contains("github:user/leaf"));
            
            // Verify syntax is valid
            let reparse = Root::parse(&result_text);
            assert!(reparse.errors().is_empty(), "Reparsing failed: {:?}", reparse.errors());
        } else {
            panic!("Could not find target URL in transitive chain test");
        }
    }
}

/// Test complex follows chains with nested path references like mynixpkgs.follows = "dotfiles/nixpkgs"
#[test]
fn test_complex_follows_chains() {
    let input = r#"{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    
    # Primary external flake with its own nixpkgs
    dotfiles = {
      url = "github:user/dotfiles";
      # This dotfiles flake has its own inputs.nixpkgs
    };
    
    # Home manager that follows our main nixpkgs
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    
    # Complex follows pattern - follows nixpkgs from dotfiles flake
    mynixpkgs.follows = "dotfiles/nixpkgs";
    
    # Another complex follows - references home-manager's nixpkgs
    utils = {
      url = "github:numtide/flake-utils";
      inputs.nixpkgs.follows = "home-manager/nixpkgs";
    };
    
    # Multi-level follows chain
    deep-reference.follows = "utils/nixpkgs";
  };
}"#;

    let parse_result = Root::parse(input);
    assert!(parse_result.errors().is_empty(), "Parse errors: {:?}", parse_result.errors());
    
    if let Some(expr) = parse_result.tree().expr() {
        let node = expr.syntax();
        
        // Test replacing the dotfiles URL (source of complex follows reference)
        if let Some(path) = find_url_string_path(node, "github:user/dotfiles") {
            let mut builder = GreenNodeBuilder::new();
            assert!(reconstruct_with_replacement(&mut builder, node, &path, 0, "git+file:///home/tim/src/dotfiles").is_ok());
            
            let result = builder.finish();
            let new_tree = SyntaxNode::new_root(result);
            let result_text = new_tree.text().to_string();
            
            // Verify replacement occurred
            assert!(result_text.contains("git+file:///home/tim/src/dotfiles"));
            assert!(!result_text.contains("github:user/dotfiles"));
            
            // Verify complex follows patterns preserved
            assert!(result_text.contains("mynixpkgs.follows = \"dotfiles/nixpkgs\""));
            assert!(result_text.contains("inputs.nixpkgs.follows = \"home-manager/nixpkgs\""));
            assert!(result_text.contains("deep-reference.follows = \"utils/nixpkgs\""));
            
            // Verify other URLs preserved
            assert!(result_text.contains("github:nix-community/home-manager"));
            assert!(result_text.contains("github:numtide/flake-utils"));
            
            // Verify syntax is valid
            let reparse = Root::parse(&result_text);
            assert!(reparse.errors().is_empty(), "Reparsing failed: {:?}", reparse.errors());
        } else {
            panic!("Could not find target URL in complex follows chain test");
        }
    }
}

/// Test nested flake with multiple levels of input dependencies
#[test]
fn test_multi_level_nested_dependencies() {
    let input = r#"{
  inputs = {
    # Level 0: Base dependencies
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    
    # Level 1: Flakes that depend on base
    devshell = {
      url = "github:numtide/devshell";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-utils.follows = "flake-utils";
      };
    };
    
    # Level 2: Flakes that depend on level 1
    project-template = {
      url = "github:user/project-template";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        devshell.follows = "devshell";
      };
    };
    
    # Level 3: Final consumer that depends on everything
    my-project = {
      url = "github:user/my-project";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        template.follows = "project-template";
        devshell.follows = "devshell";
      };
    };
  };
}"#;

    let parse_result = Root::parse(input);
    assert!(parse_result.errors().is_empty(), "Parse errors: {:?}", parse_result.errors());
    
    if let Some(expr) = parse_result.tree().expr() {
        let node = expr.syntax();
        
        // Test replacing a mid-level dependency (project-template)
        if let Some(path) = find_url_string_path(node, "github:user/project-template") {
            let mut builder = GreenNodeBuilder::new();
            assert!(reconstruct_with_replacement(&mut builder, node, &path, 0, "git+file:///home/tim/src/project-template").is_ok());
            
            let result = builder.finish();
            let new_tree = SyntaxNode::new_root(result);
            let result_text = new_tree.text().to_string();
            
            // Verify replacement occurred
            assert!(result_text.contains("git+file:///home/tim/src/project-template"));
            assert!(!result_text.contains("github:user/project-template"));
            
            // Verify all dependency levels preserved
            assert!(result_text.contains("template.follows = \"project-template\""));
            assert!(result_text.contains("devshell.follows = \"devshell\""));
            assert!(result_text.contains("flake-utils.follows = \"flake-utils\""));
            
            // Verify all other URLs preserved
            assert!(result_text.contains("github:numtide/devshell"));
            assert!(result_text.contains("github:user/my-project"));
            assert!(result_text.contains("github:numtide/flake-utils"));
            
            // Verify syntax is valid
            let reparse = Root::parse(&result_text);
            assert!(reparse.errors().is_empty(), "Reparsing failed: {:?}", reparse.errors());
        } else {
            panic!("Could not find target URL in multi-level dependencies test");
        }
    }
}

/// Test flake references with complex input override patterns
#[test]
fn test_nested_flake_input_overrides() {
    let input = r#"{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    
    # Flake with complex input override structure
    complex-flake = {
      url = "github:user/complex";
      inputs = {
        # Direct override
        nixpkgs.follows = "nixpkgs";
        
        # Nested flake override with its own structure
        sub-flake = {
          url = "github:user/sub";
          inputs.nixpkgs.follows = "nixpkgs";
        };
        
        # Override with path reference
        utils.follows = "sub-flake/flake-utils";
      };
    };
    
    # Another flake that references the complex structure
    consumer = {
      url = "github:user/consumer";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        complex.follows = "complex-flake";
        # Reference nested input from complex flake
        inherited-utils.follows = "complex-flake/sub-flake/flake-utils";
      };
    };
  };
}"#;

    let parse_result = Root::parse(input);
    assert!(parse_result.errors().is_empty(), "Parse errors: {:?}", parse_result.errors());
    
    if let Some(expr) = parse_result.tree().expr() {
        let node = expr.syntax();
        
        // Test replacing the sub-flake URL (nested within complex override structure)
        if let Some(path) = find_url_string_path(node, "github:user/sub") {
            let mut builder = GreenNodeBuilder::new();
            assert!(reconstruct_with_replacement(&mut builder, node, &path, 0, "git+file:///home/tim/src/sub").is_ok());
            
            let result = builder.finish();
            let new_tree = SyntaxNode::new_root(result);
            let result_text = new_tree.text().to_string();
            
            // Verify replacement occurred
            assert!(result_text.contains("git+file:///home/tim/src/sub"));
            assert!(!result_text.contains("github:user/sub"));
            
            // Verify complex override structure preserved
            assert!(result_text.contains("utils.follows = \"sub-flake/flake-utils\""));
            assert!(result_text.contains("inherited-utils.follows = \"complex-flake/sub-flake/flake-utils\""));
            assert!(result_text.contains("complex.follows = \"complex-flake\""));
            
            // Verify other URLs preserved
            assert!(result_text.contains("github:user/complex"));
            assert!(result_text.contains("github:user/consumer"));
            
            // Verify syntax is valid
            let reparse = Root::parse(&result_text);
            assert!(reparse.errors().is_empty(), "Reparsing failed: {:?}", reparse.errors());
        } else {
            panic!("Could not find target URL in nested input overrides test");
        }
    }
}

/// Test error handling with malformed nested patterns
#[test]
fn test_nested_flake_error_handling() {
    let input = r#"{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    
    # Valid nested structure
    valid-nested = {
      url = "github:user/valid";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };
}"#;

    let parse_result = Root::parse(input);
    assert!(parse_result.errors().is_empty(), "Parse errors: {:?}", parse_result.errors());
    
    if let Some(expr) = parse_result.tree().expr() {
        let node = expr.syntax();
        
        // Test looking for non-existent URL in nested structure
        let missing_path = find_url_string_path(node, "github:user/nonexistent");
        assert!(missing_path.is_none(), "Should not find non-existent URL");
        
        // Test successful replacement still works
        if let Some(path) = find_url_string_path(node, "github:user/valid") {
            let mut builder = GreenNodeBuilder::new();
            assert!(reconstruct_with_replacement(&mut builder, node, &path, 0, "git+file:///local/valid").is_ok());
            
            let result = builder.finish();
            let new_tree = SyntaxNode::new_root(result);
            let result_text = new_tree.text().to_string();
            
            // Verify replacement worked correctly
            assert!(result_text.contains("git+file:///local/valid"));
            assert!(!result_text.contains("github:user/valid"));
            
            // Verify structure preserved
            assert!(result_text.contains("inputs.nixpkgs.follows = \"nixpkgs\""));
            
            // Verify syntax is valid
            let reparse = Root::parse(&result_text);
            assert!(reparse.errors().is_empty(), "Reparsing failed: {:?}", reparse.errors());
        } else {
            panic!("Could not find valid URL for error handling test");
        }
    }
}