# Security and privacy checks for WSL tarball builds
# This module wraps the tarball builder with security checks
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.wsl;

  # List of personal identifiers to check for
  personalIdentifiers = [
    "tim"
    "tblack"
    "timblack"
  ];

  # List of sensitive environment patterns
  sensitiveEnvPatterns = [
    "TOKEN"
    "API_KEY"
    "SECRET"
    "PASSWORD"
    "PRIVATE_KEY"
    "AWS_"
    "GITHUB_TOKEN"
    "GITLAB_TOKEN"
    "NPM_TOKEN"
    "OPENAI"
    "ANTHROPIC"
  ];

  # Generate a security check script
  securityCheckScript = pkgs.writers.writeBashBin "wsl-tarball-security-check" ''
    set -e
    
    # Colors for output
    RED='\033[0;31m'
    YELLOW='\033[1;33m'
    GREEN='\033[0;32m'
    BLUE='\033[0;34m'
    NC='\033[0m'
    
    echo -e "''${BLUE}════════════════════════════════════════════════''${NC}"
    echo -e "''${BLUE}    WSL Tarball Security & Privacy Check       ''${NC}"
    echo -e "''${BLUE}════════════════════════════════════════════════''${NC}"
    echo ""
    
    WARNINGS=0
    ERRORS=0
    CONFIG_NAME="''${1:-unknown}"
    
    # Function to check for personal identifiers
    check_personal() {
      local value="$1"
      local context="$2"
      for id in ${concatStringsSep " " personalIdentifiers}; do
        if [[ "$value" =~ $id ]]; then
          echo -e "''${YELLOW}⚠ WARNING: Personal identifier '$id' found in $context: $value''${NC}"
          WARNINGS=$((WARNINGS + 1))
          return 0
        fi
      done
      return 1
    }
    
    # Check wsl.defaultUser
    DEFAULT_USER="${optionalString (cfg ? defaultUser) cfg.defaultUser}"
    if [ -n "$DEFAULT_USER" ]; then
      check_personal "$DEFAULT_USER" "wsl.defaultUser"
    fi
    
    # Check normal users (not system users)
    echo "Checking configured users..."
    ${concatMapStringsSep "\n    " (user: 
      let
        userCfg = config.users.users.${user};
        isNormalUser = userCfg.isNormalUser or false;
      in optionalString isNormalUser ''check_personal "${user}" "users.users"''
    ) (attrNames config.users.users)}
    
    # Check for SSH keys
    ${concatMapStringsSep "\n    " (user: 
      let 
        userCfg = config.users.users.${user};
        hasKeys = userCfg ? openssh && userCfg.openssh ? authorizedKeys &&
                  ((userCfg.openssh.authorizedKeys.keys or []) != [] || 
                   (userCfg.openssh.authorizedKeys.keyFiles or []) != []);
      in optionalString hasKeys ''
        echo -e "''${YELLOW}⚠ WARNING: SSH authorized keys configured for user ${user}''${NC}"
        echo "  These keys will be included in the tarball"
        WARNINGS=$((WARNINGS + 1))''
    ) (attrNames config.users.users)}
    
    # Check hostname
    HOSTNAME="${config.networking.hostName or "nixos"}"
    if [ -n "$HOSTNAME" ]; then
      if check_personal "$HOSTNAME" "networking.hostName"; then
        echo "  Consider using a generic hostname like 'nixos-wsl'"
      fi
    fi
    
    # Check git configuration in environment
    if [[ -n "''${GIT_AUTHOR_NAME:-}" ]] || [[ -n "''${GIT_AUTHOR_EMAIL:-}" ]]; then
      echo -e "''${YELLOW}⚠ WARNING: Git configuration in build environment''${NC}"
      [ -n "''${GIT_AUTHOR_NAME:-}" ] && echo "  GIT_AUTHOR_NAME: ''${GIT_AUTHOR_NAME}"
      [ -n "''${GIT_AUTHOR_EMAIL:-}" ] && echo "  GIT_AUTHOR_EMAIL: ''${GIT_AUTHOR_EMAIL}"
      WARNINGS=$((WARNINGS + 1))
    fi
    
    # Check for sensitive environment variables
    echo "Checking for sensitive environment variables..."
    for pattern in ${concatStringsSep " " sensitiveEnvPatterns}; do
      if env | grep -q "^$pattern"; then
        echo -e "''${RED}✗ ERROR: Sensitive environment variable pattern detected: $pattern*''${NC}"
        ERRORS=$((ERRORS + 1))
      fi
    done
    
    # Summary
    echo ""
    echo -e "''${BLUE}════════════════════════════════════════════════''${NC}"
    echo -e "''${BLUE}                   Summary                      ''${NC}"
    echo -e "''${BLUE}════════════════════════════════════════════════''${NC}"
    
    if [ $ERRORS -gt 0 ]; then
      echo -e "''${RED}✗ Found $ERRORS error(s) - Build blocked''${NC}"
      echo ""
      echo "Critical issues must be resolved before building."
      echo "To bypass checks (NOT RECOMMENDED), run:"
      echo "  WSL_TARBALL_SKIP_CHECKS=1 build-wsl-tarball $CONFIG_NAME"
    elif [ $WARNINGS -gt 0 ]; then
      echo -e "''${YELLOW}⚠ Found $WARNINGS warning(s)''${NC}"
      echo ""
      echo "These warnings indicate personal information that will be"
      echo "included in the tarball. Consider:"
      echo "  1. Creating a generic configuration for distribution"
      echo "  2. Using 'nixos' as defaultUser instead of personal names"
      echo "  3. Removing SSH keys and personal git config"
    else
      echo -e "''${GREEN}✓ No sensitive information detected''${NC}"
      echo "Configuration appears safe for distribution."
    fi
    
    # Exit with error if critical issues found
    if [ $ERRORS -gt 0 ] && [ "''${WSL_TARBALL_SKIP_CHECKS:-0}" != "1" ]; then
      exit 1
    fi
    
    if [ "''${WSL_TARBALL_SKIP_CHECKS:-0}" = "1" ]; then
      echo ""
      echo -e "''${YELLOW}⚠ CHECKS BYPASSED - Proceeding despite warnings''${NC}"
    fi
  '';

in
{
  options = {
    wsl.tarballChecks = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable security and privacy checks for tarball builds";
      };

      personalIdentifiers = mkOption {
        type = types.listOf types.str;
        default = personalIdentifiers;
        description = "List of personal identifiers to check for";
      };

      sensitivePatterns = mkOption {
        type = types.listOf types.str;
        default = sensitiveEnvPatterns;
        description = "List of sensitive environment variable patterns";
      };
    };
  };

  config = mkIf (cfg.enable or false) {
    # Provide the check script as a build artifact
    system.build.tarballSecurityCheck = securityCheckScript;
  };
}
