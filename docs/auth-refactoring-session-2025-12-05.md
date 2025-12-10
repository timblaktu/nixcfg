# Authentication Architecture Refactoring - Fresh Session Prompt

## Context

We need to refactor the git authentication architecture in `home/modules/github-auth.nix` to eliminate configuration redundancy and leverage official gh/glab credential helper integration.

## Background Research

**Research completed in commit `ec60b30`:**
- Comprehensive analysis in `docs/git-auth-integration-research-2025-12-05.md`
- Both `gh` and `glab` provide `auth git-credential` subcommands
- Current implementation has configuration redundancy (Bitwarden item/field in 2 places)
- GitLab CLI fix completed in commit `5be4f25` (runtime env var injection working)

## Current State

**Branch**: `claude/review-pa161878-01BN7oP9qR4p8N6a9YZZufa8`

**Current Architecture (Redundant)**:
```nix
# Place 1: Shell aliases
shellAliases.gh = "GH_TOKEN=\"$(rbw get ...)\" gh";
shellAliases.glab = "GITLAB_TOKEN=\"$(rbw get ...)\" glab";

# Place 2: Custom credential helpers (DUPLICATE CONFIG)
rbwCredentialHelper = writeShellScript "git-credential-rbw" ''
  TOKEN=$(rbw get ...)  # SAME Bitwarden config again!
'';
rbwGitlabCredentialHelper = writeShellScript "git-credential-rbw-gitlab" ''
  TOKEN=$(rbw get ...)  # SAME Bitwarden config again!
'';
```

**Current Git Config**:
```bash
# Redundant: BOTH rbw helper AND gh credential helper for GitHub
credential.helper = /nix/store/.../git-credential-rbw
credential.https://github.com.helper = gh auth git-credential  # Unused!

# GitLab uses custom helper (no glab integration)
credential.https://git.panasonic.aero.helper = git-credential-rbw-gitlab
```

## Proposed Solution: Wrapper Scripts

**Key Insight**: Create wrapper scripts that inject tokens from Bitwarden, then use those wrappers for BOTH CLI and git credential operations.

### Architecture

```nix
let
  # Single definition of where to get tokens (ONE place per service)
  gh-with-auth = pkgs.writeShellScriptBin "gh" ''
    export GH_TOKEN="$(${mkRbwCommand cfg.bitwarden} 2>/dev/null)"
    exec ${pkgs.gh}/bin/gh "$@"
  '';

  glab-with-auth = pkgs.writeShellScriptBin "glab" ''
    export GITLAB_TOKEN="$(${mkRbwCommand cfg.gitlab.bitwarden} 2>/dev/null)"
    exec ${pkgs.glab}/bin/glab "$@"
  '';
in {
  # Wrappers become the actual commands (NO shell aliases needed)
  home.packages = [ gh-with-auth glab-with-auth ];

  # Use same wrappers for git credential helpers
  programs.git.extraConfig = {
    # Remove cache and custom rbw helper (redundant)
    # Use wrapped gh/glab which inject tokens from Bitwarden
    credential."https://github.com".helper = "!${gh-with-auth}/bin/gh auth git-credential";
    credential."https://gist.github.com".helper = "!${gh-with-auth}/bin/gh auth git-credential";
    credential."https://${cfg.gitlab.host}".helper = "!${glab-with-auth}/bin/glab auth git-credential";
  };
}
```

### How It Works

**CLI operations**:
```bash
$ gh repo list
→ gh-with-auth wrapper runs
→ fetches token from Bitwarden via rbw
→ exports GH_TOKEN
→ execs real gh binary
→ gh sees GH_TOKEN and uses it
```

**Git operations**:
```bash
$ git clone https://github.com/user/repo
→ git calls credential helper: gh auth git-credential
→ gh-with-auth wrapper runs (same script!)
→ fetches token from Bitwarden via rbw
→ exports GH_TOKEN
→ execs gh auth git-credential
→ gh sees GH_TOKEN and provides it to git
```

## Implementation Steps

### 1. Create Wrapper Scripts

In `home/modules/github-auth.nix`, in the `let` block:

```nix
# GitHub CLI wrapper with Bitwarden token injection
gh-with-auth = pkgs.writeShellScriptBin "gh" ''
  export GH_TOKEN="$(${mkRbwCommand cfg.bitwarden} 2>/dev/null)"
  exec ${pkgs.gh}/bin/gh "$@"
'';

# GitLab CLI wrapper with Bitwarden token injection
glab-with-auth = pkgs.writeShellScriptBin "glab" ''
  export GITLAB_TOKEN="$(${mkRbwCommand cfg.gitlab.bitwarden} 2>/dev/null)"
  exec ${pkgs.glab}/bin/glab "$@"
'';
```

### 2. Install Wrappers

Replace shell aliases with wrapper packages:

```nix
# OLD: Shell aliases (remove)
# programs.bash.shellAliases = mkMerge [ ... ];
# programs.zsh.shellAliases = mkMerge [ ... ];

# NEW: Install wrappers as actual commands
home.packages = mkMerge [
  (mkIf cfg.gh.enable [ gh-with-auth ])
  (mkIf (cfg.gitlab.enable && cfg.gitlab.glab.enable) [ glab-with-auth ])
];
```

