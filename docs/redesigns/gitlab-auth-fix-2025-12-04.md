# GitLab CLI Authentication Fix - 2025-12-04

## Problem Statement

Current implementation (commit efd64fb) writes GitLab tokens to `~/.config/glab-cli/config.yml` at home-manager switch time. This is an anti-pattern:

**Issues**:
1. ❌ Token written to disk becomes stale if changed in Bitwarden
2. ❌ Token sits on disk between switches (security risk)
3. ❌ File is "managed" but contains runtime secrets (violates declarative principles)
4. ❌ Doesn't match our existing gh pattern (which is correct)

## Research Findings

### GitLab CLI (glab) Authentication Methods

**Official documentation**: https://github.com/gl-cli/glab/blob/main/README.md

**Supported authentication** (in precedence order):
1. **Environment variable** (`GITLAB_TOKEN`) - checked FIRST
2. **Configuration file** (`~/.config/glab-cli/config.yml`) - fallback
3. No git credential helper integration (glab does NOT read from git)
4. No external credential provider API

**Key environment variables**:
- `GITLAB_TOKEN` - authentication token, overrides config file
- `GITLAB_HOST` - GitLab instance (defaults to gitlab.com)
- `GITLAB_API_HOST` - separate API endpoint if needed

### Real-World Pattern: 1Password Integration

**Reference**: https://developer.1password.com/docs/cli/shell-plugins/gitlab/

1Password integrates with glab using:
- **Shell plugin** that injects `GITLAB_TOKEN` environment variable at runtime
- **On-demand credential fetching** (biometric auth when command runs)
- **No token storage** in glab config file
- **No credential helper protocol** - just env var injection

This is EXACTLY the pattern we should use with rbw.

### Git Credential Helper Clarification

**Important**: `glab auth git-credential` is for Git to use glab's token, NOT for glab to read from git credential helpers. The credential flow is one-way: glab → git (not git → glab).

## Correct Solution

### Pattern: Mirror GitHub CLI (gh) Implementation

**Current gh implementation (CORRECT)**:
```nix
programs.zsh.shellAliases.gh =
  "GH_TOKEN=\"$(${mkRbwCommand cfg.bitwarden} 2>/dev/null)\" ${pkgs.gh}/bin/gh";
```

**Proposed glab implementation (SAME PATTERN)**:
```nix
programs.zsh.shellAliases.glab =
  "GITLAB_TOKEN=\"$(${mkRbwCommand cfg.gitlab.bitwarden} 2>/dev/null)\" ${pkgs.glab}/bin/glab";
```

### Configuration File Changes

**Config file should NOT include token field**:
```yaml
# GitLab CLI configuration
# Token provided via GITLAB_TOKEN environment variable at runtime
host: git.panasonic.aero
hosts:
  git.panasonic.aero:
    git_protocol: https
    api_protocol: https
    # NO token field here!
display_hyperlinks: true
glamour_style: dark
editor: nvim
```

### Why This Works

1. ✅ **glab checks GITLAB_TOKEN first** (documented precedence)
2. ✅ **Token fetched at runtime** from Bitwarden (never stale)
3. ✅ **No secrets on disk** (secure)
4. ✅ **Matches gh pattern** (consistency)
5. ✅ **Proven by 1Password** (real-world validation)

## Implementation Plan

### Phase 1: Revert Token Storage (IMMEDIATE)

**File**: `home/modules/github-auth.nix`

1. **Remove token fetching from activation script**:
   ```nix
   home.activation.glabConfig = mkIf (cfg.gitlab.enable && cfg.gitlab.glab.enable)
     (lib.hm.dag.entryAfter [ "linkGeneration" ] ''
       mkdir -p "$HOME/.config/glab-cli"
       CONFIG_FILE="$HOME/.config/glab-cli/config.yml"

       # Remove symlink if it exists
       if [ -L "$CONFIG_FILE" ]; then
         rm -f "$CONFIG_FILE"
       fi

       # Create config WITHOUT token field
       cat > "$CONFIG_FILE" <<EOF
   # GitLab CLI configuration
   # Token provided via GITLAB_TOKEN environment variable at runtime
   host: ${cfg.gitlab.host}
   hosts:
     ${cfg.gitlab.host}:
       git_protocol: ${cfg.protocol}
       api_protocol: https
   display_hyperlinks: true
   glamour_style: dark
   editor: ${config.home.sessionVariables.EDITOR or "vim"}
   EOF
       chmod 600 "$CONFIG_FILE"
       $DRY_RUN_CMD echo "✅ GitLab CLI configured for ${cfg.gitlab.host} (token via env var)"
     '');
   ```

2. **Restore shell aliases** (bash and zsh):
   ```nix
   programs.bash.shellAliases = mkMerge [
     (mkIf cfg.gh.enable {
       gh = "GH_TOKEN=\"$(${mkRbwCommand cfg.bitwarden} 2>/dev/null)\" ${pkgs.gh}/bin/gh";
     })
     (mkIf (cfg.gitlab.enable && cfg.gitlab.glab.enable) {
       glab = "GITLAB_TOKEN=\"$(${mkRbwCommand cfg.gitlab.bitwarden} 2>/dev/null)\" ${pkgs.glab}/bin/glab";
     })
   ];

   programs.zsh.shellAliases = mkMerge [
     (mkIf cfg.gh.enable {
       gh = "GH_TOKEN=\"$(${mkRbwCommand cfg.bitwarden} 2>/dev/null)\" ${pkgs.gh}/bin/gh";
     })
     (mkIf (cfg.gitlab.enable && cfg.gitlab.glab.enable) {
       glab = "GITLAB_TOKEN=\"$(${mkRbwCommand cfg.gitlab.bitwarden} 2>/dev/null)\" ${pkgs.glab}/bin/glab";
     })
   ];
   ```

### Phase 2: Testing Validation

**Test cases**:
1. ✅ `glab auth status` - should show authenticated via env var
2. ✅ `glab api user` - should return username
3. ✅ `glab project list --member` - should show projects
4. ✅ Config file has no token field
5. ✅ Token never written to disk

### Phase 3: Git Credential Helper (ALREADY WORKING)

**No changes needed** - git credential helper already configured:
```nix
credential."https://${cfg.gitlab.host}" = {
  username = cfg.gitlab.git.userName;
  helper = rbwGitlabCredentialHelper;
};
```

This handles git clone/push/pull operations separately from glab CLI.

## Security Comparison

### ❌ Current (BAD) - Token on Disk
```
home-manager switch → fetch token → write to ~/.config/glab-cli/config.yml
                      ↑ token stale until next switch
                      ↑ token readable on disk (mode 600)
```

### ✅ Proposed (GOOD) - Runtime Fetching
```
glab command → shell alias → fetch token → inject GITLAB_TOKEN → glab runs
               ↑ token fetched fresh every time
               ↑ token never touches disk
               ↑ token only in process memory
```

## Lessons Learned

1. **Always check environment variable support first** - most CLIs support this
2. **External credential providers are rare** - env vars are the standard pattern
3. **Mirror existing patterns** - gh and glab should work the same way
4. **Research before implementing** - understand tool's auth precedence
5. **Security over convenience** - runtime fetching is always better than storage

## References

- [glab CLI Documentation](https://docs.gitlab.com/cli/)
- [glab README - Authentication](https://github.com/gl-cli/glab/blob/main/README.md#authentication)
- [1Password GitLab Integration](https://developer.1password.com/docs/cli/shell-plugins/gitlab/)
- [glab man pages](https://linuxcommandlibrary.com/man/glab-auth)
