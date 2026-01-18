# Claude Code & OpenCode SOPS Integration Plan

**Status**: Planning Phase
**Created**: 2026-01-16
**Target**: Q1 2026

## Executive Summary

This plan extends Claude Code and OpenCode modules to support **dual-mode secret management**:
1. **Runtime fetching** (current, default) - Secrets retrieved via `rbw` at command execution
2. **Build-time baking** (new) - Secrets decrypted via `sops-nix` during system activation

Both modes will be available simultaneously, with runtime fetching as the default for maximum flexibility.

---

## Background

### Current Implementation (Runtime Only)

**How it works now:**
```
User runs: claudework or opencodework
  ↓
Wrapper script executes
  ↓
Script calls: rbw get "PAC Code Companion v2" "API Key"
  ↓
Bitwarden CLI fetches secret (requires unlock)
  ↓
Export ANTHROPIC_API_KEY=$token
  ↓
Launch claude/opencode with token in environment
```

**Advantages:**
- ✅ Instant token rotation (no rebuild)
- ✅ Works on any system with rbw
- ✅ No secrets on disk (memory only)

**Disadvantages:**
- ❌ Requires Bitwarden unlock per session
- ❌ Network dependency for first unlock
- ❌ Doesn't work on systems without rbw (e.g., locked-down corporate)

### Proposed Addition (Build-Time via SOPS)

**How it will work:**
```
User runs: home-manager switch
  ↓
sops-nix decrypts secrets/claude-tokens.yaml
  ↓
Secrets written to /run/user/1000/secrets/
  ├── claude-work-token (mode 400, owner: user)
  ├── opencode-work-token
  └── ...
  ↓
User runs: claudework or opencodework
  ↓
Wrapper script reads: cat /run/user/1000/secrets/claude-work-token
  ↓
Export ANTHROPIC_API_KEY=$token
  ↓
Launch claude/opencode
```

**Advantages:**
- ✅ No unlock required (secrets already decrypted)
- ✅ Works offline
- ✅ Faster launch time (no rbw call)
- ✅ Centralized secret management

**Disadvantages:**
- ❌ Requires rebuild for token rotation
- ❌ Secrets on disk (but in tmpfs with proper permissions)
- ❌ Requires sops-nix setup (age keys)

---

## Design Goals

1. **Backward Compatibility** - Existing rbw configurations continue working
2. **Zero Breaking Changes** - Defaults remain unchanged
3. **Clear Migration Path** - Easy opt-in to SOPS mode
4. **Dual Mode Support** - Both modes can coexist (e.g., work via SOPS, personal via rbw)
5. **Fail-Safe Behavior** - Clear error messages when neither mode is configured

---

## Architecture

### Module Option Structure

```nix
# New options added to claude-code.nix and opencode.nix
accounts.<name>.secrets = {
  # Existing runtime fetching (default)
  bearerToken.bitwarden = {
    item = "PAC Code Companion v2";
    field = "API Key";
  };

  # NEW: Build-time SOPS support
  bearerToken.sops = {
    enable = false;  # Default: use rbw
    secretName = "claude-work-token";  # Key in sops secrets file
    # Optional: custom sops file (defaults to account.sopsFile or global defaultSopsFile)
    sopsFile = null;
  };
};
```

### Secret Priority Resolution

When launching a command, wrapper scripts check in this order:

1. **SOPS Path** (if `bearerToken.sops.enable = true`)
   - Read from `config.sops.secrets."${secretName}".path`
   - If file doesn't exist → error with migration instructions

2. **RBW Fetch** (if `bearerToken.bitwarden` is configured)
   - Call `rbw get <item> <field>`
   - If rbw not found or unlock fails → error with setup instructions

3. **No Secret Source** → error

---

## Implementation Phases

### Phase 1: Module Options & Logic (Week 1)

**Files to modify:**
- `home/modules/claude-code.nix` - Add `bearerToken.sops` submodule
- `home/modules/opencode.nix` - Add `bearerToken.sops` submodule
- `home/modules/claude-code/lib.nix` - Update `mkClaudeWrapperScript`

**Changes:**

1. **Add SOPS options to account submodule**:
```nix
secrets.bearerToken.sops = mkOption {
  type = types.submodule {
    options = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Use SOPS for build-time secret management instead of runtime rbw";
      };

      secretName = mkOption {
        type = types.str;
        description = "Name of secret in sops configuration (e.g., 'claude-work-token')";
      };

      sopsFile = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = "Custom SOPS file (null = use account/global default)";
      };
    };
  };
  default = { enable = false; };
  description = "SOPS-based secret management (alternative to runtime rbw)";
};
```

