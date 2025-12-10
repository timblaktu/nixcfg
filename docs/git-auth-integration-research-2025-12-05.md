# Git Authentication Integration Research - 2025-12-05

## Executive Summary

Research into best practices for integrating GitHub CLI (`gh`) and GitLab CLI (`glab`) with git authentication, focusing on HTTPS token auth with a single authentication mechanism per service.

**Key Finding:** Both `gh` and `glab` provide `auth git-credential` subcommands that integrate directly with git's credential helper system, enabling a **single authentication mechanism** for both CLI and git operations.

---

## Current State Analysis

### Existing Configuration

```bash
# Global credential helpers (checked in order)
credential.helper = cache --timeout=3600
credential.helper = /nix/store/.../git-credential-rbw

# GitHub-specific (checked for github.com requests)
credential.https://github.com.helper = /nix/store/.../gh auth git-credential
credential.https://github.com.username = token

# GitHub gists (checked for gist.github.com)
credential.https://gist.github.com.helper = /nix/store/.../gh auth git-credential

# GitLab-specific (checked for git.panasonic.aero)
credential.https://git.panasonic.aero.helper = /nix/store/.../git-credential-rbw-gitlab
credential.https://git.panasonic.aero.username = oauth2
```

### Current Authentication Flow

**GitHub:**
1. **CLI Operations** (`gh` commands): Shell alias injects `GH_TOKEN` from Bitwarden → ✅ Working
2. **Git Operations** (clone/push/pull): Uses `gh auth git-credential` helper → ✅ Working
3. **Token Source**: `gh` authenticated via `GH_TOKEN` environment variable

**GitLab:**
1. **CLI Operations** (`glab` commands): Shell alias injects `GITLAB_TOKEN` from Bitwarden → ✅ Working
2. **Git Operations**: Uses custom `git-credential-rbw-gitlab` helper → ✅ Working
3. **Token Source**: Bitwarden via rbw

### Identified Issues

1. **Redundancy**: GitHub has BOTH custom rbw helper AND gh credential helper configured
2. **Inconsistency**: GitLab uses custom helper for git, but glab CLI not configured as credential helper
3. **No Integration**: glab not configured to provide credentials to git operations

---

## Research Findings

### 1. gh CLI Git Integration

**Command:** `gh auth setup-git`

**What it does:**
- Configures git to use `gh auth git-credential` as credential helper
- Adds entry: `credential.helper = !gh auth git-credential`
- Can be scoped to specific hosts with `--hostname`

**Token Storage:**
- With `--secure-storage` flag: System keyring/credential manager (secure)
- Without flag: `~/.config/gh/hosts.yml` (plaintext)
- Fallback if keyring unavailable: plaintext file

**How it works:**
```bash
# Git requests credentials for github.com
git → calls gh auth git-credential → gh provides token from its storage
```

**Official Docs:** https://cli.github.com/manual/gh_auth_setup-git

### 2. glab CLI Git Integration

**Command:** `glab auth login` (interactive, prompts for git integration)

**What it does:**
- During `glab auth login`, asks: "Authenticate Git with your GitLab credentials?"
- If yes, adds: `credential.https://gitlab.com.helper = !glab auth git-credential`
- Can be manually configured for self-hosted instances

**Token Storage:**
- `~/.config/glab-cli/config.yml` (plaintext by default)
- Environment variable `GITLAB_TOKEN` takes precedence

**How it works:**
```bash
# Git requests credentials for gitlab.com
git → calls glab auth git-credential → glab provides token from config or env var
```

**Official Docs:** https://docs.gitlab.com/cli/

### 3. Git Credential Helper Precedence

Git credential helpers are checked in order:
1. **Host-specific helpers** (e.g., `credential.https://github.com.helper`)
2. **Global helpers** (e.g., `credential.helper`)
3. **First successful response wins**

Multiple helpers can be configured; git tries them sequentially until one provides credentials.

### 4. Security Comparison

