use crate::selective_reconstruction::{find_url_string_path, reconstruct_with_replacement};
use rnix::{Root, SyntaxNode};
use rowan::{GreenNodeBuilder, ast::AstNode};

#[test]
fn test_module_input_access_pattern() {
    // Test the _module.args.origInputs = inputs pattern for passing inputs to separate modules
    let input = r#"{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    home-manager.url = "github:nix-community/home-manager";
  };
  
  outputs = inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      flake = {
        # Make inputs available to all modules
        _module.args.origInputs = inputs;
      };
      
      imports = [
        ./modules/home-configuration.nix
      ];
      
      systems = [ "x86_64-linux" "aarch64-linux" ];
    };
}"#;

    let parse_result = Root::parse(input);
    assert!(parse_result.errors().is_empty(), "Parse errors: {:?}", parse_result.errors());
    
    let tree = parse_result.tree();
    
    if let Some(expr) = tree.expr() {
        let node = expr.syntax();
        
        // Test replacing the home-manager input URL
        if let Some(path) = find_url_string_path(node, "github:nix-community/home-manager") {
            let mut builder = GreenNodeBuilder::new();
            let replacement_url = "git+file:///home/tim/src/home-manager?ref=feature-test-with-fcitx5-fix";
            
            assert!(reconstruct_with_replacement(&mut builder, node, &path, 0, replacement_url).is_ok());
            
            let result = builder.finish();
            let new_tree = SyntaxNode::new_root(result);
            let result_text = new_tree.text().to_string();
            
            // Verify the URL was replaced
            assert!(result_text.contains(replacement_url));
            assert!(!result_text.contains("github:nix-community/home-manager"));
            
            // Verify the structure is preserved (module args pattern should be intact)
            assert!(result_text.contains("_module.args.origInputs = inputs"));
            assert!(result_text.contains("flake-parts.lib.mkFlake"));
            assert!(result_text.contains("./modules/home-configuration.nix"));
            
            // Verify the result is still valid Nix syntax
            let validation_result = Root::parse(&result_text);
            assert!(validation_result.errors().is_empty(), "Validation errors after replacement: {:?}", validation_result.errors());
        } else {
            panic!("Could not find home-manager URL in module input access pattern");
        }
    } else {
        panic!("Could not parse expression in module input access pattern");
    }
}

#[test]
fn test_persystem_input_distinction_pattern() {
    // Test inputs' vs inputs access patterns within perSystem modules
    let input = r#"{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    crane.url = "github:ipetkov/crane";
  };
  
  outputs = inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [ "x86_64-linux" "aarch64-linux" ];
      
      perSystem = { config, self', inputs', pkgs, system, ... }: {
        # inputs' provides per-system access to input packages
        packages.my-tool = inputs'.crane.packages.default;
        
        # inputs provides raw flake inputs (not per-system)
        devShells.default = pkgs.mkShell {
          buildInputs = [
            inputs.crane.packages.${system}.cargo
            inputs'.nixpkgs.legacyPackages.hello
          ];
        };
      };
    };
}"#;

    let parse_result = Root::parse(input);
    assert!(parse_result.errors().is_empty(), "Parse errors: {:?}", parse_result.errors());
    
    let tree = parse_result.tree();
    
    if let Some(expr) = tree.expr() {
        let node = expr.syntax();
        
        // Test replacing the crane input URL  
        if let Some(path) = find_url_string_path(node, "github:ipetkov/crane") {
            let mut builder = GreenNodeBuilder::new();
            let replacement_url = "git+file:///home/tim/src/crane?ref=custom-features";
            
            assert!(reconstruct_with_replacement(&mut builder, node, &path, 0, replacement_url).is_ok());
            
            let result = builder.finish();
            let new_tree = SyntaxNode::new_root(result);
            let result_text = new_tree.text().to_string();
            
            // Verify the URL was replaced
            assert!(result_text.contains(replacement_url));
            assert!(!result_text.contains("github:ipetkov/crane"));
            
            // Verify perSystem structure is preserved with both input access patterns
            assert!(result_text.contains("inputs'.crane.packages.default"));
            assert!(result_text.contains("inputs.crane.packages.${system}.cargo"));
            assert!(result_text.contains("inputs'.nixpkgs.legacyPackages.hello"));
            
            // Verify the result is still valid Nix syntax
            let validation_result = Root::parse(&result_text);
            assert!(validation_result.errors().is_empty(), "Validation errors after replacement: {:?}", validation_result.errors());
        } else {
            panic!("Could not find crane URL in perSystem input distinction pattern");
        }
    } else {
        panic!("Could not parse expression in perSystem input distinction pattern");
    }
}

