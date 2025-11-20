# GitHub Authentication Redesign Plan
**Date**: 2025-11-20
**Branch**: claude/review-pa161878-01BN7oP9qR4p8N6a9YZZufa8
**Status**: Design Complete, Implementation Pending

## Executive Summary

The current GitHub authentication implementation has fundamental architectural flaws:
1. **Wrong Scope**: Implemented as NixOS system modules instead of home-manager user modules
2. **Host-Specific**: Requires manual configuration per-host instead of working automatically everywhere
3. **Over-Engineered**: 500+ lines of custom bash scripts instead of leveraging built-in tools
4. **Violates DRY**: Configuration must be duplicated across hosts

This redesign fixes these issues by creating a proper home-manager module that works seamlessly across all hosts.

---

## Current Implementation Analysis

### Files Created (To Be Removed)
```
modules/nixos/bitwarden-github-auth.nix  (300 lines - WRONG SCOPE)
modules/nixos/github-auth.nix            (250 lines - WRONG SCOPE)
hosts/thinky-nixos/github-auth.nix       (36 lines - SHOULD NOT EXIST)
docs/GITHUB-AUTH-SETUP.md                (302 lines - OUTDATED)
QUICK-GITHUB-AUTH-SETUP.md               (165 lines - OUTDATED)
```

### Critical Issues

#### Issue 1: Wrong Module Scope
**Problem**: GitHub authentication is a **user concern**, not a system concern.
- SSH **host** keys → NixOS module ✅ (system-wide)
- SSH **user** keys → Home-manager module ✅ (user-specific)
- GitHub auth tokens → Currently NixOS module ❌ (should be user-specific)

**Current Architecture (WRONG)**:
```
NixOS System Module (modules/nixos/bitwarden-github-auth.nix)
  ↓
Per-Host Configuration (hosts/thinky-nixos/github-auth.nix)
  ↓
System Activation Scripts (run as root, write to user dirs)
  ↓
Manual setup required on each new host
```

**Correct Architecture (TARGET)**:
```
Home-Manager User Module (home/modules/github-auth.nix)
  ↓
User Configuration (home/modules/base.nix - enabled once)
  ↓
Declarative Configuration (programs.git, programs.gh)
  ↓
Automatic on all hosts where user exists
```

#### Issue 2: Over-Engineering
**Current Approach**:
- ❌ Custom bash scripts in activation scripts (fragile, imperative)
- ❌ Custom `~/.git-askpass-bitwarden` script (unnecessary)
- ❌ Systemd services for "persistent" mode (complex)
- ❌ Manual error handling and retry logic (reimplementing git)

**Better Approach**:
- ✅ Use `git-credential-cache` (built-in, secure, in-memory)
- ✅ Use `programs.git.extraConfig` (declarative)
- ✅ Use `programs.gh` (nixpkgs home-manager module)
- ✅ Let git handle credential management (that's what it's designed for)

#### Issue 3: Duplication of Existing Infrastructure
**Already Have**:
- ✅ `home/modules/secrets-management.nix` - rbw configuration pattern
- ✅ `home/common/git.nix` - git configuration module
- ✅ `modules/nixos/sops-nix.nix` - SOPS infrastructure
- ✅ Working patterns for user secrets (SSH keys via rbw)

**Current Implementation**:
- ❌ Reimplements rbw configuration
- ❌ Separate from git.nix
- ❌ SOPS support in separate module
- ❌ Doesn't follow established patterns

---

## Redesign Architecture

### Module Structure
```
home/modules/github-auth.nix (NEW - Single unified module)
├── Bitwarden Mode (default)
│   ├── Uses existing rbw config (secrets-management.nix)
│   ├── Git credential helper: calls rbw dynamically
│   ├── GH CLI: uses token from rbw
│   └── No secrets on disk (fetched on-demand)
│
└── SOPS Mode (alternative)
    ├── Uses existing sops config (sops-nix.nix)
    ├── Git credential helper: reads sops secret
    ├── GH CLI: uses token from sops secret
    └── Encrypted secret on disk
```