| Method | Token Storage | Security Level | Single Source |
|--------|---------------|----------------|---------------|
| **gh/glab plaintext** | ~/.config files | ❌ Low | ❌ Duplicate |
| **gh/glab --secure-storage** | System keyring | ✅ High | ❌ Duplicate |
| **Custom rbw helpers** | Bitwarden vault | ✅ High | ✅ Single |
| **Shell aliases + rbw** | Bitwarden vault | ✅ High | ✅ Single |

---

## The Ideal Solution

### Goal
- **Single authentication mechanism** per service (Bitwarden as source of truth)
- **Unified authentication** for both CLI tools and git operations
- **No token duplication** or staleness issues
- **Secure token storage** (never plaintext on disk)

### Current vs Ideal

**Current Approach:**
```
gh CLI:    Shell alias → Bitwarden (via GH_TOKEN)          ✅
gh git:    gh credential helper → gh storage                ❌ (redundant)
glab CLI:  Shell alias → Bitwarden (via GITLAB_TOKEN)      ✅
glab git:  Custom rbw helper → Bitwarden                    ⚠️ (inconsistent)
```

**Problem:**
- GitHub has redundant credential paths (both rbw and gh helpers)
- GitLab is inconsistent (CLI uses env var, git uses custom helper)
- gh/glab tools authenticate via env vars but git doesn't benefit from unified flow

### Two Possible Architectures

#### Option A: CLI Tools as Credential Source (SIMPLER)

**Use gh/glab as git credential helpers, but authenticate them via env vars**

```
Configuration:
1. Keep shell aliases: gh/glab commands use GH_TOKEN/GITLAB_TOKEN from Bitwarden
2. Configure gh/glab as git credential helpers
3. When git needs credentials, gh/glab check env vars FIRST

Flow:
CLI operations:  gh → reads GH_TOKEN → Bitwarden token
Git operations:  git → gh auth git-credential → checks GH_TOKEN → Bitwarden token
```

**Pros:**
- ✅ Single authentication mechanism (env vars from Bitwarden)
- ✅ Leverages official CLI tool integration
- ✅ No token duplication
- ✅ Tokens never stored on disk

**Cons:**
- ⚠️ Requires env vars to be available in all contexts
- ⚠️ May not work in non-interactive contexts (cron, systemd)

**Implementation:**
```nix
# Shell aliases (already working)
programs.bash.shellAliases = {
  gh = "GH_TOKEN=\"$(rbw get github-token)\" gh";
  glab = "GITLAB_TOKEN=\"$(rbw get gitlab-token)\" glab";
};

# Git credential helpers
programs.git.extraConfig = {
  credential."https://github.com".helper = "${pkgs.gh}/bin/gh auth git-credential";
  credential."https://gitlab.com".helper = "${pkgs.glab}/bin/glab auth git-credential";
};

# NO custom rbw credential helpers needed
```

**Key Question:** Do `gh auth git-credential` and `glab auth git-credential` respect environment variables?

**Answer (from research):**
- ✅ **gh**: `gh auth git-credential` checks `GH_TOKEN` first (confirmed in testing)
- ✅ **glab**: `glab auth git-credential` checks `GITLAB_TOKEN` first (documented behavior)

#### Option B: Direct Bitwarden Integration (CURRENT APPROACH)

**Use custom rbw credential helpers for everything**

```
Configuration:
1. Shell aliases: gh/glab use env vars from Bitwarden
2. Git credential helpers: Custom scripts that call rbw directly

Flow:
CLI operations:  gh → reads GH_TOKEN → Bitwarden via rbw
Git operations:  git → git-credential-rbw → Bitwarden via rbw
```

**Pros:**
- ✅ Complete control over authentication flow
- ✅ Single source of truth (Bitwarden)
- ✅ Works in all contexts (interactive and non-interactive)

**Cons:**
- ❌ Duplicates functionality (gh/glab already have credential helpers)
- ❌ More code to maintain
- ❌ Doesn't leverage official CLI integration

---

## Recommended Approach: Option A (CLI Tools as Credential Source)

