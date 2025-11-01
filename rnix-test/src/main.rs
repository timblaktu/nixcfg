use std::fs;

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
    } else {
        println!("❌ Could not access root expression");
    }
}