### Integration Points

**1. Extends `programs.git` (home/common/git.nix)**
```nix
programs.git = {
  enable = true;
  userName = "timblaktu";
  userEmail = "timblaktu@gmail.com";

  # NEW: GitHub auth integration
  extraConfig = mkIf config.githubAuth.enable {
    credential.helper = [
      "cache --timeout=3600"  # 1 hour in-memory cache
      config.githubAuth.credentialHelper  # rbw or sops backend
    ];
  };
};
```

**2. Configures `programs.gh`**
```nix
programs.gh = mkIf config.githubAuth.enable {
  enable = true;
  gitProtocol = config.githubAuth.protocol;  # "https" or "ssh"

  # Token sourced from rbw or sops based on mode
  settings = {
    git_protocol = config.githubAuth.protocol;
  };
};
```

**3. Uses Existing Secret Backends**
```nix
# Bitwarden mode: leverage secrets-management.nix
home.activation.githubAuthRbw = mkIf (cfg.mode == "bitwarden") {
  # Simple: just call 'rbw get github-token'
  # No custom scripts, no complex logic
};

# SOPS mode: leverage sops-nix
sops.secrets."github-token" = mkIf (cfg.mode == "sops") {
  path = "${config.home.homeDirectory}/.config/github/token";
};
```

### Configuration Interface

**Simple Enable (Default Settings)**:
```nix
# In home/modules/base.nix or user config
githubAuth.enable = true;  # That's it!
```

**Full Customization**:
```nix
githubAuth = {
  enable = true;
  mode = "bitwarden";  # or "sops"
  protocol = "https";  # or "ssh"

  bitwarden = {
    tokenName = "github-token";  # Entry name in Bitwarden
    folder = "Infrastructure/Tokens";
  };

  # OR

  sops = {
    secretName = "github_token";
    secretsFile = ../../secrets/common/github.yaml;
  };

  git = {
    enableCredentialHelper = true;
    cacheTimeout = 3600;  # 1 hour
  };

  gh = {
    enable = true;
    enableAliases = true;
  };
};
```

---

## Implementation Plan

### Phase 1: Create New Module ✅ READY TO IMPLEMENT

**File**: `home/modules/github-auth.nix`

**Structure**:
```nix
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.githubAuth;

  # Credential helper for Bitwarden mode
  rbwCredentialHelper = pkgs.writeShellScript "git-credential-rbw" ''
    # Simple wrapper: read operation from stdin, call rbw
    case "$1" in
      get) rbw get ${cfg.bitwarden.tokenName} ;;
      store|erase) exit 0 ;;  # No-op for rbw
    esac
  '';

  # Credential helper for SOPS mode
  sopsCredentialHelper = pkgs.writeShellScript "git-credential-sops" ''
    # Simple wrapper: read from sops secret file
    case "$1" in
      get) cat ${config.sops.secrets."${cfg.sops.secretName}".path} ;;
      store|erase) exit 0 ;;  # No-op for sops
    esac
  '';

in {
  options.githubAuth = {
    # See detailed options below
  };

  config = mkIf cfg.enable {
    # Integration with programs.git
    # Integration with programs.gh
    # Mode-specific configuration
  };
}
```

**Key Features**:
- ~150 lines total (down from 500+)
- No activation scripts (pure declarative)
- Leverages existing nixpkgs modules
- Works on all hosts automatically

### Phase 2: Integration ✅ READY TO IMPLEMENT

**1. Enable in Base Module**
```nix
# home/modules/base.nix
{
  imports = [
    # ... existing imports ...
    ./github-auth.nix  # ADD THIS
  ];

  # Optional: expose enable option
  options.homeBase.enableGithubAuth = mkOption {
    type = types.bool;
    default = false;
    description = "Enable GitHub authentication";
  };

  config = {
    githubAuth.enable = cfg.enableGithubAuth;
  };
}
```