### 3. Configure Git Credential Helpers

Replace custom rbw helpers with wrappers:

```nix
programs.git.extraConfig = mkMerge [
  (mkIf cfg.git.enableCredentialHelper {
    credential = {
      # Remove custom rbw helper
      # OLD: helper = [
      #   "cache --timeout=${toString cfg.git.cacheTimeout}"
      #   "${rbwCredentialHelper}"
      # ];

      # NEW: Let gh/glab handle credentials via wrappers
      "https://github.com" = {
        username = cfg.git.userName;
        helper = "!${gh-with-auth}/bin/gh auth git-credential";
      };
      "https://gist.github.com" = {
        helper = "!${gh-with-auth}/bin/gh auth git-credential";
      };
    };
  })
  (mkIf (cfg.gitlab.enable && cfg.gitlab.git.enableCredentialHelper) {
    credential."https://${cfg.gitlab.host}" = {
      username = cfg.gitlab.git.userName;
      # Remove custom rbw helper, use wrapped glab
      helper = "!${glab-with-auth}/bin/glab auth git-credential";
    };
  })
];
```

### 4. Remove Custom Credential Helpers

Delete these from the `let` block:
- `rbwCredentialHelper` (and its SOPS variant)
- `rbwGitlabCredentialHelper` (and its SOPS variant)

These are ~200 lines of custom code that are no longer needed.

### 5. Keep Config File Generation

The glab config file activation script should remain (creates `~/.config/glab-cli/config.yml` without token).

## Testing Plan

### 1. Build and Switch
```bash
nix flake check
home-manager switch --flake .#tim@thinky-nixos
```

### 2. Test CLI Operations
```bash
# Test gh (should fetch token from Bitwarden)
gh repo list

# Test glab (should fetch token from Bitwarden)
glab project list --member
```

### 3. Test Git Operations
```bash
# Test GitHub git operations
git clone https://github.com/timblaktu/test-repo /tmp/test-gh
cd /tmp/test-gh
echo "test" >> README.md
git commit -am "test"
git push

# Test GitLab git operations
git clone https://git.panasonic.aero/user/test-repo /tmp/test-gl
# Similar push test
```

### 4. Verify Configuration
```bash
# Check git config
git config --list | grep credential

# Should show:
# credential.https://github.com.helper=!/nix/store/.../gh auth git-credential
# credential.https://git.panasonic.aero.helper=!/nix/store/.../glab auth git-credential

# Should NOT show custom rbw helpers anymore
```

## Expected Outcomes

**Code Reduction**:
- Remove ~200 lines of custom credential helper code
- Remove shell aliases (replaced by wrappers)
- Net reduction: ~150 lines

**Configuration Simplification**:
- Bitwarden item/field specified ONCE per service (in wrapper only)
- Same wrapper used for both CLI and git
- No duplication, easier to maintain

**Functional Equivalence**:
- ✅ CLI tools work exactly as before
- ✅ Git operations work exactly as before
- ✅ Tokens fetched fresh from Bitwarden
- ✅ No tokens stored on disk
- ✅ Same security properties

## Important Notes

### ⚠️ Concurrent Claude Session Warning

**DO NOT MODIFY** any marker-pdf related files. Another Claude session is actively working on marker-pdf enhancements. Only modify:
- `home/modules/github-auth.nix`
- Documentation files (if needed)

### Current Branch

Work on branch: `claude/review-pa161878-01BN7oP9qR4p8N6a9YZZufa8`

This branch already has:
- GitLab auth fix (commit `5be4f25`)
- tomd implementation (commits `a4c4a71`, `6d931da`)
- Research document (commit `ec60b30`)

### After Implementation

1. Run `nix flake check` to validate
2. Test both CLI and git operations thoroughly
3. Commit changes with descriptive message
4. Update CLAUDE.md to mark task as complete

## Success Criteria

- ✅ All tests pass
- ✅ Code is cleaner (fewer lines, no duplication)
- ✅ Configuration is simpler (one source per service)
- ✅ Functionality is identical to before
- ✅ `nix flake check` passes
- ✅ Git operations work for both GitHub and GitLab

## Reference Documents

- **Research**: `docs/git-auth-integration-research-2025-12-05.md`
- **Current Module**: `home/modules/github-auth.nix`
- **GitLab Fix**: commit `5be4f25`
- **Research Commit**: commit `ec60b30`

---

## Quick Start Command

After starting fresh session, use this prompt:

```
I need to refactor the git authentication architecture in home/modules/github-auth.nix
to eliminate configuration redundancy. Read docs/auth-refactoring-session-2025-12-05.md
for complete context and implementation plan. Current branch: claude/review-pa161878-01BN7oP9qR4p8N6a9YZZufa8

Key points:
- Replace custom rbw credential helpers with wrapper scripts
- Wrappers inject tokens from Bitwarden and use official gh/glab credential helpers
- Same wrapper used for both CLI and git operations
- Eliminates duplication (Bitwarden config in ONE place per service)
- Reduces code by ~150 lines

DO NOT touch marker-pdf files (concurrent session working on that).

Please implement the refactoring following the detailed steps in the session prompt.
```
