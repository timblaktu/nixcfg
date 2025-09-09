# Drop-in file management module for Home Manager
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.homeBase;
  
  # Get the absolute path to the files directory
  filesDir = ./../../files;
  
  # Generate automatic zsh completion by parsing help text
  generateAutoZshCompletion = { name }:
    let
      funcName = "_${lib.replaceStrings ["-"] ["_"] name}";
    in pkgs.writeText "_${name}" ''
      #compdef ${name}
      
      ${funcName}() {
        local curcontext="$curcontext" state line
        typeset -A opt_args
        
        _arguments -C \
          '--help[Show help message]' \
          '-h[Show help message]' \
          "1: :->cmds" \
          "*::arg:->args"
        
        case $state in
          (cmds)
            # Get available commands by parsing help
            local -a commands
            local help_output
            help_output=$(${name} --help 2>/dev/null || ${name} -h 2>/dev/null || ${name} help 2>/dev/null || ${name} 2>&1)
            
            # Extract commands from help text - look for common patterns
            local cmd_list
            cmd_list=$(echo "$help_output" | awk '
              /COMMANDS:/ { in_cmds=1; next }
              /^[A-Z]/ && in_cmds { in_cmds=0 }
              in_cmds && /^[[:space:]]+[a-zA-Z]/ {
                gsub(/^[[:space:]]*/, "")
                cmd = $1
                $1 = ""
                gsub(/^[[:space:]]*/, "")
                desc = $0
                print cmd ":" desc
              }
            ')
            
            if [[ -n "$cmd_list" ]]; then
              commands=(''${(f)cmd_list})
              _describe "${name} commands" commands
            else
              # Fallback - look for common command words
              local simple_cmds
              simple_cmds=$(echo "$help_output" | grep -oE '\b(setup|deploy|run|help|check|scan|start|stop|status|install|config)\b' | sort -u | tr '\n' ' ')
              if [[ -n "$simple_cmds" ]]; then
                _values "${name} commands" ''${=simple_cmds}
              fi
            fi
            ;;
          (args)
            # Handle subcommand options and arguments
            local subcmd="$line[1]"
            local subcmd_help
            
            # Get subcommand help
            subcmd_help=$(${name} "$subcmd" --help 2>/dev/null || ${name} "$subcmd" -h 2>/dev/null)
            
            if [[ -z "$subcmd_help" ]]; then
              return
            fi
            
            # Check if we're completing an option value
            local prev="$words[CURRENT-1]"
            if [[ "$prev" == -* ]]; then
              # Extract the option's parameter name and possible values
              local opt_line opt_param
              opt_line=$(echo "$subcmd_help" | grep -E "^[[:space:]]*$prev[[:space:]]" | head -1)
              
              if [[ -n "$opt_line" ]]; then
                # Extract parameter name (e.g., MODE, FILE, etc.)
                opt_param=$(echo "$opt_line" | sed -n 's/^[[:space:]]*-[a-zA-Z][[:space:]]*\([A-Z][A-Z0-9_]*\).*/\1/p')
                
                if [[ -n "$opt_param" ]]; then
                  # Look for a VALUES section for this parameter
                  local values_section
                  values_section=$(echo "$subcmd_help" | awk -v param="$opt_param" '
                    BEGIN { found=0 }
                    $0 ~ "^" param " VALUES:" { found=1; next }
                    found && /^[A-Z]/ { exit }
                    found && /^[[:space:]]+[a-zA-Z0-9_]+/ {
                      gsub(/^[[:space:]]*/, "")
                      value = $1
                      $1 = ""
                      gsub(/^[[:space:]]*/, "")
                      desc = $0
                      print value ":" desc
                    }
                  ')
                  
                  if [[ -n "$values_section" ]]; then
                    # Use _describe for values with descriptions
                    local -a value_descriptions
                    value_descriptions=(''${(f)values_section})
                    _describe "$opt_param value" value_descriptions
                    return
                  fi
                  
                  # Try to extract inline values from option description
                  local inline_values
                  # Pattern: "Mode: value1, value2, value3"
                  inline_values=$(echo "$opt_line" | sed -n 's/.*:[[:space:]]*\([a-zA-Z0-9_, ]*\).*/\1/p' | tr ',' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | grep -v "default" | tr '\n' ' ')
                  
                  if [[ -n "$inline_values" ]]; then
                    local -a values_array
                    values_array=(''${=inline_values})
                    compadd -a values_array
                    return
                  fi
                  
                  # Special cases for common parameter types
                  case "$opt_param" in
                    FILE|PATH)
                      _files
                      return
                      ;;
                    DIR|DIRECTORY)
                      _directories
                      return
                      ;;
                    USER)
                      _users
                      return
                      ;;
                    HOST|IP|HOSTNAME)
                      _hosts
                      return
                      ;;
                  esac
                fi
              fi
            else
              # Complete options for the subcommand
              local -a options
              options=$(echo "$subcmd_help" | awk '
                /^[[:space:]]*-[a-zA-Z0-9]/ {
                  gsub(/^[[:space:]]*/, "")
                  opt = $1
                  $1 = ""
                  gsub(/^[[:space:]]*/, "")
                  desc = $0
                  print opt "[" desc "]"
                }
              ')
              
              if [[ -n "$options" ]]; then
                local -a opt_array
                opt_array=(''${(f)options})
                _arguments -S "''${opt_array[@]}"
              fi
            fi
            ;;
        esac
      }
      
      ${funcName} "$@"
    '';
    
  # Generate bash completion (enhanced to support value constraints)
  generateAutoBashCompletion = { name }:
    let
      funcName = "_${lib.replaceStrings ["-"] ["_"] name}";
    in pkgs.writeText "${name}-completion.bash" ''
      # Auto-generated bash completion for ${name}
      ${funcName}() {
          local cur prev words cword
          COMPREPLY=()
          cur="''${COMP_WORDS[COMP_CWORD]}"
          prev="''${COMP_WORDS[COMP_CWORD-1]}"
          words=("''${COMP_WORDS[@]}")
          cword=$COMP_CWORD
          
          # Get help text and parse commands
          local help_text
          help_text=$(${name} --help 2>/dev/null || ${name} -h 2>/dev/null || ${name} help 2>/dev/null)
          
          local commands
          commands=$(echo "$help_text" | sed -n '/COMMANDS:/,/^[A-Z]/p' | grep -E '^\s+\w+' | awk '{print $1}' | tr '\n' ' ')
          
          # Find current command
          local cmd=""
          local i
          for (( i=1; i < cword; i++ )); do
              local word="''${words[i]}"
              if [[ "$word" != -* ]] && echo "$commands" | grep -q "\b$word\b"; then
                  cmd="$word"
                  break
              fi
          done
          
          # Check if previous word was an option that expects a value
          if [[ "$prev" == -* ]]; then
              local option_help
              if [[ -n "$cmd" ]]; then
                  option_help=$(${name} "$cmd" --help 2>/dev/null || ${name} "$cmd" -h 2>/dev/null)
              else
                  option_help="$help_text"
              fi
              
              # Extract possible values for the previous option
              local option_line
              option_line=$(echo "$option_help" | grep -E "^\s*$prev\s+" | head -1)
              
              if [[ -n "$option_line" ]]; then
                  # Try to extract value constraints from the description
                  local values=""
                  
                  # Pattern 1: "Mode: value1, value2, value3"
                  if echo "$option_line" | grep -q ":[[:space:]]*[a-zA-Z0-9_]"; then
                      values=$(echo "$option_line" | sed -n 's/.*:[[:space:]]*\([a-zA-Z0-9_,[:space:]]*\).*/\1/p' | tr ',' ' ')
                  fi
                  
                  # Pattern 2: "(value1|value2|value3)"
                  if [[ -z "$values" ]] && echo "$option_line" | grep -q "([a-zA-Z0-9_|]*)"; then
                      values=$(echo "$option_line" | sed -n 's/.*(\([a-zA-Z0-9_|]*\)).*/\1/p' | tr '|' ' ')
                  fi
                  
                  # Pattern 3: "{value1,value2,value3}"
                  if [[ -z "$values" ]] && echo "$option_line" | grep -q "{[a-zA-Z0-9_,]*}"; then
                      values=$(echo "$option_line" | sed -n 's/.*{\([a-zA-Z0-9_,]*\)}.*/\1/p' | tr ',' ' ')
                  fi
                  
                  # Remove common non-value words
                  values=$(echo "$values" | sed 's/\(default\|Default\).*//g' | xargs)
                  
                  if [[ -n "$values" ]]; then
                      COMPREPLY=( $(compgen -W "$values" -- "$cur") )
                      return
                  fi
                  
                  # Special case for file/path options
                  if echo "$option_line" | grep -qiE "(FILE|PATH)"; then
                      COMPREPLY=( $(compgen -f -- "$cur") )
                      return
                  fi
                  
                  # Special case for directory options
                  if echo "$option_line" | grep -qiE "(DIR|DIRECTORY)"; then
                      COMPREPLY=( $(compgen -d -- "$cur") )
                      return
                  fi
              fi
          fi
          
          # Default behavior: complete commands and options
          if [[ -n "$cmd" ]]; then
              # Complete options for specific command
              local cmd_help
              cmd_help=$(${name} "$cmd" --help 2>/dev/null || ${name} "$cmd" -h 2>/dev/null)
              local opts
              opts=$(echo "$cmd_help" | grep -oE '\s+-[a-zA-Z0-9]+' | tr -d ' ' | tr '\n' ' ')
              COMPREPLY=( $(compgen -W "$opts" -- "$cur") )
          else
              # Complete commands and global options
              local global_opts
              global_opts=$(echo "$help_text" | grep -oE '\s+-[a-zA-Z0-9]+' | tr -d ' ' | tr '\n' ' ')
              COMPREPLY=( $(compgen -W "$commands $global_opts" -- "$cur") )
          fi
      }
      complete -F ${funcName} ${name}
    '';
  
  # Helper functions
  mkHomeFiles = { sourceDir, targetDir, executable ? false }: 
    let
      dirContents = builtins.readDir sourceDir;
      files = filterAttrs (name: type: type == "regular") dirContents;
      fileEntries = mapAttrs' (name: value: {
        name = "${targetDir}/${name}";
        value = {
          source = sourceDir + "/${name}";
          executable = executable;
        };
      }) files;
    in fileEntries;
    
  # Generate bash completion files automatically for all scripts
  mkBashCompletionFiles = 
    let
      binDir = filesDir + "/bin";
      binContents = builtins.readDir binDir;
      executableFiles = filterAttrs (name: type: type == "regular") binContents;
    in
    mapAttrs' (scriptName: _: {
      name = ".local/share/bash-completion/completions/${scriptName}";
      value = {
        source = generateAutoBashCompletion {
          name = scriptName;
        };
      };
    }) executableFiles;
  
  # Generate zsh completion files automatically for all scripts
  mkZshCompletionFiles = 
    let
      binDir = filesDir + "/bin";
      binContents = builtins.readDir binDir;
      executableFiles = filterAttrs (name: type: type == "regular") binContents;
    in
    mapAttrs' (scriptName: _: {
      name = ".local/share/zsh/site-functions/_${scriptName}";
      value = {
        source = generateAutoZshCompletion {
          name = scriptName;
        };
      };
    }) executableFiles;