**2. Configure in User Config**
```nix
# home/tim.nix or in homeBase configuration
{
  homeBase.enableGithubAuth = true;

  # Optional overrides
  githubAuth = {
    mode = "bitwarden";
    bitwarden.tokenName = "github-token";
  };

  # rbw already configured via secrets-management.nix
  secretsManagement.rbw.email = "timblaktu@gmail.com";
}
```

### Phase 3: Cleanup ✅ READY TO IMPLEMENT

**Remove Old Files**:
```bash
git rm modules/nixos/bitwarden-github-auth.nix
git rm modules/nixos/github-auth.nix
git rm hosts/thinky-nixos/github-auth.nix
git rm docs/GITHUB-AUTH-SETUP.md
git rm QUICK-GITHUB-AUTH-SETUP.md
```

**Archive Documentation**:
```bash
mv docs/GITHUB-AUTH-SETUP.md .archive/github-auth-setup-OLD-2025-11-20.md
mv QUICK-GITHUB-AUTH-SETUP.md .archive/quick-github-auth-OLD-2025-11-20.md
```

### Phase 4: Documentation ✅ READY TO IMPLEMENT

**Create New Docs**:
1. `docs/GITHUB-AUTH.md` - Comprehensive guide (focus on usage, not implementation)
2. `QUICK-START-GITHUB.md` - 2-minute setup guide
3. Update `home/modules/README.md` - Document new module
4. Update `CLAUDE.md` - Mark task complete

---

## Detailed Module Specification

### Options API

```nix
options.githubAuth = {
  enable = mkEnableOption "GitHub authentication";

  mode = mkOption {
    type = types.enum [ "bitwarden" "sops" ];
    default = "bitwarden";
    description = "Secret backend to use for GitHub token";
  };

  protocol = mkOption {
    type = types.enum [ "https" "ssh" ];
    default = "https";
    description = "Git protocol for GitHub operations";
  };

  bitwarden = {
    tokenName = mkOption {
      type = types.str;
      default = "github-token";
      description = "Bitwarden entry name for GitHub token";
    };

    folder = mkOption {
      type = types.nullOr types.str;
      default = "Infrastructure/Tokens";
      description = "Bitwarden folder containing token";
    };
  };

  sops = {
    secretName = mkOption {
      type = types.str;
      default = "github_token";
      description = "Secret name in SOPS file";
    };

    secretsFile = mkOption {
      type = types.path;
      default = ../../secrets/common/github.yaml;
      description = "Path to SOPS secrets file";
    };
  };

  git = {
    enableCredentialHelper = mkOption {
      type = types.bool;
      default = true;
      description = "Configure git credential helper";
    };

    cacheTimeout = mkOption {
      type = types.int;
      default = 3600;
      description = "Credential cache timeout in seconds";
    };

    userName = mkOption {
      type = types.str;
      default = "token";
      description = "Username for HTTPS authentication";
    };
  };

  gh = {
    enable = mkOption {
      type = types.bool;
      default = true;
      description = "Configure GitHub CLI (gh)";
    };

    enableAliases = mkOption {
      type = types.bool;
      default = true;
      description = "Enable useful gh aliases";
    };
  };
};
```

### Implementation Logic