2. **Update wrapper script generation** (lib.nix:56-89):
```nix
# Current rbw logic becomes conditional
(lib.optionalString (authMethod == "bearer" && bearerToken != null) (
  let
    useSops = bearerToken.sops.enable or false;
    useBitwarden = (bearerToken.bitwarden or null) != null && !useSops;
  in
  if useSops then
    # NEW: SOPS mode
    ''
      # Retrieve API key from SOPS-decrypted secret file
      SOPS_SECRET_PATH="/run/user/$(id -u)/secrets/${bearerToken.sops.secretName}"
      if [[ -f "$SOPS_SECRET_PATH" ]]; then
        ANTHROPIC_API_KEY="$(cat "$SOPS_SECRET_PATH")"
        export ANTHROPIC_API_KEY
      else
        echo "Error: SOPS secret not found: $SOPS_SECRET_PATH" >&2
        echo "   Ensure sops.secrets.\"${bearerToken.sops.secretName}\" is configured" >&2
        echo "   Run: home-manager switch --flake .#$(hostname)" >&2
        exit 1
      fi
    ''
  else if useBitwarden then
    # EXISTING: RBW mode (current implementation)
    ''
      if command -v rbw >/dev/null 2>&1; then
        ANTHROPIC_API_KEY="$(rbw get ...)" || { ... }
        export ANTHROPIC_API_KEY
      else
        echo "Error: rbw (Bitwarden CLI) is required but not found" >&2
        exit 1
      fi
    ''
  else
    ''
      echo "Error: No secret source configured for account ${account}" >&2
      echo "   Configure either bearerToken.bitwarden or bearerToken.sops" >&2
      exit 1
    ''
))
```

### Phase 2: SOPS Secret Definitions (Week 2)

**Files to create/modify:**
- `secrets/common/claude-tokens.yaml` - Encrypted secret file
- `home/modules/base.nix` - Wire up SOPS secrets

**Steps:**

1. **Create encrypted secrets file**:
```bash
cd /home/tim/src/nixcfg/secrets/common
cp example.yaml.template claude-tokens.yaml

# Edit with SOPS (auto-encrypts on save)
sops claude-tokens.yaml
```

**File format** (`claude-tokens.yaml`):
```yaml
# Work account tokens (Code-Companion proxy)
claude-work-token: "sk-ant-..."  # Retrieved from Bitwarden manually
opencode-work-token: "sk-ant-..."

# Personal accounts (optional - usually use rbw for these)
# claude-max-token: "sk-ant-..."
# claude-pro-token: "sk-ant-..."
```

2. **Configure SOPS secrets in NixOS** (base.nix or host config):
```nix
{ config, ... }:
{
  # Enable sops-nix
  sopsNix = {
    enable = true;
    defaultSopsFile = ../../secrets/common/claude-tokens.yaml;
  };

  # Define secrets for home-manager user
  sops.secrets."claude-work-token" = {
    owner = config.users.users.tim.name;
    mode = "0400";
  };

  sops.secrets."opencode-work-token" = {
    owner = config.users.users.tim.name;
    mode = "0400";
  };
}
```

3. **Update account configurations** (base.nix):
```nix
programs.claude-code-enhanced.accounts.work = {
  enable = true;
  displayName = "Work Code-Companion";
  api = { ... };

  # SWITCH from rbw to SOPS
  secrets.bearerToken = {
    # Option A: Remove bitwarden config
    # bitwarden = { ... };  # Commented out

    # Option B: Keep bitwarden as fallback
    bitwarden = {
      item = "PAC Code Companion v2";
      field = "API Key";
    };

    # Enable SOPS (takes precedence)
    sops = {
      enable = true;
      secretName = "claude-work-token";
    };
  };
};

programs.opencode-enhanced.accounts.work = {
  # ... same pattern ...
  secrets.bearerToken.sops = {
    enable = true;
    secretName = "opencode-work-token";
  };
};
```

### Phase 3: Documentation & Examples (Week 2)

**Files to create:**
- `docs/claude-opencode-secrets-guide.md` - User guide
- `home/modules/claude-code/README-SECRETS.md` - Technical reference

**Content:**

1. **Comparison table** (rbw vs SOPS)
2. **Migration guide** (rbw → SOPS)
3. **Hybrid setup examples** (work=SOPS, personal=rbw)
4. **Troubleshooting** (permission errors, missing secrets)
5. **Security considerations** (tmpfs, file permissions, key management)

### Phase 4: Testing & Validation (Week 3)

**Test scenarios:**

1. **SOPS-only mode**
   - Configure work account with SOPS
   - Verify wrapper reads from /run/user/.../secrets/
   - Test failure modes (missing secret, wrong permissions)

2. **RBW-only mode** (existing, verify not broken)
   - Ensure current configurations still work
   - Test rbw fetch logic

3. **Hybrid mode**
   - work account: SOPS
   - max account: rbw
   - Verify both work correctly

4. **Error handling**
   - Neither SOPS nor rbw configured → clear error
   - SOPS enabled but secret file missing → migration instructions
   - rbw configured but not unlocked → setup instructions

---

## Migration Path for Users

### Existing Users (rbw → SOPS)

**Current setup** (base.nix):
```nix
programs.claude-code-enhanced.accounts.work = {
  secrets.bearerToken.bitwarden = {
    item = "PAC Code Companion v2";
    field = "API Key";
  };
};
```