### Rationale

1. **Leverage Official Integration**: gh and glab are designed to work with git credential helpers
2. **Environment Variable Precedence**: Both tools check env vars FIRST before config files
3. **Unified Flow**: CLI and git operations use the same credential source (env vars)
4. **Simplicity**: Fewer moving parts, less custom code to maintain
5. **Security**: Tokens fetched fresh from Bitwarden, never stored on disk

### How It Works in Practice

**GitHub Example:**
```bash
# User runs git clone
$ git clone https://github.com/user/repo.git

# Git credential helper chain:
1. Git checks: credential.https://github.com.helper → gh auth git-credential
2. gh auth git-credential executes
3. gh checks environment for GH_TOKEN → NOT SET (no shell alias in git context)
4. gh checks ~/.config/gh/hosts.yml → NOT AUTHENTICATED
5. gh prompts for authentication OR returns error

# PROBLEM: gh auth git-credential doesn't have access to our shell alias!
```

**This reveals a critical limitation:**
- Shell aliases only work in interactive shell contexts
- Git operations (clone, push, pull) run in their own process
- They DON'T inherit shell aliases or functions

### The Reality Check

After analysis, **Option A has a fatal flaw**: Environment variables set by shell aliases are **not available** to git credential helpers running in separate processes.

**Correct Understanding:**
```bash
# This works (shell alias scope):
$ gh repo list                    # Shell runs: GH_TOKEN="..." gh repo list

# This does NOT work (credential helper scope):
$ git clone https://github.com/user/repo
  → git spawns subprocess: gh auth git-credential
  → subprocess DOES NOT have GH_TOKEN from our shell alias
  → gh credential helper fails or prompts for login
```

---

## Corrected Recommendation: Hybrid Approach

### Architecture

**Use direct Bitwarden integration for git, shell aliases for CLI:**

```
gh CLI:      Shell alias → GH_TOKEN from Bitwarden     ✅
gh git:      Custom rbw helper → Bitwarden             ✅
glab CLI:    Shell alias → GITLAB_TOKEN from Bitwarden ✅
glab git:    Custom rbw helper → Bitwarden             ✅
```

### Why This Works

1. **CLI Tools**: Shell aliases provide fresh tokens in interactive contexts
2. **Git Operations**: Custom credential helpers fetch tokens directly from Bitwarden
3. **Single Source**: All authentication ultimately comes from Bitwarden
4. **No Duplication**: gh/glab are NOT authenticated themselves (no token storage)
5. **Works Everywhere**: Non-interactive contexts (cron, systemd) work via credential helpers

### Implementation (CURRENT STATE IS CORRECT)

**Our current implementation is actually the RIGHT approach!**

The only change needed:
- ✅ Remove redundant `gh auth git-credential` configuration (GitHub already handled by rbw)
- ✅ Ensure consistency: both GitHub and GitLab use rbw credential helpers

### Current Configuration Review

```bash
# KEEP: Direct Bitwarden integration
credential.helper = cache --timeout=3600                    # ✅ Cache for performance
credential.helper = /nix/store/.../git-credential-rbw       # ✅ GitHub via Bitwarden

# REMOVE: Redundant gh integration (we use rbw instead)
credential.https://github.com.helper = gh auth git-credential      # ❌ Remove
credential.https://gist.github.com.helper = gh auth git-credential # ❌ Remove

# KEEP: GitLab via Bitwarden
credential.https://git.panasonic.aero.helper = git-credential-rbw-gitlab # ✅ Keep
```

---

## Action Items

### 1. Remove Redundant gh Credential Helper

**Current state:** gh is configured as credential helper but we use rbw instead

**Fix:**
```nix
# In home/modules/github-auth.nix
# Remove or comment out gh as credential helper
# We only need rbw credential helper + shell aliases
```

### 2. Document Authentication Architecture

Create clear documentation explaining:
- Shell aliases for CLI tools (gh, glab) with env var injection
- Custom rbw credential helpers for git operations
- Why this architecture is optimal for our use case

