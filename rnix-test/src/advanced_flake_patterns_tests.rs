use std::fs;
use rnix::{Root, SyntaxKind};
use rowan::{GreenNodeBuilder, ast::AstNode};
use crate::selective_reconstruction::{find_url_string_path, reconstruct_with_replacement};

/// Advanced flake pattern tests based on real-world usage research
/// 
/// This module tests edge cases and complex patterns found in production Nix flakes:
/// 1. Git+SSH URLs with parameters
/// 2. FlakeHub URLs
/// 3. Subdirectory references  
/// 4. Tarball URLs
/// 5. flake-parts modular patterns
/// 6. Complex follows chains
/// 7. Non-flake inputs
/// 8. Commented and conditional inputs

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_git_ssh_urls_with_parameters() {
        let input = r#"{
  inputs = {
    nixpkgs.url = "git+ssh://git@github.com/NixOS/nixpkgs.git?shallow=1&ref=nixos-unstable";
    private-repo = {
      url = "git+ssh://git@github.com/company/private-repo.git?shallow=1";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };
}"#;
        
        let parse_result = Root::parse(input);
        let tree = parse_result.tree();
        
        if let Some(expr) = tree.expr() {
            let node = expr.syntax();
            
            // Test replacing private repo URL while preserving parameters
            if let Some(path) = find_url_string_path(node, "git+ssh://git@github.com/company/private-repo.git?shallow=1") {
                let mut builder = GreenNodeBuilder::new();
                
                assert!(reconstruct_with_replacement(&mut builder, node, &path, 0, "git+ssh://git@github.com/newcompany/repo.git?shallow=1").is_ok());
                
                let result = builder.finish();
                let new_tree = rnix::SyntaxNode::new_root(result);
                let result_text = new_tree.text().to_string();
                
                // Verify URL change
                assert!(result_text.contains("git+ssh://git@github.com/newcompany/repo.git?shallow=1"));
                assert!(!result_text.contains("company/private-repo"));
                
                // Verify other URLs unchanged
                assert!(result_text.contains("git+ssh://git@github.com/NixOS/nixpkgs.git?shallow=1&ref=nixos-unstable"));
                
                // Verify structure preservation
                assert!(result_text.contains("inputs.nixpkgs.follows"));
                
                // Validate syntax
                let validation_result = Root::parse(&result_text);
                let errors: Vec<_> = validation_result.errors().into_iter().collect();
                assert!(errors.is_empty(), "Syntax errors after SSH URL replacement: {:?}", errors);
            } else {
                panic!("Could not find SSH URL in structure");
            }
        } else {
            panic!("Could not parse SSH URL flake");
        }
    }
    
    #[test]
    fn test_flakehub_urls() {
        let input = r#"{
  inputs = {
    nixpkgs.url = "https://flakehub.com/f/NixOS/nixpkgs/0.1.*.tar.gz";
    determinate = {
      url = "https://flakehub.com/f/DeterminateSystems/determinate/1.0.0.tar.gz";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };
}"#;
        
        let parse_result = Root::parse(input);
        let tree = parse_result.tree();
        
        if let Some(expr) = tree.expr() {
            let node = expr.syntax();
            
            if let Some(path) = find_url_string_path(node, "https://flakehub.com/f/DeterminateSystems/determinate/1.0.0.tar.gz") {
                let mut builder = GreenNodeBuilder::new();
                
                assert!(reconstruct_with_replacement(&mut builder, node, &path, 0, "https://flakehub.com/f/DeterminateSystems/determinate/2.0.0.tar.gz").is_ok());
                
                let result = builder.finish();
                let new_tree = rnix::SyntaxNode::new_root(result);
                let result_text = new_tree.text().to_string();
                
                // Verify version update
                assert!(result_text.contains("2.0.0.tar.gz"));
                assert!(!result_text.contains("1.0.0.tar.gz"));
                
                // Verify other FlakeHub URL unchanged
                assert!(result_text.contains("https://flakehub.com/f/NixOS/nixpkgs/0.1.*.tar.gz"));
                
                // Validate syntax
                let validation_result = Root::parse(&result_text);
                let errors: Vec<_> = validation_result.errors().into_iter().collect();
                assert!(errors.is_empty());
            } else {
                panic!("Could not find FlakeHub URL");
            }
        } else {
            panic!("Could not parse FlakeHub flake");
        }
    }
    
    #[test]
    fn test_subdirectory_references() {
        let input = r#"{
  inputs = {
    subdir-flake = {
      url = "github:user/monorepo?dir=packages/flake1";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    another-subdir = {
      url = "git+file:///home/user/src/repo?dir=subproject&ref=main";
    };
  };
}"#;
        
        let parse_result = Root::parse(input);
        let tree = parse_result.tree();
        
        if let Some(expr) = tree.expr() {
            let node = expr.syntax();
            
            if let Some(path) = find_url_string_path(node, "github:user/monorepo?dir=packages/flake1") {
                let mut builder = GreenNodeBuilder::new();
                
                assert!(reconstruct_with_replacement(&mut builder, node, &path, 0, "github:newuser/monorepo?dir=packages/flake1").is_ok());
                
                let result = builder.finish();
                let new_tree = rnix::SyntaxNode::new_root(result);
                let result_text = new_tree.text().to_string();
                
                // Verify user change while preserving subdirectory
                assert!(result_text.contains("github:newuser/monorepo?dir=packages/flake1"));
                assert!(!result_text.contains("github:user/monorepo"));
                
                // Verify other subdirectory URL unchanged
                assert!(result_text.contains("git+file:///home/user/src/repo?dir=subproject&ref=main"));
                
                // Validate syntax
                let validation_result = Root::parse(&result_text);
                let errors: Vec<_> = validation_result.errors().into_iter().collect();
                assert!(errors.is_empty());
            } else {
                panic!("Could not find subdirectory URL");
            }
        } else {
            panic!("Could not parse subdirectory flake");
        }
    }
    
    #[test]
    fn test_tarball_urls() {
        let input = r#"{
  inputs = {
    archived-version = {
      url = "https://github.com/user/repo/archive/refs/tags/v1.0.tar.gz";
      flake = false;
    };
    release-tarball.url = "https://releases.example.com/project/v2.0.0.tar.gz";
  };
}"#;
        
        let parse_result = Root::parse(input);
        let tree = parse_result.tree();
        
        if let Some(expr) = tree.expr() {
            let node = expr.syntax();
            
            if let Some(path) = find_url_string_path(node, "https://github.com/user/repo/archive/refs/tags/v1.0.tar.gz") {
                let mut builder = GreenNodeBuilder::new();
                
                assert!(reconstruct_with_replacement(&mut builder, node, &path, 0, "https://github.com/user/repo/archive/refs/tags/v2.0.tar.gz").is_ok());
                
                let result = builder.finish();
                let new_tree = rnix::SyntaxNode::new_root(result);
                let result_text = new_tree.text().to_string();
                
                // Verify version update
                assert!(result_text.contains("v2.0.tar.gz"));
                assert!(!result_text.contains("v1.0.tar.gz"));
                
                // Verify non-flake attribute preserved
                assert!(result_text.contains("flake = false"));
                
                // Verify other tarball URL unchanged
                assert!(result_text.contains("https://releases.example.com/project/v2.0.0.tar.gz"));
                
                // Validate syntax
                let validation_result = Root::parse(&result_text);
                let errors: Vec<_> = validation_result.errors().into_iter().collect();
                assert!(errors.is_empty());
            } else {
                panic!("Could not find tarball URL");
            }
        } else {
            panic!("Could not parse tarball flake");
        }
    }
    
    #[test]
    fn test_complex_follows_chains() {
        let input = r#"{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.utils.follows = "flake-utils";
    };
    
    nested-tool = {
      url = "github:example/tool";
      inputs.nixpkgs.follows = "home-manager/nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };
  };
}"#;
        
        let parse_result = Root::parse(input);
        let tree = parse_result.tree();
        
        if let Some(expr) = tree.expr() {
            let node = expr.syntax();
            
            if let Some(path) = find_url_string_path(node, "github:example/tool") {
                let mut builder = GreenNodeBuilder::new();
                
                assert!(reconstruct_with_replacement(&mut builder, node, &path, 0, "github:newexample/tool").is_ok());
                
                let result = builder.finish();
                let new_tree = rnix::SyntaxNode::new_root(result);
                let result_text = new_tree.text().to_string();
                
                // Verify URL change
                assert!(result_text.contains("github:newexample/tool"));
                assert!(!result_text.contains("github:example/tool"));
                
                // Verify complex follows chains preserved
                assert!(result_text.contains("inputs.nixpkgs.follows = \"home-manager/nixpkgs\""));
                assert!(result_text.contains("inputs.home-manager.follows = \"home-manager\""));
                assert!(result_text.contains("inputs.utils.follows = \"flake-utils\""));
                
                // Validate syntax
                let validation_result = Root::parse(&result_text);
                let errors: Vec<_> = validation_result.errors().into_iter().collect();
                assert!(errors.is_empty());
            } else {
                panic!("Could not find tool URL in complex follows structure");
            }
        } else {
            panic!("Could not parse complex follows flake");
        }
    }
    
    #[test]
    fn test_flake_parts_modular_pattern() {
        let input = r#"{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    
    # Development dependencies
    devenv = {
      url = "github:cachix/devenv";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };
  
  outputs = inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [
        ./flake-modules/systems.nix
        ./flake-modules/packages.nix
      ];
    };
}"#;
        
        let parse_result = Root::parse(input);
        let tree = parse_result.tree();
        
        if let Some(expr) = tree.expr() {
            let node = expr.syntax();
            
            if let Some(path) = find_url_string_path(node, "github:cachix/devenv") {
                let mut builder = GreenNodeBuilder::new();
                
                assert!(reconstruct_with_replacement(&mut builder, node, &path, 0, "github:cachix/devenv-next").is_ok());
                
                let result = builder.finish();
                let new_tree = rnix::SyntaxNode::new_root(result);
                let result_text = new_tree.text().to_string();
                
                // Verify URL change
                assert!(result_text.contains("github:cachix/devenv-next"));
                assert!(!result_text.contains("github:cachix/devenv\""));
                
                // Verify flake-parts structure preserved
                assert!(result_text.contains("flake-parts.lib.mkFlake"));
                assert!(result_text.contains("./flake-modules/systems.nix"));
                assert!(result_text.contains("inputs.nixpkgs.follows = \"nixpkgs\""));
                
                // Verify comments preserved
                assert!(result_text.contains("# Development dependencies"));
                
                // Validate syntax
                let validation_result = Root::parse(&result_text);
                let errors: Vec<_> = validation_result.errors().into_iter().collect();
                assert!(errors.is_empty());
            } else {
                panic!("Could not find devenv URL in flake-parts structure");
            }
        } else {
            panic!("Could not parse flake-parts flake");
        }
    }
    
    #[test]
    fn test_non_flake_inputs() {
        let input = r#"{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    
    # Non-flake source dependencies
    vim-config = {
      url = "github:user/vim-config";
      flake = false;
    };
    
    dotfiles = {
      url = "git+file:///home/user/dotfiles";
      flake = false;
    };
  };
}"#;
        
        let parse_result = Root::parse(input);
        let tree = parse_result.tree();
        
        if let Some(expr) = tree.expr() {
            let node = expr.syntax();
            
            if let Some(path) = find_url_string_path(node, "git+file:///home/user/dotfiles") {
                let mut builder = GreenNodeBuilder::new();
                
                assert!(reconstruct_with_replacement(&mut builder, node, &path, 0, "git+file:///home/newuser/dotfiles").is_ok());
                
                let result = builder.finish();
                let new_tree = rnix::SyntaxNode::new_root(result);
                let result_text = new_tree.text().to_string();
                
                // Verify URL change
                assert!(result_text.contains("git+file:///home/newuser/dotfiles"));
                assert!(!result_text.contains("git+file:///home/user/dotfiles"));
                
                // Verify non-flake attributes preserved
                assert!(result_text.contains("flake = false"));
                
                // Verify other non-flake input unchanged
                assert!(result_text.contains("github:user/vim-config"));
                
                // Verify comments preserved
                assert!(result_text.contains("# Non-flake source dependencies"));
                
                // Validate syntax
                let validation_result = Root::parse(&result_text);
                let errors: Vec<_> = validation_result.errors().into_iter().collect();
                assert!(errors.is_empty());
            } else {
                panic!("Could not find dotfiles URL");
            }
        } else {
            panic!("Could not parse non-flake inputs");
        }
    }
    
    #[test]
    fn test_conditional_and_commented_inputs() {
        let input = r#"{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    
    # Production dependencies
    stable-tool.url = "github:vendor/stable-tool";
    
    # Temporarily disabled for testing
    # experimental-tool.url = "github:vendor/experimental-tool";
    
    development-tool = {
      url = "github:vendor/dev-tool";
      # inputs.nixpkgs.follows = "nixpkgs"; # Enable for stable builds
    };
  };
}"#;
        
        let parse_result = Root::parse(input);
        let tree = parse_result.tree();
        
        if let Some(expr) = tree.expr() {
            let node = expr.syntax();
            
            if let Some(path) = find_url_string_path(node, "github:vendor/stable-tool") {
                let mut builder = GreenNodeBuilder::new();
                
                assert!(reconstruct_with_replacement(&mut builder, node, &path, 0, "github:newvendor/stable-tool").is_ok());
                
                let result = builder.finish();
                let new_tree = rnix::SyntaxNode::new_root(result);
                let result_text = new_tree.text().to_string();
                
                // Verify URL change
                assert!(result_text.contains("github:newvendor/stable-tool"));
                assert!(!result_text.contains("github:vendor/stable-tool"));
                
                // Verify commented content preserved exactly
                assert!(result_text.contains("# experimental-tool.url = \"github:vendor/experimental-tool\";"));
                assert!(result_text.contains("# inputs.nixpkgs.follows = \"nixpkgs\"; # Enable for stable builds"));
                
                // Verify section comments preserved
                assert!(result_text.contains("# Production dependencies"));
                assert!(result_text.contains("# Temporarily disabled for testing"));
                
                // Verify other URLs unchanged (including commented ones)
                assert!(result_text.contains("github:vendor/dev-tool"));
                assert!(result_text.contains("github:vendor/experimental-tool"));
                
                // Validate syntax
                let validation_result = Root::parse(&result_text);
                let errors: Vec<_> = validation_result.errors().into_iter().collect();
                assert!(errors.is_empty());
            } else {
                panic!("Could not find stable-tool URL");
            }
        } else {
            panic!("Could not parse conditional/commented flake");
        }
    }
    
    #[test]
    fn test_real_world_complex_flake() {
        // Test with an actual complex flake pattern combining multiple advanced features
        let input = r#"{
  description = "Complex multi-repo development environment";
  
  inputs = {
    # Core dependencies
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixpkgs-stable.url = "github:NixOS/nixpkgs/nixos-24.11";
    
    # Flake framework
    flake-parts.url = "github:hercules-ci/flake-parts";
    
    # Development tools with complex follows
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    
    devenv = {
      url = "github:cachix/devenv/latest";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-parts.follows = "flake-parts";
    };
    
    # Local development repositories
    my-lib = {
      url = "git+file:///home/dev/src/my-lib?ref=feature-branch";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    
    # Non-flake dependencies
    config-files = {
      url = "git+ssh://git@private.com/configs.git?shallow=1";
      flake = false;
    };
    
    # External tools with subdirectories
    monorepo-tool = {
      url = "github:company/monorepo?dir=tools/nix-tool&ref=main";
      inputs.nixpkgs.follows = "home-manager/nixpkgs";
    };
  };
  
  outputs = inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [
        ./flake-modules/systems.nix
        ./flake-modules/dev-shells.nix
      ];
    };
}"#;
        
        let parse_result = Root::parse(input);
        let tree = parse_result.tree();
        
        if let Some(expr) = tree.expr() {
            let node = expr.syntax();
            
            // Test replacing the local development repository
            if let Some(path) = find_url_string_path(node, "git+file:///home/dev/src/my-lib?ref=feature-branch") {
                let mut builder = GreenNodeBuilder::new();
                
                assert!(reconstruct_with_replacement(&mut builder, node, &path, 0, "git+file:///home/dev/src/my-lib?ref=main").is_ok());
                
                let result = builder.finish();
                let new_tree = rnix::SyntaxNode::new_root(result);
                let result_text = new_tree.text().to_string();
                
                // Verify specific URL change
                assert!(result_text.contains("git+file:///home/dev/src/my-lib?ref=main"));
                assert!(!result_text.contains("git+file:///home/dev/src/my-lib?ref=feature-branch"));
                
                // Verify all other complex patterns preserved
                assert!(result_text.contains("github:cachix/devenv/latest"));
                assert!(result_text.contains("git+ssh://git@private.com/configs.git?shallow=1"));
                assert!(result_text.contains("github:company/monorepo?dir=tools/nix-tool&ref=main"));
                assert!(result_text.contains("inputs.nixpkgs.follows = \"home-manager/nixpkgs\""));
                assert!(result_text.contains("flake = false"));
                
                // Verify flake-parts structure preserved
                assert!(result_text.contains("flake-parts.lib.mkFlake"));
                assert!(result_text.contains("./flake-modules/systems.nix"));
                
                // Verify description and comments preserved
                assert!(result_text.contains("Complex multi-repo development environment"));
                assert!(result_text.contains("# Core dependencies"));
                assert!(result_text.contains("# Non-flake dependencies"));
                
                // Validate syntax
                let validation_result = Root::parse(&result_text);
                let errors: Vec<_> = validation_result.errors().into_iter().collect();
                assert!(errors.is_empty(), "Syntax errors in complex flake: {:?}", errors);
            } else {
                panic!("Could not find my-lib URL in complex flake");
            }
        } else {
            panic!("Could not parse complex real-world flake");
        }
    }
}