in {
  config = {
    home.file = lib.mkMerge [
      # Executable scripts
      (mkHomeFiles {
        sourceDir = filesDir + "/bin";
        targetDir = "bin";
        executable = true;
      })
      # Claude directory
      {
        "claude" = {
          source = filesDir + "/claude";
          recursive = true;
        };
      }
      # Auto-generated completions for all scripts
      mkBashCompletionFiles
      mkZshCompletionFiles
    ];
    
    programs.bash.enableCompletion = true;
    
    programs.zsh = {
      enableCompletion = true;
      initContent = lib.mkAfter ''
        # Add local zsh completions to fpath BEFORE compinit
        if [[ -d "$HOME/.local/share/zsh/site-functions" ]]; then
          fpath=($HOME/.local/share/zsh/site-functions $fpath)
        fi
        
        # Configure completion display options for better formatting
        zstyle ':completion:*' menu select
        zstyle ':completion:*' list-colors ""
        zstyle ':completion:*:descriptions' format '%B%d%b'
        zstyle ':completion:*:messages' format '%d'
        zstyle ':completion:*:warnings' format 'No matches for: %d'
        zstyle ':completion:*' group-name ""
        zstyle ':completion:*' verbose true
        
        # Force reload of completion system for new files
        autoload -U compinit
        compinit -u
        
        # Load bash completions as fallback
        if command -v bashcompinit > /dev/null 2>&1; then
          autoload -U bashcompinit && bashcompinit
          for completion in $HOME/.local/share/bash-completion/completions/*; do
            basename=''${completion##*/}
            # Only load bash completion if no native zsh completion exists
            if [[ -f "$completion" ]] && [[ ! -f "$HOME/.local/share/zsh/site-functions/_$basename" ]]; then
              source "$completion"
            fi
          done
        fi
      '';
    };
  };
}
