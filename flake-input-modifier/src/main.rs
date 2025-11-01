use clap::{Arg, ArgMatches, Command};
use std::fs;
use std::io::{self, Read};

use flake_input_modifier::replace_flake_input_url;

fn main() {
    let matches = Command::new("flake-input-modifier")
        .version("0.1.0")
        .about("AST-based Nix flake input URL replacement tool")
        .arg(
            Arg::new("flake_path")
                .help("Path to the flake.nix file (use '-' for stdin)")
                .required(true)
                .index(1)
        )
        .arg(
            Arg::new("input_name")
                .help("Name of the input to modify")
                .required(true)
                .index(2)
        )
        .arg(
            Arg::new("old_url")
                .help("Current URL to replace")
                .required(true)
                .index(3)
        )
        .arg(
            Arg::new("new_url")
                .help("New URL to use")
                .required(true)
                .index(4)
        )
        .arg(
            Arg::new("in_place")
                .short('i')
                .long("in-place")
                .help("Modify the file in-place instead of writing to stdout")
                .action(clap::ArgAction::SetTrue)
        )
        .get_matches();

    if let Err(e) = run(&matches) {
        eprintln!("Error: {}", e);
        std::process::exit(1);
    }
}

fn run(matches: &ArgMatches) -> Result<(), Box<dyn std::error::Error>> {
    let flake_path = matches.get_one::<String>("flake_path").unwrap();
    let input_name = matches.get_one::<String>("input_name").unwrap();
    let old_url = matches.get_one::<String>("old_url").unwrap();
    let new_url = matches.get_one::<String>("new_url").unwrap();
    let in_place = matches.get_flag("in_place");

    // Read the flake content
    let flake_content = if flake_path == "-" {
        let mut buffer = String::new();
        io::stdin().read_to_string(&mut buffer)?;
        buffer
    } else {
        fs::read_to_string(flake_path)?
    };

    // Perform the URL replacement
    let result = replace_flake_input_url(&flake_content, input_name, old_url, new_url)
        .map_err(|e| format!("Failed to replace URL: {}", e))?;

    // Output the result
    if in_place {
        if flake_path == "-" {
            return Err("Cannot use --in-place with stdin input".into());
        }
        fs::write(flake_path, result)?;
        eprintln!("Successfully updated {}", flake_path);
    } else {
        print!("{}", result);
    }

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;
    use std::process::Command;
    use tempfile::NamedTempFile;

    #[test]
    fn test_cli_functionality() {
        let flake_content = r#"{ inputs = { nixpkgs.url = "github:NixOS/nixpkgs"; }; }"#;
        
        // Create a temporary file
        let mut temp_file = NamedTempFile::new().unwrap();
        fs::write(temp_file.path(), flake_content).unwrap();
        
        // Test the CLI (this would require the binary to be built)
        // For now, just test the core functionality
        let result = replace_flake_input_url(
            flake_content,
            "nixpkgs",
            "github:NixOS/nixpkgs",
            "git+file:///local/nixpkgs"
        ).unwrap();
        
        assert!(result.contains("git+file:///local/nixpkgs"));
    }
}