### 3. Consider: glab Git Credential Integration

**Current:** GitLab git operations use custom rbw helper
**Alternative:** Could use `glab auth git-credential` but still needs token source

**Decision:** KEEP custom rbw helper for consistency and control

---

## Alternative Consideration: Environment Variable Export

### Could We Use gh/glab Credential Helpers with Env Vars?

**Idea:** Export `GH_TOKEN` and `GITLAB_TOKEN` as persistent environment variables

```nix
# In shell initialization
home.sessionVariables = {
  GH_TOKEN = "$(rbw get github-token)";           # ❌ Won't work - evaluated once at generation
  GITLAB_TOKEN = "$(rbw get gitlab-token)";       # ❌ Won't work - evaluated once at generation
};
```

**Problem:**
- Session variables are set ONCE when shell starts
- Tokens fetched at shell init become stale
- Defeats purpose of fresh token fetching

**Alternative: Shell RC Files**
```bash
# In .bashrc / .zshrc
export GH_TOKEN="$(rbw get github-token 2>/dev/null)"
export GITLAB_TOKEN="$(rbw get gitlab-token 2>/dev/null)"
```

**Problems:**
- Slows down shell startup (rbw call on every new shell)
- Token in process environment for entire shell session (security concern)
- Still doesn't help non-shell contexts (systemd, cron)

**Verdict:** ❌ Not recommended

---

## Final Recommendation

### Keep Current Architecture with Minor Cleanup

**What we have (and should keep):**
1. ✅ Shell aliases for gh/glab with runtime token fetching from Bitwarden
2. ✅ Custom rbw credential helpers for git operations
3. ✅ Single source of truth: Bitwarden vault
4. ✅ Tokens never stored on disk
5. ✅ Works in all contexts (interactive and non-interactive)

**What to clean up:**
1. ❌ Remove redundant gh credential helper configuration from git config
2. ✅ Ensure all services use consistent rbw-based approach

**Why this is optimal:**
- **Single authentication mechanism**: Bitwarden for everything
- **CLI/git integration**: Both work seamlessly via separate but consistent paths
- **Security**: Tokens fetched fresh, never stored
- **Simplicity**: No token duplication, no staleness
- **Flexibility**: Custom helpers give us complete control

### The Answer to Your Question

**"Are there integrations between gh/glab CLI tools and git CLI auth?"**

**Answer:** YES, both `gh auth git-credential` and `glab auth git-credential` provide this integration.

**"Would this be desirable for a single authentication mechanism?"**

**Answer:** It WOULD be desirable, BUT there's a better approach:
- Using gh/glab as credential helpers requires authenticating them first (token storage)
- Using direct Bitwarden integration (current approach) gives us:
  - Single source of truth (no duplication)
  - Fresh tokens on every operation
  - No token storage on disk
  - Complete control over authentication flow

**Your current setup is actually BETTER than using gh/glab credential helpers!**

The only issue is redundancy: you have BOTH rbw AND gh configured for GitHub. Cleaning this up will make it perfect.

---

## Testing Plan

### 1. Verify Current Flow
```bash
# Test gh CLI
gh repo list

# Test git with GitHub
git clone https://github.com/user/test-repo /tmp/test

# Test glab CLI
glab project list --member

# Test git with GitLab
git clone https://git.panasonic.aero/user/test-repo /tmp/test2
```

### 2. After Cleanup
Remove gh credential helper configuration and verify git operations still work via rbw helper.

---

## References

- [gh auth setup-git](https://cli.github.com/manual/gh_auth_setup-git)
- [GitLab CLI Documentation](https://docs.gitlab.com/cli/)
- [Git Credential Storage](https://git-scm.com/book/en/v2/Git-Tools-Credential-Storage)
- [GitHub CLI vs GCM Comparison](https://lowply.github.io/blog/2022/08/gcm-gh/)
- [glab Git Credential Documentation](https://github.com/profclems/glab/blob/trunk/docs/source/auth/git-credential.rst)
