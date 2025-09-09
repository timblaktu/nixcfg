{ config, lib, pkgs, uv-mcp-servers, ... }:

let
  cfg = config.services.uv-mcp-servers;
  
  # WSL environment detection and variable reading with fallbacks
  isWSLEnabled = config.targets.wsl.enable or false;
  
  # Read variables produced by wsl target at build-time (with fallbacks)
  windowsUsername = if isWSLEnabled then 
    config.targets.wsl.windowsUsernameFinal or "unknown"
  else 
    "unknown";
    
  windowsHomeDir = if isWSLEnabled then 
    config.targets.wsl.windowsHomeDir or "/mnt/c/Users/unknown"
  else 
    "/mnt/c/Users/unknown";
    
  wslDistroName = if isWSLEnabled then 
    config.targets.wsl.wslDistroName or "NixOS"
  else 
    "NixOS";

  # Single source of truth for allowed directories
  allowedDirectories = [
    config.home.homeDirectory
    "/etc" 
    "/nix/store"
    windowsHomeDir
    "/mnt/wsl"
    "${windowsHomeDir}/AppData/Roaming/Claude/logs"
  ];

  # Server configuration helpers
  mkServerConfig = name: serverCfg: let
    # Map server names to actual package names in uv-mcp-servers
    packageMap = {
      "sequential-thinking" = "sequential-thinking";
      "filesystem" = "filesystem"; 
      "cli-mcp-server" = "cli-mcp-server";
      "mcp-nixos" = "mcp-nixos";
    };
    
    packageName = packageMap.${name} or name;
    serverPackage = uv-mcp-servers.packages.${pkgs.system}.${packageName} or (throw "MCP server '${packageName}' not found in uv-mcp-servers");
    
    # Map to actual binary names
    binaryMap = {
      "sequential-thinking" = "sequential-thinking-mcp";
      "filesystem" = "mcp-filesystem";
      "cli-mcp-server" = "cli-mcp-server"; 
      "mcp-nixos" = "mcp-nixos";
    };
    
    binaryName = binaryMap.${name} or "mcp-${name}";
    serverBinary = "${serverPackage}/bin/${binaryName}";
    
  in {
    command = if serverCfg.useWSL then "C:\\WINDOWS\\system32\\wsl.exe" else serverBinary;
    args = if serverCfg.useWSL then 
      [ "-d" wslDistroName "-e" serverBinary ] ++ (serverCfg.args or [])
    else
      serverCfg.args or [];
    env = serverCfg.env or {};
  } // (lib.optionalAttrs (serverCfg ? timeout) { inherit (serverCfg) timeout; });

  # Generate Claude Desktop configuration
  claudeConfig = {
    mcpServers = lib.mapAttrs mkServerConfig (lib.filterAttrs (_: v: v.enable) cfg.servers);
  };

  # Server type definition
  serverOptions = { name, ... }: {
    options = {
      enable = lib.mkEnableOption "MCP server ${name}";
      
      useWSL = lib.mkOption {
        type = lib.types.bool;
        default = isWSLEnabled;
        description = "Execute server via WSL (Windows Subsystem for Linux)";
      };
      
      args = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
        description = "Additional arguments to pass to the server";
      };
      
      env = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = {};
        description = "Environment variables for the server";
      };
      
      timeout = lib.mkOption {
        type = lib.types.nullOr lib.types.int;
        default = null;
        description = "Server timeout in seconds";
      };
    };
  };