```nix
config = mkIf cfg.enable {
  # Ensure dependencies
  home.packages = with pkgs; [
    git
    (mkIf cfg.gh.enable gh)
    (mkIf (cfg.mode == "bitwarden") rbw)
    (mkIf (cfg.mode == "sops") sops)
  ];

  # Git credential configuration
  programs.git.extraConfig = mkIf cfg.git.enableCredentialHelper {
    credential = {
      helper = [
        "cache --timeout=${toString cfg.git.cacheTimeout}"
        (if cfg.mode == "bitwarden" then rbwCredentialHelper else sopsCredentialHelper)
      ];
      "https://github.com" = {
        username = cfg.git.userName;
      };
    };
  };

  # GitHub CLI configuration
  programs.gh = mkIf cfg.gh.enable {
    enable = true;
    gitProtocol = cfg.protocol;

    settings = {
      git_protocol = cfg.protocol;
      # Token authentication handled by git credential helper
    };

    aliases = mkIf cfg.gh.enableAliases {
      co = "pr checkout";
      pv = "pr view";
      rv = "repo view";
    };
  };

  # Mode-specific configuration
  home.activation.githubAuthBitwarden = mkIf (cfg.mode == "bitwarden")
    (lib.hm.dag.entryAfter ["writeBoundary"] ''
      # Verify rbw is unlocked (informational only, don't fail)
      if ! ${pkgs.rbw}/bin/rbw unlocked >/dev/null 2>&1; then
        echo "Note: Bitwarden vault is locked. Run 'rbw unlock' for GitHub auth."
      fi
    '');

  sops.secrets."${cfg.sops.secretName}" = mkIf (cfg.mode == "sops") {
    sopsFile = cfg.sops.secretsFile;
    path = "${config.home.homeDirectory}/.config/github/token";
    mode = "0600";
  };

  # Assertions
  assertions = [
    {
      assertion = cfg.mode == "bitwarden" -> config.secretsManagement.enable;
      message = "githubAuth with bitwarden mode requires secretsManagement.enable = true";
    }
    {
      assertion = cfg.mode == "sops" -> (config.sops.age.keyFile or null) != null;
      message = "githubAuth with sops mode requires SOPS age key configuration";
    }
  ];

  # Warnings
  warnings =
    optional (cfg.mode == "bitwarden" && config.secretsManagement.rbw.email == null)
      "githubAuth: bitwarden mode enabled but secretsManagement.rbw.email not set";
};
```

---

## Testing Strategy

### Manual Testing Checklist

**Prerequisites**:
```bash
# Ensure branch is correct
git branch --show-current  # Should be: claude/review-pa161878-01BN7oP9qR4p8N6a9YZZufa8

# Ensure rbw is configured
rbw unlocked || rbw unlock

# Ensure token exists in Bitwarden
rbw get github-token  # Should output your token
```

**Test 1: Basic Enable (Bitwarden Mode)**
```nix
# In home configuration
githubAuth.enable = true;
```

```bash
# Build and switch
home-manager switch --flake '.#tim@thinky-nixos'

# Verify git credential helper
git config --get-all credential.helper
# Should show: cache --timeout=3600
# Should show: /nix/store/.../git-credential-rbw

# Test authentication
git ls-remote https://github.com/timblaktu/private-repo
# Should succeed without password prompt (if vault unlocked)

# Test gh CLI
gh auth status
# Should show: ✓ Logged in to github.com
```

**Test 2: SOPS Mode**
```nix
githubAuth = {
  enable = true;
  mode = "sops";
};
```

```bash
# Create SOPS secret
echo "github_token: ghp_YOUR_TOKEN" > secrets/common/github.yaml
sops -e -i secrets/common/github.yaml

# Build and switch
home-manager switch --flake '.#tim@thinky-nixos'

# Verify secret deployed
cat ~/.config/github/token  # Should show your token

# Test git operations
git clone https://github.com/timblaktu/private-repo
```

**Test 3: Multi-Host Verification**
```bash
# On thinky-nixos
home-manager switch --flake '.#tim@thinky-nixos'
gh auth status  # Should work

# On pa161878-nixos (different host)
home-manager switch --flake '.#tim@pa161878-nixos'
gh auth status  # Should also work (no additional config needed!)
```

### Automated Testing

**NixOS Test** (optional, for CI):
```nix
# tests/github-auth.nix
import ./make-test-python.nix {
  name = "github-auth";

  nodes.machine = { ... }: {
    imports = [ ../home/modules/github-auth.nix ];

    users.users.testuser.isNormalUser = true;

    home-manager.users.testuser = {
      githubAuth = {
        enable = true;
        mode = "sops";
      };
    };
  };

  testScript = ''
    machine.wait_for_unit("multi-user.target")

    # Verify git credential helper configured
    machine.succeed("sudo -u testuser git config --get credential.helper")

    # Verify gh installed
    machine.succeed("sudo -u testuser which gh")
  '';
}
```