**Step 1**: Fetch token from Bitwarden and add to SOPS:
```bash
# Get current token
TOKEN=$(rbw get "PAC Code Companion v2" "API Key")

# Create/edit SOPS file
cd ~/src/nixcfg/secrets/common
sops claude-tokens.yaml
# Add: claude-work-token: "<paste $TOKEN here>"
```

**Step 2**: Configure SOPS secret in NixOS:
```nix
sops.secrets."claude-work-token" = {
  owner = "tim";
  mode = "0400";
};
```

**Step 3**: Enable SOPS mode:
```nix
programs.claude-code-enhanced.accounts.work = {
  secrets.bearerToken = {
    bitwarden = { ... };  # Keep as fallback or remove
    sops = {
      enable = true;
      secretName = "claude-work-token";
    };
  };
};
```

**Step 4**: Rebuild and test:
```bash
home-manager switch --flake .#tim@thinky-nixos
claudework  # Should work without rbw unlock
```

---

## Security Considerations

### SOPS Mode Security

**Threat Model**:
- ✅ **Protected from**: Disk compromise (secrets encrypted at rest)
- ✅ **Protected from**: Unauthorized users (file permissions 400, tmpfs)
- ⚠️ **Vulnerable to**: Local privilege escalation (root can read tmpfs)
- ⚠️ **Vulnerable to**: Memory dumps while claude/opencode running

**Mitigations**:
1. Secrets in tmpfs (/run/user/UID/ - RAM only, cleared on reboot)
2. File permissions: 400 (owner read-only)
3. Age key protection: `/etc/sops/age.key` (root only, 600)
4. Audit trail: Nix activation logs record secret deployments

### Comparison: SOPS vs RBW

| Aspect | SOPS (Build-Time) | RBW (Runtime) |
|--------|-------------------|----------------|
| **At Rest** | Encrypted (age) | Encrypted (Bitwarden) |
| **In Transit** | Local only | TLS to Bitwarden |
| **At Runtime** | File on tmpfs | Environment variable |
| **Persistence** | Until reboot | Until command exits |
| **Access Control** | File permissions | Bitwarden 2FA + unlock |
| **Audit Trail** | Nix logs | Bitwarden access logs |

**Recommendation**: Use SOPS for long-lived tokens (work account), RBW for personal accounts requiring frequent rotation.

---

## Open Questions & Decisions

### Q1: Should we support ANTHROPIC_BASE_URL from SOPS?

**Current**: Base URL is hardcoded in Nix config
**Proposal**: Also support SOPS-based URL for full secret management

```nix
api.baseUrl.sops = {
  enable = false;
  secretName = "claude-work-base-url";
};
```

**Decision**: DEFER to Phase 2+. Base URLs are not secret, hardcoding is fine.

### Q2: Should SOPS mode require explicit opt-in or auto-detect?

**Option A** (current plan): Explicit `sops.enable = true`
**Option B**: Auto-detect if `config.sops.secrets."${secretName}"` exists

**Decision**: Stick with explicit opt-in for clarity and predictability.

### Q3: What happens if both SOPS and rbw are configured?

**Current plan**: SOPS takes precedence if enabled
**Alternative**: Error if both are configured (force user to choose)

**Decision**: SOPS precedence allows graceful migration (add SOPS, test, then remove rbw).

---

## Success Criteria

- [ ] No breaking changes to existing rbw configurations
- [ ] SOPS mode works for work account (claudework, opencodework)
- [ ] Hybrid mode works (work=SOPS, max/pro=rbw)
- [ ] Clear error messages for all failure modes
- [ ] Documentation complete with migration guide
- [ ] All tests pass (existing + new SOPS tests)

---

## References

- **Existing SOPS Infrastructure**: `secrets/SECRETS-MANAGEMENT.md`
- **Current rbw Implementation**: `home/modules/claude-code/lib.nix:56-89`
- **SOPS-NiX Module**: `modules/nixos/sops-nix.nix`
- **SSH Key SOPS Pattern**: `modules/nixos/bitwarden-ssh-keys.nix` (similar dual-mode approach)

---

## Timeline

| Week | Phase | Deliverables |
|------|-------|--------------|
| Week 1 | Module Options & Logic | Updated claude-code.nix, opencode.nix, lib.nix |
| Week 2 | SOPS Setup & Config | claude-tokens.yaml, base.nix updates, examples |
| Week 2 | Documentation | Secrets guide, migration instructions |
| Week 3 | Testing & Validation | Test suite, verify all modes work |

**Target Completion**: End of Week 3 (Q1 2026)

---

## Next Steps

1. **Review this plan** - Get user approval for approach
2. **Create feature branch** - `feature/claude-opencode-sops-integration`
3. **Implement Phase 1** - Module options and wrapper logic
4. **Test incrementally** - Verify each phase before proceeding
5. **Document as we go** - Keep docs in sync with implementation

---

**End of Plan**