#[test]
fn test_custom_module_arguments_pattern() {
    // Test custom pkgs definitions with overlays via module arguments
    let input = r#"{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    rust-overlay.url = "github:oxalica/rust-overlay";
  };
  
  outputs = inputs@{ flake-parts, rust-overlay, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [ "x86_64-linux" "aarch64-linux" ];
      
      perSystem = { config, self', inputs', system, ... }: 
      let
        # Custom pkgs with overlays via module arguments
        pkgs = import inputs.nixpkgs {
          inherit system;
          overlays = [
            rust-overlay.overlays.default
            (final: prev: {
              # Custom overlay definitions
              my-rust = prev.rust-bin.stable.latest.default;
            })
          ];
        };
      in {
        _module.args.pkgs = pkgs;
        
        packages.default = pkgs.my-rust;
        
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            my-rust
            rust-analyzer
          ];
        };
      };
    };
}"#;

    let parse_result = Root::parse(input);
    assert!(parse_result.errors().is_empty(), "Parse errors: {:?}", parse_result.errors());
    
    let tree = parse_result.tree();
    
    if let Some(expr) = tree.expr() {
        let node = expr.syntax();
        
        // Test replacing the rust-overlay input URL
        if let Some(path) = find_url_string_path(node, "github:oxalica/rust-overlay") {
            let mut builder = GreenNodeBuilder::new();
            let replacement_url = "git+file:///home/tim/src/rust-overlay?ref=latest-features";
            
            assert!(reconstruct_with_replacement(&mut builder, node, &path, 0, replacement_url).is_ok());
            
            let result = builder.finish();
            let new_tree = SyntaxNode::new_root(result);
            let result_text = new_tree.text().to_string();
            
            // Verify the URL was replaced
            assert!(result_text.contains(replacement_url));
            assert!(!result_text.contains("github:oxalica/rust-overlay"));
            
            // Verify custom module arguments structure is preserved
            assert!(result_text.contains("_module.args.pkgs = pkgs"));
            assert!(result_text.contains("rust-overlay.overlays.default"));
            assert!(result_text.contains("import inputs.nixpkgs"));
            assert!(result_text.contains("my-rust = prev.rust-bin.stable.latest.default"));
            
            // Verify the result is still valid Nix syntax
            let validation_result = Root::parse(&result_text);
            assert!(validation_result.errors().is_empty(), "Validation errors after replacement: {:?}", validation_result.errors());
        } else {
            panic!("Could not find rust-overlay URL in custom module arguments pattern");
        }
    } else {
        panic!("Could not parse expression in custom module arguments pattern");
    }
}

#[test]
fn test_complex_flake_parts_with_multiple_modules() {
    // Test more complex flake-parts structure with multiple imports and custom arguments
    let input = r#"{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    devenv.url = "github:cachix/devenv";
    fenix.url = "github:nix-community/fenix";
  };
  
  outputs = inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [
        inputs.devenv.flakeModule
        ./nix/modules/rust.nix
        ./nix/modules/frontend.nix
      ];
      
      flake = {
        _module.args = {
          inherit inputs;
          customToolchain = inputs.fenix.packages.x86_64-linux.latest;
        };
      };
      
      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" ];
      
      perSystem = { config, self', inputs', system, customToolchain, ... }: {
        packages.toolchain = customToolchain.toolchain;
        
        devenv.shells.default = {
          languages.rust.enable = true;
          languages.rust.toolchain = customToolchain;
        };
      };
    };
}"#;

    let parse_result = Root::parse(input);
    assert!(parse_result.errors().is_empty(), "Parse errors: {:?}", parse_result.errors());
    
    let tree = parse_result.tree();
    
    if let Some(expr) = tree.expr() {
        let node = expr.syntax();
        
        // Test replacing the fenix input URL
        if let Some(path) = find_url_string_path(node, "github:nix-community/fenix") {
            let mut builder = GreenNodeBuilder::new();
            let replacement_url = "git+file:///home/tim/src/fenix?ref=custom-toolchains";
            
            assert!(reconstruct_with_replacement(&mut builder, node, &path, 0, replacement_url).is_ok());
            
            let result = builder.finish();
            let new_tree = SyntaxNode::new_root(result);
            let result_text = new_tree.text().to_string();
            
            // Verify the URL was replaced
            assert!(result_text.contains(replacement_url));
            assert!(!result_text.contains("github:nix-community/fenix"));
            
            // Verify complex flake-parts structure is preserved
            assert!(result_text.contains("inputs.devenv.flakeModule"));
            assert!(result_text.contains("./nix/modules/rust.nix"));
            assert!(result_text.contains("./nix/modules/frontend.nix"));
            assert!(result_text.contains("_module.args = {"));
            assert!(result_text.contains("inherit inputs;"));
            assert!(result_text.contains("customToolchain = inputs.fenix.packages.x86_64-linux.latest"));
            assert!(result_text.contains("devenv.shells.default"));
            
            // Verify the result is still valid Nix syntax
            let validation_result = Root::parse(&result_text);
            assert!(validation_result.errors().is_empty(), "Validation errors after replacement: {:?}", validation_result.errors());
        } else {
            panic!("Could not find fenix URL in complex flake-parts pattern");
        }
    } else {
        panic!("Could not parse expression in complex flake-parts pattern");
    }
}