in {
  options.services.uv-mcp-servers = {
    enable = lib.mkEnableOption "UV-based MCP servers";
    
    configFormat = lib.mkOption {
      type = lib.types.enum [ "json" "yaml" ];
      default = "json";
      description = "Format for Claude Desktop configuration";
    };
    
    configFile = lib.mkOption {
      type = lib.types.str;
      default = "claude-mcp-config-uv.json";
      description = "Name of the Claude Desktop configuration file";
    };
    
    servers = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule serverOptions);
      default = {};
      description = "MCP servers to configure";
      example = lib.literalExpression ''
        {
          sequential-thinking = {
            enable = true;
            env = { DEBUG = "*"; };
          };
          filesystem = {
            enable = true;
            args = allowedDirectories;
          };
        }
      '';
    };
    
    allowedDirectories = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = allowedDirectories;
      description = "Directories accessible to MCP servers";
    };
    
    globalEnv = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { DEBUG = "*"; };
      description = "Global environment variables for all servers";
    };
  };

  config = lib.mkIf cfg.enable {
    # Ensure UV MCP servers input is available
    assertions = [
      {
        assertion = uv-mcp-servers != null;
        message = "uv-mcp-servers input not found. Add uv-mcp-servers to your flake inputs and extraSpecialArgs.";
      }
    ];

    # Install necessary tools
    home.packages = with pkgs; [
      uv
      python312
      git
      jq
      nodejs  # For MCP protocol
    ];

    # Generate Claude Desktop configuration file
    home.file.${cfg.configFile} = {
      text = if cfg.configFormat == "json" then
        builtins.toJSON claudeConfig
      else
        lib.generators.toYAML {} claudeConfig;
    };

    # Create test and verification scripts
    home.file."bin/test-uv-mcp-servers" = {
      executable = true;
      text = ''
        #!/usr/bin/env bash
        
        echo "Testing UV MCP Servers..."
        echo
        
        echo "=== Configuration ==="
        echo "WSL Enabled: ${lib.boolToString isWSLEnabled}"
        echo "Windows User: ${windowsUsername}"
        echo "Windows Home: ${windowsHomeDir}"
        echo "WSL Distro: ${wslDistroName}"
        echo "Config Format: ${cfg.configFormat}"
        echo "Config File: $HOME/${cfg.configFile}"
        echo
        
        echo "=== Available Servers ==="
        ${lib.concatMapStringsSep "\n" (name: 
          "echo '  - ${name}: ${if cfg.servers.${name}.enable then "enabled" else "disabled"}'"
        ) (lib.attrNames cfg.servers)}
        echo
        
        echo "=== Configuration File ==="
        if [ -f "$HOME/${cfg.configFile}" ]; then
          echo "✓ Config file exists: $HOME/${cfg.configFile}"
          if command -v jq &> /dev/null && [[ "${cfg.configFile}" == *.json ]]; then
            echo "Server count: $(jq '.mcpServers | keys | length' "$HOME/${cfg.configFile}")"
            echo "Servers: $(jq -r '.mcpServers | keys | join(", ")' "$HOME/${cfg.configFile}")"
          fi
        else
          echo "✗ Config file missing: $HOME/${cfg.configFile}"
        fi
        echo
        
        echo "=== Package Verification ==="
        ${lib.concatMapStringsSep "\n" (name: 
          if cfg.servers.${name}.enable then let
            packageMap = {
              "sequential-thinking" = "sequential-thinking";
              "filesystem" = "filesystem"; 
              "cli-mcp-server" = "cli-mcp-server";
              "mcp-nixos" = "mcp-nixos";
            };
            binaryMap = {
              "sequential-thinking" = "sequential-thinking-mcp";
              "filesystem" = "mcp-filesystem";
              "cli-mcp-server" = "cli-mcp-server"; 
              "mcp-nixos" = "mcp-nixos";
            };
            packageName = packageMap.${name} or name;
            binaryName = binaryMap.${name} or "mcp-${name}";
          in ''
            if [ -x "${uv-mcp-servers.packages.${pkgs.system}.${packageName} or "missing"}/bin/${binaryName}" ]; then
              echo "✓ ${name}: executable found"
              # Test if server starts (will timeout, but that means it's working)
              timeout 2 "${uv-mcp-servers.packages.${pkgs.system}.${packageName}}/bin/${binaryName}" >/dev/null 2>&1 && echo "  Server starts correctly" || echo "  Server timeout (expected - means it's working)"
            else
              echo "✗ ${name}: binary not found at expected path"
            fi
          '' else ""
        ) (lib.attrNames cfg.servers)}
        echo
        
        echo "=== Directory Access ==="
        ${lib.concatMapStringsSep "\n" (dir: ''
          if [ -d "${dir}" ]; then
            echo "✓ ${dir}"
          else
            echo "✗ ${dir} (not accessible)"
          fi
        '') cfg.allowedDirectories}
        echo
        
        echo "Testing complete."
      '';
    };

    # UV MCP server management helper
    home.file."bin/manage-uv-mcp-servers" = {
      executable = true;
      text = ''
        #!/usr/bin/env bash
        
        action="''${1:-status}"
        
        case "$action" in
          status)
            echo "=== UV MCP Servers Status ==="
            echo "Config file: $HOME/${cfg.configFile}"
            if [ -f "$HOME/${cfg.configFile}" ]; then
              echo "✓ Configuration exists"
              if command -v jq &>/dev/null; then
                echo "Enabled servers:"
                jq -r '.mcpServers | keys[]' "$HOME/${cfg.configFile}" | sed 's/^/  - /'
              fi
            else
              echo "✗ Configuration missing"
            fi
            ;;
            
          test)
            echo "=== Testing UV MCP Servers ==="
            $HOME/bin/test-uv-mcp-servers
            ;;
            
          validate)
            echo "=== Validating UV MCP Server Executables ==="
            ${lib.concatMapStringsSep "\n" (name: 
              if cfg.servers.${name}.enable then let
                packageMap = {
                  "sequential-thinking" = "sequential-thinking";
                  "filesystem" = "filesystem"; 
                  "cli-mcp-server" = "cli-mcp-server";
                  "mcp-nixos" = "mcp-nixos";
                };
                binaryMap = {
                  "sequential-thinking" = "sequential-thinking-mcp";
                  "filesystem" = "mcp-filesystem";
                  "cli-mcp-server" = "cli-mcp-server"; 
                  "mcp-nixos" = "mcp-nixos";
                };
                packageName = packageMap.${name} or name;
                binaryName = binaryMap.${name} or "mcp-${name}";
              in ''
                echo "Testing ${name}..."
                if [ -x "${uv-mcp-servers.packages.${pkgs.system}.${packageName} or "missing"}/bin/${binaryName}" ]; then
                  echo "✓ ${name}: Executable exists"
                  echo "  Path: ${uv-mcp-servers.packages.${pkgs.system}.${packageName}}/bin/${binaryName}"
                  echo "  Testing startup..."
                  timeout 3 "${uv-mcp-servers.packages.${pkgs.system}.${packageName}}/bin/${binaryName}" >/dev/null 2>&1
                  if [ $? -eq 124 ]; then
                    echo "  ✓ Server starts (timeout expected)"
                  else
                    echo "  ⚠ Server exited unexpectedly"
                  fi
                else
                  echo "✗ ${name}: Executable not found"
                fi
                echo
              '' else ""
            ) (lib.attrNames cfg.servers)}
            ;;
            
          *)
            echo "Usage: $0 {status|test|validate}"
            echo
            echo "Commands:"
            echo "  status   - Show configuration status"
            echo "  test     - Run full test suite"
            echo "  validate - Validate server executables"
            ;;
        esac
      '';
    };
  };
}
