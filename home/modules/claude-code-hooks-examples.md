# Claude Code Hooks Examples

This file contains example hook configurations for common development workflows.
Add these to your Nix configuration or directly to `~/.claude/settings.json`.

## Python Development Hooks

Automatically format Python files after editing:

```nix
programs.claude-code.hooks = {
  PostToolUse = [
    {
      matcher = "Edit|Write";
      hooks = [{
        type = "command";
        command = ''
          jq -r '.tool_input.file_path' | { 
            read file_path; 
            if echo "$file_path" | grep -q '\.py$'; then 
              black "$file_path" 2>/dev/null || true; 
            fi; 
          }
        '';
      }];
    }
  ];
};
```

## TypeScript/JavaScript Hooks

Format and lint TypeScript/JavaScript files:

```nix
programs.claude-code.hooks = {
  PostToolUse = [
    {
      matcher = "Edit|Write";
      hooks = [{
        type = "command";
        command = ''
          jq -r '.tool_input.file_path' | { 
            read file_path; 
            if echo "$file_path" | grep -qE '\.(ts|tsx|js|jsx)$'; then 
              prettier --write "$file_path" 2>/dev/null || true; 
            fi; 
          }
        '';
      }];
    }
  ];
};
```

## Git Safety Hooks

Prevent editing of sensitive files:

```nix
programs.claude-code.hooks = {
  PreToolUse = [
    {
      matcher = "Edit|Write";
      hooks = [{
        type = "command";
        command = ''
          file_path=$(jq -r '.tool_input.file_path')
          if echo "$file_path" | grep -qE '(\.env|\.secrets|id_rsa)'; then
            echo "BLOCKED: Cannot edit sensitive file: $file_path" >&2
            exit 2
          fi
        '';
      }];
    }
  ];
};
```

## Nix Development Hooks

Check Nix files for syntax errors:

```nix
programs.claude-code.hooks = {
  PostToolUse = [
    {
      matcher = "Edit|Write";
      hooks = [{
        type = "command";
        command = ''
          jq -r '.tool_input.file_path' | { 
            read file_path; 
            if echo "$file_path" | grep -q '\.nix$'; then 
              nix-instantiate --parse "$file_path" >/dev/null 2>&1 || {
                echo "Warning: Nix syntax error in $file_path" >&2
              }
            fi; 
          }
        '';
      }];
    }
  ];
};
```

## Test Automation Hooks

Run tests after code changes:

```nix
programs.claude-code.hooks = {
  PostToolUse = [
    {
      matcher = "Edit|Write";
      hooks = [{
        type = "command";
        command = ''
          file_path=$(jq -r '.tool_input.file_path')
          if echo "$file_path" | grep -qE 'src/.*\.(py|js|ts)$'; then
            # Run tests in background
            (npm test 2>/dev/null || pytest 2>/dev/null || true) &
          fi
        '';
      }];
    }
  ];
};
```

## Logging Hooks

Log all tool usage:

```nix
programs.claude-code.hooks = {
  PreToolUse = [
    {
      matcher = "*";
      hooks = [{
        type = "command";
        command = ''
          tool_name=$(jq -r '.tool_name')
          timestamp=$(date -Iseconds)
          echo "[$timestamp] Tool: $tool_name" >> ~/.claude/tool-usage.log
        '';
      }];
    }
  ];
};
```

## Session Management Hooks

Save session context on stop:

```nix
programs.claude-code.hooks = {
  Stop = [
    {
      matcher = "";
      hooks = [{
        type = "command";
        command = ''
          session_id=$(jq -r '.session_id')
          timestamp=$(date +%Y%m%d_%H%M%S)
          # Save session summary
          echo "Session $session_id ended at $timestamp" >> ~/.claude/sessions.log
        '';
      }];
    }
  ];
};
```

## Complete Example Configuration

Here's a complete example combining multiple hooks:

```nix
programs.claude-code = {
  enable = true;
  
  # Permissions
  permissions = {
    allow = [
      "Bash(npm test:*)"
      "Bash(pytest:*)"
      "Read(~/.config/*)"
    ];
    deny = [
      "Bash(rm -rf:*)"
      "Read(.env*)"
      "Write(/etc/*)"
    ];
  };
  
  # Hooks
  hooks = {
    # Before tool use
    PreToolUse = [
      {
        matcher = "Edit|Write";
        hooks = [{
          type = "command";
          command = ''
            # Log file modifications
            jq -r '"Editing: \(.tool_input.file_path)"' >> ~/.claude/edits.log
          '';
        }];
      }
    ];
    
    # After tool use
    PostToolUse = [
      {
        matcher = "Edit|Write";
        hooks = [{
          type = "command";
          command = ''
            # Auto-format based on file type
            file_path=$(jq -r '.tool_input.file_path')
            case "$file_path" in
              *.py) black "$file_path" 2>/dev/null || true ;;
              *.nix) nixpkgs-fmt "$file_path" 2>/dev/null || true ;;
              *.js|*.ts) prettier --write "$file_path" 2>/dev/null || true ;;
            esac
          '';
        }];
      }
    ];
    
    # On session stop
    Stop = [
      {
        matcher = "";
        hooks = [{
          type = "command";
          command = ''
            echo "Session complete at $(date)" >> ~/.claude/sessions.log
          '';
        }];
      }
    ];
  };
};
```

## Notes

1. **Exit Codes**: 
   - Exit code 0: Success, continue normally
   - Exit code 2: Block the operation (for PreToolUse hooks)
   - Other codes: Show error but continue

2. **Environment Variables**:
   - `$CLAUDE_PROJECT_DIR`: Project directory
   - `$CLAUDE_FILE_PATH`: File being edited (in PostToolUse)
   - `$CLAUDE_TOOL_NAME`: Name of the tool being used

3. **Security**: 
   - Always validate inputs in hooks
   - Use absolute paths where possible
   - Be careful with shell expansion

4. **Performance**:
   - Hooks have a 60-second timeout by default
   - Run heavy operations in background with `&`
   - Consider using `|| true` to prevent failures from blocking