---

## Migration Guide

### For Users of Old Implementation

**Before** (per-host configuration):
```nix
# hosts/thinky-nixos/default.nix
imports = [
  ./github-auth.nix  # Host-specific
];

# hosts/pa161878-nixos/default.nix
imports = [
  ./github-auth.nix  # Must duplicate!
];
```

**After** (single user configuration):
```nix
# home/modules/base.nix or home/tim.nix
githubAuth.enable = true;
# Works on ALL hosts automatically!
```

**Migration Steps**:
1. Remove host-specific imports
2. Enable in user's home configuration
3. Remove old host-specific config files
4. Verify token in Bitwarden/SOPS
5. Test on each host

---

## Benefits Summary

### Code Quality
- ✅ **70% less code** (150 lines vs 500+ lines)
- ✅ **Zero activation scripts** (pure declarative)
- ✅ **No custom bash** (uses built-in tools)
- ✅ **Proper module scope** (home-manager not NixOS)

### User Experience
- ✅ **Configure once, works everywhere** (no per-host setup)
- ✅ **Simpler enable** (single option vs multiple files)
- ✅ **Better error messages** (assertions and warnings)
- ✅ **Faster deployment** (no heavy activation scripts)

### Maintainability
- ✅ **Follows nixcfg patterns** (like secrets-management.nix)
- ✅ **Leverages nixpkgs modules** (programs.git, programs.gh)
- ✅ **Clear separation** (user vs system concerns)
- ✅ **Easy to test** (declarative configuration)

### Security
- ✅ **Same security model** (rbw or sops, no change)
- ✅ **Less custom code** (fewer attack surfaces)
- ✅ **Proper credential caching** (git's built-in cache)
- ✅ **No plaintext secrets** (same as before)

---

## Rollback Plan

If issues arise during implementation:

**Step 1**: Keep old implementation in archive
```bash
git mv modules/nixos/bitwarden-github-auth.nix .archive/
git mv modules/nixos/github-auth.nix .archive/
# Don't delete, just archive
```

**Step 2**: Feature flag for rollback
```nix
# home/modules/base.nix
githubAuth.implementation = mkOption {
  type = types.enum [ "new" "legacy" ];
  default = "new";
};
```

**Step 3**: Gradual rollout
- Test on single host first (thinky-ubuntu standalone)
- Then WSL hosts
- Finally NixOS hosts

---

## Success Criteria

Implementation is complete when:

1. ✅ New module created in `home/modules/github-auth.nix`
2. ✅ Old modules removed from `modules/nixos/`
3. ✅ Works on at least 2 different hosts without per-host config
4. ✅ Both bitwarden and sops modes tested
5. ✅ `nix flake check` passes
6. ✅ Documentation updated
7. ✅ Manual testing checklist completed
8. ✅ Changes committed and pushed

---

## References

### Existing Patterns to Follow
- `home/modules/secrets-management.nix` - rbw configuration
- `home/common/git.nix` - git configuration
- `modules/nixos/bitwarden-ssh-keys.nix` - Bitwarden integration (but note: this should also be home-manager eventually)

### Nixpkgs Documentation
- `programs.git` - https://github.com/nix-community/home-manager/blob/master/modules/programs/git.nix
- `programs.gh` - https://github.com/nix-community/home-manager/blob/master/modules/programs/gh.nix
- SOPS home-manager - https://github.com/Mic92/sops-nix

### Git Credential Helpers
- Official docs: https://git-scm.com/docs/gitcredentials
- Credential cache: https://git-scm.com/docs/git-credential-cache
- Custom helpers: https://git-scm.com/docs/git-credential

---

**End of Redesign Plan**
