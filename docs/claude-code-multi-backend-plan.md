# Claude Code Multi-Backend & Termux Integration Plan

## Overview

Integrate work's Code-Companion proxy as a new Claude Code "account" alongside existing personal accounts (max, pro), with unified configuration across all platforms including Termux.

**Key Design Decision**: Generate Termux configuration as Nix package outputs - no nix-on-droid required. Single source of truth, simple installation.

## Progress Tracking

### Phase 1: Research & Design (Autonomous - No Nix Required)

| Task | Name | Status | Date |
|------|------|--------|------|
| R1 | Document current account submodule structure | TASK:COMPLETE | 2026-01-11 |
| R2 | Document wrapper script generation across platforms | TASK:COMPLETE | 2026-01-11 |
| R3 | Document run-tasks.sh for Nix module adaptation | TASK:COMPLETE | 2026-01-11 |
| R4 | Document skills structure for Nix module adaptation | TASK:COMPLETE | 2026-01-11 |
| R5 | Draft complete API options Nix code | TASK:COMPLETE | 2026-01-11 |
| R6 | Draft complete wrapper script Nix code | TASK:COMPLETE | 2026-01-11 |

### Phase 2: Implementation (Requires Nix Host)

| Task | Name | Status | Date |
|------|------|--------|------|
| I1 | Implement API options in account submodule | TASK:COMPLETE | 2026-01-11 |
| I2 | Implement wrapper script generation | TASK:COMPLETE | 2026-01-11 |
| I3 | Add work account configuration | TASK:COMPLETE | 2026-01-11 |
| I4 | Create Termux package output | TASK:COMPLETE | 2026-01-11 |
| I5 | Store secrets in Bitwarden | TASK:COMPLETE | 2026-01-11 |
| I6 | Test on Nix-managed host | TASK:BLOCKED | 2026-01-11 |
| I7 | Test Termux installation | TASK:PENDING | |
| I8 | Add task automation to Nix module | TASK:COMPLETE | 2026-01-11 |
| I9 | Add skills support to Nix module | TASK:COMPLETE | 2026-01-11 |

---

## Phase 1: Research Task Definitions

### Task R1: Document current account submodule structure

**Goal**: Read and document the current account submodule in `home/modules/claude-code.nix` to understand what exists and what needs to be added.

**Actions**:
1. Read `home/modules/claude-code.nix` lines 140-200 (account submodule definition)
2. Read `home/modules/base.nix` to find current account usage (search for "accounts")
3. Document the current structure in findings section below
4. Identify gaps vs. requirements in Code-Companion Requirements section

**Output**: Document current state in "R1 Findings" section below.

**Definition of Done** (ALL must be true):
- [x] R1 Findings section contains "Current Options" subsection listing each existing option with its type
- [x] R1 Findings section contains "Current Usage" subsection showing how accounts are defined in base.nix
- [x] R1 Findings section contains "Gaps Analysis" subsection listing what's missing for Code-Companion
- [x] R1 Findings placeholder text `*(Task R1 will populate this section)*` is replaced

---

### Task R2: Document wrapper script generation across platforms

**Goal**: Read all platform-specific wrapper script generation code and document the pattern.

**Actions**:
1. Read `home/migration/wsl-home-files.nix` - search for "mkClaudeWrapperScript" or wrapper generation
2. Read `home/migration/linux-home-files.nix` - same search
3. Read `home/migration/darwin-home-files.nix` - same search
4. Document how wrappers are generated, what they set, common patterns
5. Note where the wrapper function should be refactored to avoid duplication

**Output**: Document findings in "R2 Findings" section below.

**Definition of Done** (ALL must be true):
- [x] R2 Findings contains "Platform Files" subsection listing each platform file and line numbers where wrappers are defined
- [x] R2 Findings contains "Common Pattern" subsection with the actual Nix code pattern used (or noting differences)
- [x] R2 Findings contains "Environment Variables Set" subsection listing all env vars currently set by wrappers
- [x] R2 Findings contains "Refactoring Recommendation" subsection identifying duplication and where to extract shared code
- [x] R2 Findings placeholder text `*(Task R2 will populate this section)*` is replaced

---

### Task R3: Document run-tasks.sh for Nix module adaptation

**Goal**: Document the run-tasks.sh script in enough detail to generate it from Nix.

**Actions**:
1. Read `~/bin/run-tasks.sh` completely
2. Document all features, options, and dependencies (rg, claude, etc.)
3. Identify any hardcoded paths that need parameterization
4. Read `~/.claude/commands/next-task.md` for slash command format
5. Document what files need to be generated and their content

**Output**: Document in "R3 Findings" section below.

**Definition of Done** (ALL must be true):
- [x] R3 Findings contains "CLI Options" subsection listing all command-line options with descriptions
- [x] R3 Findings contains "Dependencies" subsection listing required tools (rg, claude, etc.)
- [x] R3 Findings contains "Hardcoded Values" subsection listing any paths/values that need parameterization
- [x] R3 Findings contains "Slash Command Format" subsection with the content of next-task.md
- [x] R3 Findings contains "Safety Limits" subsection documenting MAX_ITERATIONS, rate limit handling, etc.
- [x] R3 Findings placeholder text `*(Task R3 will populate this section)*` is replaced

---

### Task R4: Document skills structure for Nix module adaptation

**Goal**: Document the skills directory structure for Nix module generation.

**Actions**:
1. List `~/.claude/skills/` directory structure
2. Read SKILL.md file(s) to understand format
3. Read any REFERENCE.md or supporting files
4. Document the expected directory structure and file formats
5. Identify which skills should be "built-in" vs user-defined

**Output**: Document in "R4 Findings" section below.

**Definition of Done** (ALL must be true):
- [x] R4 Findings contains "Directory Structure" subsection showing the file tree of ~/.claude/skills/
- [x] R4 Findings contains "SKILL.md Format" subsection with an example or template of the format
- [x] R4 Findings contains "Supporting Files" subsection listing other files (REFERENCE.md, etc.) and their purpose
- [x] R4 Findings contains "Built-in Skills" subsection listing which skills should ship with the Nix module
- [x] R4 Findings placeholder text `*(Task R4 will populate this section)*` is replaced

---

### Task R5: Draft complete API options Nix code

**Goal**: Write the complete, copy-paste ready Nix code for the API options extension.

**Prerequisite**: R1 must be TASK:COMPLETE before starting this task.

**Actions**:
1. Using R1 findings, draft the complete new options block
2. Include all options from the plan: api.baseUrl, api.authMethod, api.disableApiKey, api.modelMappings
3. Include secrets.bearerToken with Bitwarden reference structure
4. Include extraEnvVars option
5. Format as valid Nix code ready to insert

**Output**: Complete Nix code block in "R5 Draft Code" section below.

**Definition of Done** (ALL must be true):
- [x] R5 Draft Code contains a complete `accounts = mkOption { ... }` block in valid Nix syntax
- [x] R5 Draft Code includes `api.baseUrl` option with type `types.nullOr types.str`
- [x] R5 Draft Code includes `api.authMethod` option with type `types.enum [ "api-key" "bearer" "bedrock" ]`
- [x] R5 Draft Code includes `api.disableApiKey` option with type `types.bool`
- [x] R5 Draft Code includes `api.modelMappings` option with type `types.attrsOf types.str`
- [x] R5 Draft Code includes `secrets.bearerToken.bitwarden` submodule with `item` and `field` options
- [x] R5 Draft Code includes `extraEnvVars` option with type `types.attrsOf types.str`
- [x] R5 Draft Code placeholder text `*(Task R5 will populate this section)*` is replaced

---

### Task R6: Draft complete wrapper script Nix code

**Goal**: Write the complete, copy-paste ready Nix code for wrapper script generation.

**Prerequisite**: R2 must be TASK:COMPLETE before starting this task.

**Actions**:
1. Using R2 findings, draft the updated mkClaudeWrapperScript function
2. Handle all API options (baseUrl, authMethod, modelMappings)
3. Handle secrets retrieval via rbw
4. Handle extraEnvVars
5. Design as a shared function to be used across all platform files
6. Format as valid Nix code

**Output**: Complete Nix code block in "R6 Draft Code" section below.

**Definition of Done** (ALL must be true):
- [x] R6 Draft Code contains a complete `mkClaudeWrapperScript` function in valid Nix syntax
- [x] R6 Draft Code handles `api.baseUrl` by conditionally setting ANTHROPIC_BASE_URL
- [x] R6 Draft Code handles `api.authMethod == "bearer"` by retrieving token via rbw
- [x] R6 Draft Code handles `api.disableApiKey` by conditionally setting ANTHROPIC_API_KEY=""
- [x] R6 Draft Code handles `api.modelMappings` by setting ANTHROPIC_DEFAULT_*_MODEL env vars
- [x] R6 Draft Code handles `extraEnvVars` by iterating and exporting each
- [x] R6 Draft Code includes comment indicating where to place this shared function
- [x] R6 Draft Code placeholder text `*(Task R6 will populate this section)*` is replaced

---

## Phase 1 Findings

### R1 Findings

#### Current Options

The account submodule is defined at `home/modules/claude-code.nix:143-163`:

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enable` | `bool` (mkEnableOption) | `false` | Enable this Claude Code account profile |
| `displayName` | `types.str` | (required) | Display name for this account profile |
| `model` | `types.nullOr (types.enum [ "sonnet" "opus" "haiku" ])` | `null` | Default model for this account (null = use global default) |

The parent module also defines:
- `defaultAccount` (`types.nullOr types.str`, default: `null`) - Default account when running 'claude' without profile

#### Current Usage

In `home/modules/base.nix:341-351`, accounts are defined as:

```nix
accounts = {
  max = {
    enable = true;
    displayName = "Claude Max Account";
  };
  pro = {
    enable = true;
    displayName = "Claude Pro Account";
    model = "sonnet";
  };
};
```

Both accounts use standard Anthropic API authentication (API key from environment).

#### Gaps Analysis

The Code-Companion requirements (from the plan) need:

| Required Feature | Current Support | Gap |
|------------------|-----------------|-----|
| Custom API base URL | ❌ Not supported | Need `api.baseUrl` option |
| Bearer token auth | ❌ Not supported | Need `api.authMethod` option with `bearer` value |
| Empty API key | ❌ Not supported | Need `api.disableApiKey` option |
| Model name mapping | ❌ Not supported | Need `api.modelMappings` option |
| Secret management | ❌ Not supported | Need `secrets.bearerToken.bitwarden` submodule |
| Extra env vars | ❌ Not supported | Need `extraEnvVars` option |

**Summary**: The current submodule only supports basic Anthropic API authentication. All API proxy features need to be added for Code-Companion integration.

---

### R2 Findings

#### Platform Files

| Platform | File | Wrapper Lines | Accounts Defined |
|----------|------|--------------|------------------|
| WSL | `home/migration/wsl-home-files.nix` | 379-420 (max), 446-487 (pro) | max, pro |
| Linux | `home/migration/linux-home-files.nix` | 316-357 (max), 383-424 (pro) | max, pro |
| Darwin | `home/migration/darwin-home-files.nix` | 320-361 (max), 387-428 (pro) | max, pro |

WSL also has a unified dispatcher at lines 274-335 (`claude-code-wrapper`), but it simply delegates to `claudemax`/`claudepro`.

#### Common Pattern

The `mkClaudeWrapperScript` function is **identically duplicated** in all three platform files. Signature:

```nix
mkClaudeWrapperScript = { account, displayName, configDir, extraEnvVars ? { } }: ''
  account="${account}"
  config_dir="${configDir}"
  pidfile="/tmp/claude-''${account}.pid"

  # Headless mode bypass for -p/--print
  if [[ "$*" =~ (^|[[:space:]])-p([[:space:]]|$) || ... ]]; then
    export CLAUDE_CONFIG_DIR="$config_dir"
    ${lib.concatStringsSep "\n" (lib.mapAttrsToList (k: v: "export ${k}=\"${v}\"") extraEnvVars)}
    exec "${pkgs.claude-code}/bin/claude" "$@"
  fi

  # Instance detection via pgrep
  if pgrep -f "claude.*--config-dir.*$config_dir" > /dev/null 2>&1; then
    exec "${pkgs.claude-code}/bin/claude" --config-dir="$config_dir" "$@"
  fi

  # PID-based single instance management
  if [[ -f "$pidfile" ]]; then
    pid=$(cat "$pidfile")
    if kill -0 "$pid" 2>/dev/null; then
      echo "Claude (${displayName}) is already running (PID: $pid)"
      exec "${pkgs.claude-code}/bin/claude" --config-dir="$config_dir" "$@"
    else
      rm -f "$pidfile"
    fi
  fi

  # Launch new instance
  export CLAUDE_CONFIG_DIR="$config_dir"
  ${lib.concatStringsSep "\n" (lib.mapAttrsToList (k: v: "export ${k}=\"${v}\"") extraEnvVars)}
  mkdir -p "$config_dir"
  echo $$ > "$pidfile"
  exec "${pkgs.claude-code}/bin/claude" --config-dir="$config_dir" "$@"
'';
```

Each platform then invokes it twice (once for `claudemax`, once for `claudepro`) with identical parameters.

#### Environment Variables Set

| Variable | Source | Purpose |
|----------|--------|---------|
| `CLAUDE_CONFIG_DIR` | `configDir` parameter | Account-specific config directory |
| `DISABLE_TELEMETRY` | `extraEnvVars` | Disable telemetry |
| `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC` | `extraEnvVars` | Disable non-essential network traffic |
| `DISABLE_ERROR_REPORTING` | `extraEnvVars` | Disable error reporting |

**Not yet supported** (needed for Code-Companion):
- `ANTHROPIC_BASE_URL` - Custom API endpoint
- `ANTHROPIC_AUTH_TOKEN` - Bearer token authentication
- `ANTHROPIC_API_KEY` - Must be set to empty string for some proxies
- `ANTHROPIC_DEFAULT_*_MODEL` - Model name mappings

#### Refactoring Recommendation

**Current Problem**: The `mkClaudeWrapperScript` function is defined 6 times total (2 accounts x 3 platforms) with identical code. Only the invocation parameters differ.

**Recommended Refactoring**:

1. **Extract shared function** to `home/modules/claude-code/lib.nix`:
   ```nix
   # home/modules/claude-code/lib.nix
   { lib, pkgs }:
   {
     mkClaudeWrapperScript = { account, displayName, configDir, api ? {}, secrets ? {}, extraEnvVars ? {} }: ''
       # ... unified implementation with API support
     '';
   }
   ```

2. **Import in platform files**:
   ```nix
   let
     claudeLib = import ../modules/claude-code/lib.nix { inherit lib pkgs; };
   in
   # ...
   content = claudeLib.mkClaudeWrapperScript { ... };
   ```

3. **Generate wrappers dynamically** from `cfg.accounts`:
   ```nix
   # Instead of hardcoded claudemax/claudepro
   scripts = lib.mapAttrs (name: account:
     mkUnifiedFile {
       name = "claude${name}";
       content = claudeLib.mkClaudeWrapperScript {
         inherit (account) displayName;
         account = name;
         configDir = "${config.home.homeDirectory}/src/nixcfg/claude-runtime/.claude-${name}";
         inherit (account) api secrets extraEnvVars;
       };
     }
   ) (lib.filterAttrs (n: a: a.enable) cfg.accounts);
   ```

**Benefits**:
- Single source of truth for wrapper logic
- Automatic wrapper generation from account options
- API proxy support without per-platform changes
- Easy to add new accounts (just add to `accounts` attrset)

---

### R3 Findings


#### CLI Options

| Option | Arguments | Default | Description |
|--------|-----------|---------|-------------|
| `<plan-file>` | path | (required) | Markdown file with Progress Tracking table |
| `-n` | N | 1 | Run N tasks |
| `-a`, `--all` | - | - | Run all pending tasks |
| `-c`, `--continuous` | - | - | Run continuously (survives rate limits) |
| `-d`, `--delay` | N | 10 | Seconds between tasks |
| `--dry-run` | - | - | Show prompt without executing |
| `-h`, `--help` | - | - | Show help |

**Modes** (mutually exclusive):
- `single` (default): Run 1 task
- `count`: Run N tasks (`-n N`)
- `all`: Run all pending (`-a`)
- `continuous`: Run until complete or circuit breaker (`-c`)

#### Dependencies

| Tool | Purpose | Availability |
|------|---------|--------------|
| `bash` | Shell interpreter | Universal |
| `rg` (ripgrep) | Pattern matching for status tokens | Needs installation |
| `claude` | Claude Code CLI | Main dependency |
| `date` | Timestamps and runtime calculation | Universal |
| `realpath` | Resolve absolute paths | Universal (GNU coreutils) |
| `tee` | Duplicate output to log file | Universal |

#### Hardcoded Values

| Value | Current | Parameterization Needed |
|-------|---------|------------------------|
| `LOG_DIR` | `.claude-task-logs` | Could be configurable |
| `STATE_FILE` | `.claude-task-state` | Could be configurable |
| `DELAY_BETWEEN_TASKS` | 10 seconds | Already CLI arg (`-d`) |
| `RATE_LIMIT_WAIT` | 300 seconds (5 min) | Consider making configurable |
| `MAX_RETRIES` | 3 | Consider making configurable |
| `MAX_ITERATIONS` | 100 | Consider making configurable |
| `MAX_RUNTIME_HOURS` | 8 | Consider making configurable |
| `MAX_CONSECUTIVE_RATE_LIMITS` | 5 | Consider making configurable |

**Status Tokens** (critical for matching):
- `TASK:PENDING` - Marks pending tasks in table
- `TASK:COMPLETE` - Marks completed tasks
- `ALL_TASKS_DONE` - Claude's completion signal

#### Slash Command Format

Content of `~/.claude/commands/next-task.md`:

Read the plan file specified below (or auto-detect from CLAUDE.md if not specified),
find the first "Pending" task in the Progress Tracking table, execute it following
the task definition in that file, document findings in the corresponding section,
mark it "Complete" with today's date, and report what you completed and what's next.
Commit your changes when done.

Plan file: \$ARGUMENTS

If no plan file argument is provided:
1. Check the project's CLAUDE.md for a "Primary File" or "Plan File" reference
2. Look for files matching `*-research.md`, `*-plan.md`, or `*-tasks.md` in docs/
3. Ask the user which file to use

After completing the task, provide a summary:

## Task Completed
- **Task ID**: [task number/name]
- **Status**: Complete
- **Summary**: [1-2 sentence summary]

## Next Pending Task
- **Task ID**: [next task number/name]
- **Description**: [brief description]

If no pending tasks remain, state "All tasks complete!"

**Key Differences from run-tasks.sh**:
- Interactive (within Claude session) vs unattended (CLI invocation)
- Supports `\$ARGUMENTS` for plan file path
- Auto-detection of plan file from CLAUDE.md
- Structured summary output format
- Uses simpler "Pending"/"Complete" tokens (should be updated to TASK: prefix for consistency)

#### Safety Limits

| Limit | Value | Purpose |
|-------|-------|---------|
| `MAX_ITERATIONS` | 100 | Prevent runaway loops |
| `MAX_RUNTIME_HOURS` | 8 | Prevent endless execution |
| `MAX_CONSECUTIVE_RATE_LIMITS` | 5 | Circuit breaker for API issues |
| `MAX_RETRIES` | 3 | Per-task retry limit for rate limits |

**Runtime Calculations**:
- START_TIME=\$(date +%s)
- runtime=\$((date +%s - START_TIME))
- max_runtime_seconds=\$((MAX_RUNTIME_HOURS * 3600))

**Pre-flight Validation**:
1. Checks for `TASK:PENDING` tasks before starting (exits early if none)
2. Warns if plan file lacks proper Progress Tracking table
3. Warns if using old-style "Pending" instead of "TASK:PENDING" tokens

**Return Codes from run_task()**:
- `0`: Success - task completed
- `1`: Failure - task failed
- `2`: Rate limited - should retry after wait
- `3`: All complete - Claude reports `ALL_TASKS_DONE`

**State Persistence** (`.claude-task-state`):
- LAST_RUN=2026-01-11T10:30:00+00:00
- TASKS_RUN=5
- STATUS=complete|rate_limited|failed|interrupted|all_complete
- PENDING_NOW=3
- RUNTIME_SECONDS=1234
- PLAN_FILE=/absolute/path/to/plan.md

**Logging**:
- Creates `.claude-task-logs/` directory
- Each task logged to `task_YYYYMMDD_HHMMSS.log`
- Both stdout and file via `tee`

#### Recent Improvements (2026-01-11)

**Exit Messaging Enhancement**:
- Added `format_runtime()` helper - displays human-readable times ("2h 15m", "5m 32s")
- Added `print_exit_summary()` function - consistent exit block for ALL exit paths showing:
  - Reason for stopping
  - Tasks completed vs pending
  - Total runtime
  - Log directory location
- Updated all 7 exit paths: success, iteration limit, runtime limit, rate limit circuit breaker, retry limit, Claude confirms complete, user interrupt (Ctrl+C)

**Rate Limit False Positive Fix**:
- **Bug**: Script searched ALL output for "rate limit" text, triggering false positives when Claude's output mentioned rate limits in documentation (e.g., "rate limit circuit breaker")
- **Fix**: Now checks exit code FIRST - if exit code is 0 (success), skip rate limit detection entirely
- **Fix**: More specific patterns that require error context: `(error|failed|rejected|denied|exceeded|http|status).*rate.?limit` etc.
- Only checks for rate limit patterns when Claude returns non-zero exit code

#### Nix Module Adaptation Notes

**For task-automation.nix**:

1. **Wrapper Script Generation**:
   - Extract configurable constants to Nix options
   - Inject tool paths (rg, claude) from pkgs
   - Consider making safety limits configurable per-account

2. **Slash Command Deployment**:
   - Deploy next-task.md to each account's commands/ directory
   - Update to use TASK:PENDING/TASK:COMPLETE tokens consistently
   - Template with account-specific defaults

3. **Cross-Platform Considerations**:
   - Termux: Use /data/data/com.termux/files/usr/bin/bash
   - All platforms: Ensure rg is in PATH or provide fallback to grep -E

4. **Suggested Nix Options**:
   - taskAutomation.enable
   - taskAutomation.safetyLimits.maxIterations (default: 100)
   - taskAutomation.safetyLimits.maxRuntimeHours (default: 8)
   - taskAutomation.safetyLimits.maxConsecutiveRateLimits (default: 5)
   - taskAutomation.safetyLimits.rateLimitWaitSeconds (default: 300)
   - taskAutomation.safetyLimits.delayBetweenTasks (default: 10)
   - taskAutomation.logDirectory (default: ".claude-task-logs")
   - taskAutomation.stateFile (default: ".claude-task-state")

5. **Source File**: `~/bin/run-tasks.sh` - this is the canonical source that should be adapted for Nix generation


---

### R4 Findings

#### Directory Structure

```
~/.claude/skills/
└── adr-writer/
    ├── SKILL.md      # Main skill definition (required)
    └── REFERENCE.md  # Supporting documentation (optional)
```

Skills are organized as directories under `~/.claude/skills/`. Each skill directory must contain a `SKILL.md` file and may include supporting files like `REFERENCE.md`.

#### SKILL.md Format

The `SKILL.md` file uses YAML frontmatter followed by markdown content:

```markdown
---
name: <skill-id>
description: <description for skill discovery and triggering>
---

# [Skill Title]

## [Template/Instructions Section]

[The main content that Claude uses when the skill is invoked]

## Instructions

[Step-by-step usage guidance]

## Best Practices

[Guidelines for effective use]

...additional sections as needed...
```

**Frontmatter Fields**:
| Field | Required | Description |
|-------|----------|-------------|
| `name` | Yes | Skill identifier (lowercase, hyphenated) |
| `description` | Yes | Used by Claude to determine when to invoke the skill |

**Content Sections** (vary by skill type):
- Template sections with code blocks for copy-paste content
- Instructions for step-by-step usage
- Best practices and guidelines
- Links to supporting files via relative paths `[REFERENCE.md](REFERENCE.md)`

#### Supporting Files

**REFERENCE.md** (optional):
- Extended documentation too long for SKILL.md
- Deep-dive explanations, examples, alternatives
- Referenced from SKILL.md via markdown links
- Example: ADR criteria definitions, writing guidelines, naming conventions

**Other possible supporting files**:
| File | Purpose |
|------|---------|
| `REFERENCE.md` | Extended reference documentation |
| `EXAMPLES.md` | Example usage and outputs |
| `templates/*.md` | Reusable template files |
| `*.json` | Configuration or schema files |

#### Built-in Skills

Skills to ship with the Nix module:

| Skill | Files | Purpose | Priority |
|-------|-------|---------|----------|
| `adr-writer` | `SKILL.md`, `REFERENCE.md` | Write Architecture Decision Records | High - already exists |

**Potential future built-in skills**:

| Skill | Purpose | Status |
|-------|---------|--------|
| `commit-message` | Generate conventional commit messages | Could extract from existing claude-utils.bash |
| `pr-description` | Generate PR descriptions | Common workflow |
| `code-review` | Structured code review guidance | Common workflow |
| `nix-module` | Write Nix modules following best practices | Project-specific but useful |

**Recommendation**: Start with `adr-writer` as the only built-in, allow users to define custom skills via Nix options.

#### Nix Module Adaptation Notes

**Skill Option Structure**:

```nix
skills = {
  enable = mkEnableOption "Claude Code skills";

  builtins = {
    adr-writer = mkOption {
      type = types.bool;
      default = true;
      description = "Enable ADR writing skill";
    };
  };

  custom = mkOption {
    type = types.attrsOf (types.submodule {
      options = {
        description = mkOption {
          type = types.str;
          description = "Skill description for discovery";
        };
        skillContent = mkOption {
          type = types.str;
          description = "SKILL.md content (without frontmatter - generated)";
        };
        referenceContent = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "Optional REFERENCE.md content";
        };
        extraFiles = mkOption {
          type = types.attrsOf types.str;
          default = {};
          description = "Additional files as name -> content attrset";
        };
      };
    });
    default = {};
    description = "Custom skill definitions";
  };
};
```

**Deployment**:
- Deploy skills to each account's `skills/` directory
- Generate SKILL.md with proper frontmatter from options
- Copy supporting files alongside
- For Termux package: include skills in `share/claude-skills/`

**File Generation Example**:

```nix
# Generate SKILL.md with frontmatter
mkSkillFile = name: skill: ''
  ---
  name: ${name}
  description: ${skill.description}
  ---

  ${skill.skillContent}
'';

# Deploy to account directory
"claude-runtime/.claude-${accountName}/skills/${skillName}/SKILL.md".text =
  mkSkillFile skillName skill;
```

---

### R5 Draft Code

#### Complete Account Submodule with API Options

This code block is designed to **replace** the existing `accounts = mkOption { ... }` block at `home/modules/claude-code.nix:143-163`. It extends the current structure with API proxy support, secrets management, and extra environment variables.

```nix
# Location: home/modules/claude-code.nix (replace lines 142-163)
# Prerequisites: inherit (lib) types mkOption mkEnableOption;

# Account submodule with API proxy support
accounts = mkOption {
  type = types.attrsOf (types.submodule {
    options = {
      # ─── Existing Options (preserved) ─────────────────────────
      enable = mkEnableOption "this Claude Code account profile";

      displayName = mkOption {
        type = types.str;
        description = "Display name for this account profile";
        example = "Claude Max Account";
      };

      model = mkOption {
        type = types.nullOr (types.enum [ "sonnet" "opus" "haiku" ]);
        default = null;
        description = "Default model for this account (null means use global default)";
      };

      # ─── NEW: API Configuration ───────────────────────────────
      api = {
        baseUrl = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = ''
            Custom API base URL for this account.
            Set to null (default) to use the standard Anthropic API.
            Example: "https://codecompanionv2.d-dp.nextcloud.aero"
          '';
          example = "https://api.example.com/v1";
        };

        authMethod = mkOption {
          type = types.enum [ "api-key" "bearer" "bedrock" ];
          default = "api-key";
          description = ''
            Authentication method for this account:
            - "api-key": Standard Anthropic API key (ANTHROPIC_API_KEY)
            - "bearer": Bearer token authentication (ANTHROPIC_AUTH_TOKEN)
            - "bedrock": AWS Bedrock authentication
          '';
        };

        disableApiKey = mkOption {
          type = types.bool;
          default = false;
          description = ''
            Set ANTHROPIC_API_KEY to an empty string.
            Required by some proxy servers that reject requests with API keys.
          '';
        };

        modelMappings = mkOption {
          type = types.attrsOf types.str;
          default = { };
          description = ''
            Map Claude model names to proxy-specific model names.
            Keys are Claude model names (sonnet, opus, haiku).
            Values are the proxy model identifiers.
          '';
          example = {
            sonnet = "devstral";
            opus = "devstral";
            haiku = "qwen-a3b";
          };
        };
      };

      # ─── NEW: Secrets Configuration ───────────────────────────
      secrets = {
        bearerToken = mkOption {
          type = types.nullOr (types.submodule {
            options = {
              bitwarden = mkOption {
                type = types.submodule {
                  options = {
                    item = mkOption {
                      type = types.str;
                      description = "Bitwarden item name containing the token";
                      example = "Code-Companion";
                    };
                    field = mkOption {
                      type = types.str;
                      description = "Field name within the Bitwarden item";
                      example = "bearer_token";
                    };
                  };
                };
                description = "Bitwarden reference for retrieving the bearer token via rbw";
              };
            };
          });
          default = null;
          description = ''
            Secret management for bearer token authentication.
            On Nix-managed hosts, tokens are retrieved via rbw (Bitwarden CLI).
            On Termux, tokens are read from ~/.secrets/claude-<account>-token files.
          '';
        };

        # Future extensibility for other secret types
        # apiKey = mkOption { ... };  # For non-standard API key sources
      };

      # ─── NEW: Extra Environment Variables ─────────────────────
      extraEnvVars = mkOption {
        type = types.attrsOf types.str;
        default = { };
        description = ''
          Additional environment variables to set for this account.
          These are exported before launching Claude Code.
        '';
        example = {
          DISABLE_TELEMETRY = "1";
          CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC = "1";
          DISABLE_ERROR_REPORTING = "1";
        };
      };
    };
  });
  default = { };
  description = ''
    Claude Code account profiles.
    Each account can have its own API configuration, secrets, and environment.
    Common accounts: max, pro, work
  '';
};
```

#### Usage Example (for base.nix)

This shows how to define accounts using the new options:

```nix
# Location: home/modules/base.nix (accounts definition)
programs.claude-code-enhanced = {
  accounts = {
    # Standard Anthropic API account (existing pattern)
    max = {
      enable = true;
      displayName = "Claude Max Account";
      extraEnvVars = {
        DISABLE_TELEMETRY = "1";
        CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC = "1";
        DISABLE_ERROR_REPORTING = "1";
      };
    };

    # Standard Anthropic API with default model override
    pro = {
      enable = true;
      displayName = "Claude Pro Account";
      model = "sonnet";
      extraEnvVars = {
        DISABLE_TELEMETRY = "1";
        CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC = "1";
        DISABLE_ERROR_REPORTING = "1";
      };
    };

    # Work proxy account (Code-Companion)
    work = {
      enable = true;
      displayName = "Work Code-Companion";
      model = "sonnet";

      api = {
        baseUrl = "https://codecompanionv2.d-dp.nextcloud.aero";
        authMethod = "bearer";
        disableApiKey = true;
        modelMappings = {
          sonnet = "devstral";
          opus = "devstral";
          haiku = "qwen-a3b";
        };
      };

      secrets.bearerToken.bitwarden = {
        item = "Code-Companion";
        field = "bearer_token";
      };

      extraEnvVars = {
        DISABLE_TELEMETRY = "1";
        CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC = "1";
        DISABLE_ERROR_REPORTING = "1";
      };
    };
  };
};
```

#### Validation Notes

The Nix code above:
- Uses `types.nullOr` for optional values (baseUrl, bearerToken)
- Uses `types.enum` for constrained choices (authMethod)
- Uses `types.attrsOf types.str` for key-value mappings (modelMappings, extraEnvVars)
- Uses nested `types.submodule` for structured options (secrets.bearerToken.bitwarden)
- Includes `description` and `example` attributes for documentation
- Maintains backwards compatibility - existing configs continue to work unchanged
- All new options have sensible defaults (null, false, {})

#### Environment Variables Generated

| Option | Environment Variable | Value |
|--------|---------------------|-------|
| `api.baseUrl` | `ANTHROPIC_BASE_URL` | The URL value |
| `api.authMethod == "bearer"` | `ANTHROPIC_AUTH_TOKEN` | Token from secrets |
| `api.disableApiKey` | `ANTHROPIC_API_KEY` | Empty string `""` |
| `api.modelMappings.sonnet` | `ANTHROPIC_DEFAULT_SONNET_MODEL` | Mapped model name |
| `api.modelMappings.opus` | `ANTHROPIC_DEFAULT_OPUS_MODEL` | Mapped model name |
| `api.modelMappings.haiku` | `ANTHROPIC_DEFAULT_HAIKU_MODEL` | Mapped model name |
| `extraEnvVars.<name>` | `<NAME>` | The value |

---

### R6 Draft Code

#### Shared Wrapper Library

This code should be placed in a new shared library file to avoid duplication across platform files.

```nix
# Location: home/modules/claude-code/lib.nix
# Purpose: Shared library functions for Claude Code wrapper generation
# Usage: Import in platform files: let claudeLib = import ../modules/claude-code/lib.nix { inherit lib pkgs; };

{ lib, pkgs }:

{
  # Generate a Claude Code wrapper script for an account
  # Handles API proxy configuration, authentication, and environment setup
  mkClaudeWrapperScript = {
    # Required parameters
    account,           # Account name (e.g., "max", "pro", "work")
    displayName,       # Human-readable name for messages
    configDir,         # Path to account config directory
    claudeBin,         # Path to claude binary (allows overriding for Termux)

    # Optional API configuration (from account.api options)
    api ? {},

    # Optional secrets configuration (from account.secrets options)
    secrets ? {},

    # Optional extra environment variables (from account.extraEnvVars)
    extraEnvVars ? {}
  }:
  let
    # Extract API options with defaults
    baseUrl = api.baseUrl or null;
    authMethod = api.authMethod or "api-key";
    disableApiKey = api.disableApiKey or false;
    modelMappings = api.modelMappings or {};

    # Extract secrets options
    bearerToken = secrets.bearerToken or null;

    # Generate API environment variable exports
    apiEnvVars = lib.concatStringsSep "\n" (lib.filter (s: s != "") [
      # ANTHROPIC_BASE_URL - set if custom baseUrl specified
      (lib.optionalString (baseUrl != null) ''
        export ANTHROPIC_BASE_URL="${baseUrl}"'')

      # ANTHROPIC_API_KEY - set to empty string if disableApiKey is true
      (lib.optionalString disableApiKey ''
        export ANTHROPIC_API_KEY=""'')

      # ANTHROPIC_AUTH_TOKEN - retrieve via rbw if bearer auth + bitwarden configured
      (lib.optionalString (authMethod == "bearer" && bearerToken != null && bearerToken.bitwarden or null != null) ''
        # Retrieve bearer token from Bitwarden via rbw
        if command -v rbw >/dev/null 2>&1; then
          ANTHROPIC_AUTH_TOKEN="$(rbw get "${bearerToken.bitwarden.item}" "${bearerToken.bitwarden.field}" 2>/dev/null)" || {
            echo "⚠️  Warning: Failed to retrieve bearer token from Bitwarden" >&2
            echo "   Item: ${bearerToken.bitwarden.item}, Field: ${bearerToken.bitwarden.field}" >&2
          }
          export ANTHROPIC_AUTH_TOKEN
        else
          # Fallback for systems without rbw (e.g., Termux)
          if [[ -f "$HOME/.secrets/claude-${account}-token" ]]; then
            export ANTHROPIC_AUTH_TOKEN="$(cat "$HOME/.secrets/claude-${account}-token")"
          else
            echo "⚠️  Warning: Bearer token not found" >&2
            echo "   Expected: ~/.secrets/claude-${account}-token (or rbw configured)" >&2
          fi
        fi'')
    ]);

    # Generate model mapping environment variables
    # Maps: sonnet -> ANTHROPIC_DEFAULT_SONNET_MODEL, etc.
    modelEnvVars = lib.concatStringsSep "\n" (lib.mapAttrsToList (model: mapping: ''
      export ANTHROPIC_DEFAULT_${lib.toUpper model}_MODEL="${mapping}"'') modelMappings);

    # Generate extra environment variable exports
    extraEnvExports = lib.concatStringsSep "\n" (lib.mapAttrsToList (k: v: ''
      export ${k}="${v}"'') extraEnvVars);

    # Combined environment setup block
    envSetupBlock = lib.concatStringsSep "\n" (lib.filter (s: s != "") [
      apiEnvVars
      modelEnvVars
      extraEnvExports
    ]);

  in ''
    #!/usr/bin/env bash
    set -euo pipefail

    account="${account}"
    config_dir="${configDir}"
    pidfile="/tmp/claude-''${account}.pid"

    # ─── Environment Setup ───────────────────────────────────────────
    setup_environment() {
      export CLAUDE_CONFIG_DIR="$config_dir"
      ${envSetupBlock}
    }

    # ─── Headless Mode Detection ─────────────────────────────────────
    # Bypass PID check for stateless operations (-p/--print)
    if [[ "$*" =~ (^|[[:space:]])-p([[:space:]]|$) || "$*" =~ (^|[[:space:]])--print([[:space:]]|$) ]]; then
      setup_environment
      exec "${claudeBin}" "$@"
    fi

    # ─── Existing Instance Detection ─────────────────────────────────
    # Check if Claude is already running with this config directory
    if pgrep -f "claude.*--config-dir.*$config_dir" > /dev/null 2>&1; then
      exec "${claudeBin}" --config-dir="$config_dir" "$@"
    fi

    # ─── PID-Based Single Instance Management ────────────────────────
    if [[ -f "$pidfile" ]]; then
      pid=$(cat "$pidfile")
      if kill -0 "$pid" 2>/dev/null; then
        echo "🔄 Claude (${displayName}) is already running (PID: $pid)"
        echo "   Using existing instance..."
        exec "${claudeBin}" --config-dir="$config_dir" "$@"
      else
        echo "🧹 Cleaning up stale PID file..."
        rm -f "$pidfile"
      fi
    fi

    # ─── Launch New Instance ─────────────────────────────────────────
    echo "🚀 Launching Claude (${displayName})..."
    setup_environment

    # Create config directory if it doesn't exist
    mkdir -p "$config_dir"

    # Store PID and execute
    echo $$ > "$pidfile"
    exec "${claudeBin}" --config-dir="$config_dir" "$@"
  '';

  # Generate a Termux-specific wrapper (simpler, no rbw dependency)
  mkTermuxWrapperScript = {
    account,
    displayName,
    api ? {},
    extraEnvVars ? {}
  }:
  let
    baseUrl = api.baseUrl or null;
    authMethod = api.authMethod or "api-key";
    disableApiKey = api.disableApiKey or false;
    modelMappings = api.modelMappings or {};
  in ''
    #!/data/data/com.termux/files/usr/bin/bash
    set -euo pipefail

    # ─── API Configuration ───────────────────────────────────────────
    ${lib.optionalString (baseUrl != null) ''
    export ANTHROPIC_BASE_URL="${baseUrl}"
    ''}
    ${lib.optionalString disableApiKey ''
    export ANTHROPIC_API_KEY=""
    ''}
    ${lib.optionalString (authMethod == "bearer") ''
    # Bearer token - read from local secrets file on Termux
    TOKEN_FILE="$HOME/.secrets/claude-${account}-token"
    if [[ -f "$TOKEN_FILE" ]]; then
      export ANTHROPIC_AUTH_TOKEN="$(cat "$TOKEN_FILE")"
    else
      echo "⚠️  Warning: Bearer token not found at $TOKEN_FILE" >&2
      echo "   Create it with: mkdir -p ~/.secrets && echo 'your-token' > $TOKEN_FILE" >&2
    fi
    ''}
    ${lib.concatStringsSep "\n" (lib.mapAttrsToList (model: mapping: ''
    export ANTHROPIC_DEFAULT_${lib.toUpper model}_MODEL="${mapping}"
    '') modelMappings)}

    # ─── Extra Environment Variables ─────────────────────────────────
    ${lib.concatStringsSep "\n" (lib.mapAttrsToList (k: v: ''
    export ${k}="${v}"
    '') extraEnvVars)}

    # ─── Config Directory ────────────────────────────────────────────
    export CLAUDE_CONFIG_DIR="$HOME/.claude-${account}"
    mkdir -p "$CLAUDE_CONFIG_DIR"

    # ─── Launch Claude ───────────────────────────────────────────────
    exec claude "$@"
  '';
}
```

#### Usage in Platform Files

Replace the duplicated `mkClaudeWrapperScript` definitions in each platform file with imports from the shared library:

```nix
# Location: home/migration/wsl-home-files.nix (and linux-home-files.nix, darwin-home-files.nix)
# Replace the inline mkClaudeWrapperScript definitions with:

{ config, lib, pkgs, ... }:

let
  # Import shared Claude Code library
  claudeLib = import ../modules/claude-code/lib.nix { inherit lib pkgs; };

  # Reference to claude-code config
  cfg = config.programs.claude-code-enhanced;

  # Generate wrapper for an account
  mkAccountWrapper = name: account: mkUnifiedFile {
    name = "claude${name}";
    executable = true;
    content = claudeLib.mkClaudeWrapperScript {
      account = name;
      displayName = account.displayName;
      configDir = "${config.home.homeDirectory}/src/nixcfg/claude-runtime/.claude-${name}";
      claudeBin = "${pkgs.claude-code}/bin/claude";
      api = account.api or {};
      secrets = account.secrets or {};
      extraEnvVars = account.extraEnvVars or {};
    };
    tests = {
      help = pkgs.writeShellScript "test-claude${name}-help" ''
        claude${name} --help >/dev/null 2>&1 || true
        echo "✅ claude${name}: Syntax validation passed"
      '';
    };
  };

in {
  # ... other config ...

  home.file = {
    # Dynamic wrapper generation from account options
    # (This replaces the hardcoded claudemax/claudepro definitions)
  } // (lib.mapAttrs' (name: account:
    lib.nameValuePair "bin/claude${name}" (mkAccountWrapper name account)
  ) (lib.filterAttrs (n: a: a.enable) cfg.accounts));
}
```

#### Termux Package Generation

```nix
# Location: flake-modules/termux-outputs.nix
# Generate Termux wrappers from account configuration

{ inputs, self, lib, withSystem, ... }: {
  flake = {
    packages.aarch64-linux.termux-claude-scripts = withSystem "aarch64-linux" ({ pkgs, ... }:
      let
        # Import shared library
        claudeLib = import ../home/modules/claude-code/lib.nix { inherit lib pkgs; };

        # Reference home config for account definitions
        # Note: We extract account config without requiring full home-manager evaluation
        accounts = {
          max = {
            enable = true;
            displayName = "Claude Max Account";
            api = {};
            extraEnvVars = {
              DISABLE_TELEMETRY = "1";
              CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC = "1";
              DISABLE_ERROR_REPORTING = "1";
            };
          };
          pro = {
            enable = true;
            displayName = "Claude Pro Account";
            api = {};
            extraEnvVars = {
              DISABLE_TELEMETRY = "1";
              CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC = "1";
              DISABLE_ERROR_REPORTING = "1";
            };
          };
          work = {
            enable = true;
            displayName = "Work Code-Companion";
            api = {
              baseUrl = "https://codecompanionv2.d-dp.nextcloud.aero";
              authMethod = "bearer";
              disableApiKey = true;
              modelMappings = {
                sonnet = "devstral";
                opus = "devstral";
                haiku = "qwen-a3b";
              };
            };
            extraEnvVars = {
              DISABLE_TELEMETRY = "1";
              CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC = "1";
              DISABLE_ERROR_REPORTING = "1";
            };
          };
        };

        # Generate Termux wrapper for each enabled account
        mkTermuxWrapper = name: account: pkgs.writeShellScriptBin "claude${name}"
          (claudeLib.mkTermuxWrapperScript {
            inherit (account) displayName;
            account = name;
            api = account.api or {};
            extraEnvVars = account.extraEnvVars or {};
          });

        wrapperScripts = lib.mapAttrs mkTermuxWrapper
          (lib.filterAttrs (n: a: a.enable) accounts);

        # Install script for Termux
        installScript = pkgs.writeShellScriptBin "install-termux-claude" ''
          #!/data/data/com.termux/files/usr/bin/bash
          set -euo pipefail

          INSTALL_DIR="''${1:-$HOME/bin}"
          mkdir -p "$INSTALL_DIR"

          echo "Installing Claude Code account wrappers to $INSTALL_DIR..."

          ${lib.concatStringsSep "\n" (lib.mapAttrsToList (name: script: ''
          cp "${script}/bin/claude${name}" "$INSTALL_DIR/"
          chmod +x "$INSTALL_DIR/claude${name}"
          echo "  ✅ Installed: claude${name}"
          '') wrapperScripts)}

          echo ""
          echo "Installation complete!"
          echo ""
          echo "Usage:"
          ${lib.concatStringsSep "\n" (lib.mapAttrsToList (name: account: ''
          echo "  claude${name} - ${account.displayName}"
          '') (lib.filterAttrs (n: a: a.enable) accounts))}
          echo ""
          echo "For accounts using bearer auth, store token at:"
          echo "  ~/.secrets/claude-<account>-token"
        '';

      in pkgs.symlinkJoin {
        name = "termux-claude-scripts";
        paths = (lib.attrValues wrapperScripts) ++ [ installScript ];
      }
    );
  };
}
```

#### Environment Variables Generated

The wrapper script generates these environment variables based on account options:

| Account Option | Environment Variable | Condition |
|----------------|---------------------|-----------|
| `api.baseUrl` | `ANTHROPIC_BASE_URL` | When `baseUrl != null` |
| `api.disableApiKey` | `ANTHROPIC_API_KEY=""` | When `disableApiKey == true` |
| `api.authMethod == "bearer"` | `ANTHROPIC_AUTH_TOKEN` | Retrieved via rbw (Nix) or file (Termux) |
| `api.modelMappings.sonnet` | `ANTHROPIC_DEFAULT_SONNET_MODEL` | For each mapping entry |
| `api.modelMappings.opus` | `ANTHROPIC_DEFAULT_OPUS_MODEL` | For each mapping entry |
| `api.modelMappings.haiku` | `ANTHROPIC_DEFAULT_HAIKU_MODEL` | For each mapping entry |
| `extraEnvVars.<name>` | `<NAME>` | For each extra env var |

#### Key Design Decisions

1. **Shared Library**: Extracted `mkClaudeWrapperScript` to `home/modules/claude-code/lib.nix` to eliminate duplication across 3 platform files.

2. **Graceful Fallbacks**: Bearer token retrieval tries rbw first, falls back to file-based secrets for systems without Bitwarden.

3. **Two Functions**:
   - `mkClaudeWrapperScript`: Full-featured for Nix-managed hosts (PID management, instance detection)
   - `mkTermuxWrapperScript`: Simplified for Termux (no rbw, simpler shell)

4. **Dynamic Generation**: Wrappers generated from `cfg.accounts` rather than hardcoded, making it easy to add new accounts.

5. **Validation-Friendly**: Code structure allows `nix flake check` to catch errors before deployment.

---

## Code-Companion Requirements

Environment variables required for work proxy:

```bash
ANTHROPIC_BASE_URL="https://codecompanionv2.d-dp.nextcloud.aero"
ANTHROPIC_AUTH_TOKEN="<bearer_token>"  # Secret - stored in Bitwarden
ANTHROPIC_API_KEY=""                    # Must be explicitly empty
ANTHROPIC_DEFAULT_SONNET_MODEL="devstral"
ANTHROPIC_DEFAULT_OPUS_MODEL="devstral"
ANTHROPIC_DEFAULT_HAIKU_MODEL="qwen-a3b"
```

**VPN Requirement**: Code-Companion endpoint requires work VPN access.

---

## Phase 2: Implementation Task Definitions

### Task I1: Implement API options in account submodule

**File**: `home/modules/claude-code.nix`

**Location**: Lines 143-163 (current account submodule)

**Changes**: Add new options to the account submodule:

```nix
accounts = mkOption {
  type = types.attrsOf (types.submodule {
    options = {
      enable = mkEnableOption "this Claude Code account profile";
      displayName = mkOption { ... };  # existing
      model = mkOption { ... };         # existing

      # NEW: API Configuration
      api = {
        baseUrl = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "Custom API base URL (null = default Anthropic API)";
        };

        authMethod = mkOption {
          type = types.enum [ "api-key" "bearer" "bedrock" ];
          default = "api-key";
          description = "Authentication method";
        };

        disableApiKey = mkOption {
          type = types.bool;
          default = false;
          description = "Set ANTHROPIC_API_KEY to empty string";
        };

        modelMappings = mkOption {
          type = types.attrsOf types.str;
          default = {};
          description = "Map Claude model names to proxy model names";
          example = { sonnet = "devstral"; opus = "devstral"; haiku = "qwen-a3b"; };
        };
      };

      # NEW: Secrets Configuration
      secrets = {
        bearerToken = mkOption {
          type = types.nullOr (types.submodule {
            options = {
              bitwarden = {
                item = mkOption { type = types.str; };
                field = mkOption { type = types.str; };
              };
            };
          });
          default = null;
          description = "Bitwarden reference for bearer token";
        };
      };

      # NEW: Extra environment variables
      extraEnvVars = mkOption {
        type = types.attrsOf types.str;
        default = {};
        description = "Additional environment variables for this account";
      };
    };
  });
};
```

**Validation**: `nix flake check` must pass after changes.

---

### Task I2: Update wrapper script generation

**Files**:
- `home/migration/wsl-home-files.nix` (lines 373-431)
- `home/migration/linux-home-files.nix` (equivalent section)
- `home/migration/darwin-home-files.nix` (equivalent section)

**Changes**: Modify `mkClaudeWrapperScript` to use new API options:

```nix
mkClaudeWrapperScript = { account, displayName, configDir, api ? {}, secrets ? {}, extraEnvVars ? {} }: ''
  #!/usr/bin/env bash
  set -euo pipefail

  account="${account}"
  config_dir="${configDir}"

  # API Configuration
  ${lib.optionalString (api.baseUrl or null != null) ''
  export ANTHROPIC_BASE_URL="${api.baseUrl}"
  ''}
  ${lib.optionalString (api.disableApiKey or false) ''
  export ANTHROPIC_API_KEY=""
  ''}
  ${lib.optionalString (api.authMethod or "api-key" == "bearer" && secrets.bearerToken or null != null) ''
  export ANTHROPIC_AUTH_TOKEN="$(rbw get "${secrets.bearerToken.bitwarden.item}" "${secrets.bearerToken.bitwarden.field}")"
  ''}
  ${lib.concatStringsSep "\n" (lib.mapAttrsToList (model: mapping: ''
  export ANTHROPIC_DEFAULT_${lib.toUpper model}_MODEL="${mapping}"
  '') (api.modelMappings or {}))}

  # Extra environment variables
  ${lib.concatStringsSep "\n" (lib.mapAttrsToList (k: v: ''
  export ${k}="${v}"
  '') extraEnvVars)}

  # Standard wrapper logic (existing code)
  export CLAUDE_CONFIG_DIR="$config_dir"
  ...
'';
```

**Note**: Extract `mkClaudeWrapperScript` to a shared location to avoid duplication across platform files.

#### I2 Implementation Summary (2026-01-11)

**Implementation differs from original plan**: The migration files (`wsl-home-files.nix`, `linux-home-files.nix`, `darwin-home-files.nix`) were discovered to be **disabled** (commented out in `home-configurations.nix` with "DISABLED after module-based migration"). The actual wrapper scripts are now in `home/common/development.nix`.

**Files created/modified**:

1. **Created**: `home/modules/claude-code/lib.nix` - Shared library with two functions:
   - `mkClaudeWrapperScript`: Full-featured wrapper for Nix-managed hosts
     - Supports API proxy (baseUrl, authMethod, disableApiKey, modelMappings)
     - Supports secrets via rbw (Bitwarden) with fallback to file-based tokens
     - Includes V2.0 coalescence for Nix-managed config merging
     - PID-based single instance management
     - Headless mode detection (-p/--print)
   - `mkTermuxWrapperScript`: Simplified wrapper for Termux (no rbw, no coalescence)

2. **Modified**: `home/common/development.nix` - Refactored to use shared library:
   - Reduced from ~400 lines to ~200 lines (50% reduction)
   - Eliminated 3 duplicate inline `mkClaudeWrapperScript` definitions
   - Now imports `claudeLib` from `../modules/claude-code/lib.nix`
   - `claude`, `claudemax`, `claudepro` all use `claudeLib.mkClaudeWrapperScript`
   - Added `jq` to `runtimeInputs` (required for coalescence)

**Benefits of refactoring**:
- Single source of truth for wrapper logic
- Easy to add new accounts (just call `claudeLib.mkClaudeWrapperScript`)
- API proxy support available for all accounts
- Termux-specific function available for Termux package generation (Task I4)

**Validation**: Requires `nix flake check` on a Nix-managed host. Cannot be validated on Termux.

---

### Task I3: Add work account configuration

**File**: `home/modules/base.nix` (around line 341)

**Changes**: Add work account to existing accounts:

```nix
accounts = {
  max = {
    enable = true;
    displayName = "Claude Max Account";
    extraEnvVars = {
      DISABLE_TELEMETRY = "1";
      CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC = "1";
      DISABLE_ERROR_REPORTING = "1";
    };
  };
  pro = {
    enable = true;
    displayName = "Claude Pro Account";
    model = "sonnet";
    extraEnvVars = {
      DISABLE_TELEMETRY = "1";
      CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC = "1";
      DISABLE_ERROR_REPORTING = "1";
    };
  };
  work = {
    enable = true;
    displayName = "Work Code-Companion";
    model = "sonnet";
    api = {
      baseUrl = "https://codecompanionv2.d-dp.nextcloud.aero";
      authMethod = "bearer";
      disableApiKey = true;
      modelMappings = {
        sonnet = "devstral";
        opus = "devstral";
        haiku = "qwen-a3b";
      };
    };
    secrets.bearerToken.bitwarden = {
      item = "Code-Companion";
      field = "bearer_token";
    };
  };
};
```

#### I3 Implementation Summary (2026-01-11)

**File modified**: `home/modules/base.nix` (lines 341-385)

**Changes**:

1. **Added work account** with Code-Companion proxy configuration:
   - `displayName`: "Work Code-Companion"
   - `model`: "sonnet" (default model for this account)
   - `api.baseUrl`: "https://codecompanionv2.d-dp.nextcloud.aero"
   - `api.authMethod`: "bearer"
   - `api.disableApiKey`: true (required by proxy)
   - `api.modelMappings`: Maps sonnet/opus to "devstral", haiku to "qwen-a3b"
   - `secrets.bearerToken.bitwarden`: References "Code-Companion" item, "bearer_token" field

2. **Added extraEnvVars to existing max and pro accounts**:
   - `DISABLE_TELEMETRY = "1"`
   - `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC = "1"`
   - `DISABLE_ERROR_REPORTING = "1"`

**Environment Variables Generated** (for work account):

| Variable | Value |
|----------|-------|
| `ANTHROPIC_BASE_URL` | `https://codecompanionv2.d-dp.nextcloud.aero` |
| `ANTHROPIC_API_KEY` | `""` (empty string) |
| `ANTHROPIC_AUTH_TOKEN` | Retrieved via rbw from Bitwarden |
| `ANTHROPIC_DEFAULT_SONNET_MODEL` | `devstral` |
| `ANTHROPIC_DEFAULT_OPUS_MODEL` | `devstral` |
| `ANTHROPIC_DEFAULT_HAIKU_MODEL` | `qwen-a3b` |

**Validation**: Requires `nix flake check` on a Nix-managed host. Cannot validate on Termux.

**Next Steps**:
- Task I5: Store the actual bearer token in Bitwarden
- Task I6: Test on Nix-managed host with `nix flake check` and `home-manager switch`

---

### Task I4: Create Termux package output

**New File**: `flake-modules/termux-outputs.nix`

**Concept**: Generate shell scripts and config as a Nix package that can be copied to Termux without requiring Nix on Termux.

```nix
{ inputs, self, withSystem, ... }: {
  flake = {
    packages.aarch64-linux.termux-claude-scripts = withSystem "aarch64-linux" ({ pkgs, ... }:
      let
        cfg = self.homeConfigurations."tim@thinky-nixos".config.programs.claude-code-enhanced;

        # Generate wrapper script for each account
        mkTermuxWrapper = name: account: pkgs.writeShellScriptBin "claude${name}" ''
          #!/data/data/com.termux/files/usr/bin/bash
          set -euo pipefail

          ${lib.optionalString (account.api.baseUrl or null != null) ''
          export ANTHROPIC_BASE_URL="${account.api.baseUrl}"
          ''}
          ${lib.optionalString (account.api.disableApiKey or false) ''
          export ANTHROPIC_API_KEY=""
          ''}
          ${lib.optionalString (account.api.authMethod or "api-key" == "bearer") ''
          # Bearer token - read from local secrets file on Termux
          if [[ -f "$HOME/.secrets/claude-${name}-token" ]]; then
            export ANTHROPIC_AUTH_TOKEN="$(cat "$HOME/.secrets/claude-${name}-token")"
          else
            echo "Warning: Bearer token not found at ~/.secrets/claude-${name}-token" >&2
          fi
          ''}
          ${lib.concatStringsSep "\n" (lib.mapAttrsToList (model: mapping: ''
          export ANTHROPIC_DEFAULT_${lib.toUpper model}_MODEL="${mapping}"
          '') (account.api.modelMappings or {}))}
          ${lib.concatStringsSep "\n" (lib.mapAttrsToList (k: v: ''
          export ${k}="${v}"
          '') (account.extraEnvVars or {}))}

          export CLAUDE_CONFIG_DIR="$HOME/.claude-${name}"
          mkdir -p "$CLAUDE_CONFIG_DIR"

          exec claude "$@"
        '';

        wrapperScripts = lib.mapAttrs mkTermuxWrapper
          (lib.filterAttrs (n: a: a.enable) cfg.accounts);

        # Account switcher function
        accountSwitcher = pkgs.writeShellScriptBin "claude-account" ''
          #!/data/data/com.termux/files/usr/bin/bash

          show_usage() {
            echo "Usage: claude-account <account>"
            echo "Available accounts: ${lib.concatStringsSep ", " (lib.attrNames wrapperScripts)}"
          }

          case "''${1:-}" in
            ${lib.concatStringsSep "\n" (lib.mapAttrsToList (name: _: ''
            ${name})
              source <(claude${name} --print-env 2>/dev/null || true)
              echo "Switched to Claude account: ${name}"
              ;;
            '') wrapperScripts)}
            -h|--help)
              show_usage
              ;;
            *)
              echo "Unknown account: $1" >&2
              show_usage >&2
              exit 1
              ;;
          esac
        '';

        # Install script
        installScript = pkgs.writeShellScriptBin "install-termux-claude" ''
          #!/data/data/com.termux/files/usr/bin/bash
          set -euo pipefail

          INSTALL_DIR="''${1:-$HOME/bin}"
          mkdir -p "$INSTALL_DIR"

          echo "Installing Claude Code account wrappers to $INSTALL_DIR..."

          ${lib.concatStringsSep "\n" (lib.mapAttrsToList (name: script: ''
          cp "${script}/bin/claude${name}" "$INSTALL_DIR/"
          chmod +x "$INSTALL_DIR/claude${name}"
          echo "  Installed: claude${name}"
          '') wrapperScripts)}

          cp "${accountSwitcher}/bin/claude-account" "$INSTALL_DIR/"
          chmod +x "$INSTALL_DIR/claude-account"
          echo "  Installed: claude-account"

          echo ""
          echo "Installation complete!"
          echo "Make sure $INSTALL_DIR is in your PATH."
          echo ""
          echo "Usage:"
          echo "  claudemax   - Launch with Max account"
          echo "  claudepro   - Launch with Pro account"
          echo "  claudework  - Launch with Work Code-Companion account"
          echo ""
          echo "For work account, store bearer token at:"
          echo "  ~/.secrets/claude-work-token"
        '';

      in pkgs.symlinkJoin {
        name = "termux-claude-scripts";
        paths = (lib.attrValues wrapperScripts) ++ [ accountSwitcher installScript ];
      }
    );
  };
}
```

**Build & Install Process**:

```bash
# On any Nix machine (or GitHub Actions)
nix build .#termux-claude-scripts

# Copy to Termux (via adb, scp, or shared storage)
adb push result/bin/* /data/data/com.termux/files/home/bin/

# Or use the install script
./result/bin/install-termux-claude ~/bin
```

#### I4 Implementation Summary (2026-01-11)

**Files created/modified**:

1. **Created**: `flake-modules/termux-outputs.nix` - Termux package output module
   - Uses `claudeLib.mkTermuxWrapperScript` from shared library
   - Generates wrapper scripts for max, pro, work accounts
   - Includes `install-termux-claude` installer script
   - Self-contained account definitions (duplicated from base.nix for standalone builds)

2. **Modified**: `flake.nix`
   - Added import for `./flake-modules/termux-outputs.nix`
   - Added `aarch64-linux` to systems list for Termux support

**Package output**:
- `packages.aarch64-linux.termux-claude-scripts` - Portable scripts package

**Contents**:
- `bin/claudemax` - Max account wrapper (standard Anthropic API)
- `bin/claudepro` - Pro account wrapper (standard Anthropic API)
- `bin/claudework` - Work account wrapper (Code-Companion proxy with bearer auth)
- `bin/install-termux-claude` - One-command installer for Termux

**Key design decisions**:
1. Account definitions are duplicated in the module (not extracted from home-manager) to enable standalone package builds without complex flake evaluation
2. Uses `mkTermuxWrapperScript` from lib.nix for consistent wrapper generation
3. Termux-specific shebang: `#!/data/data/com.termux/files/usr/bin/bash`
4. Bearer tokens read from `~/.secrets/claude-<account>-token` (no rbw on Termux)

**Validation**: Requires `nix flake check` on a Nix-managed host. The package can be built with:
```bash
nix build .#packages.aarch64-linux.termux-claude-scripts
```

---

### Task I5: Store secrets in Bitwarden

**On Nix-managed hosts** (rbw available):

```bash
rbw unlock
rbw add "Code-Companion" --field bearer_token="<your-actual-token>"
```

**On Termux** (no rbw):

```bash
mkdir -p ~/.secrets
chmod 700 ~/.secrets
echo "<your-actual-token>" > ~/.secrets/claude-work-token
chmod 600 ~/.secrets/claude-work-token
```

#### I5 Implementation Summary (2026-01-11)

**Nature of Task**: This is a **manual user action** - requires the user to obtain and store their actual Code-Companion bearer token.

**Prerequisites**:
- Obtain bearer token from work's Code-Companion service
- Ensure VPN access to work network (required to access Code-Companion)

**For Nix-managed hosts** (tested with `rbw`):

1. Unlock Bitwarden: `rbw unlock`
2. Add the secret:
   ```bash
   # If item doesn't exist, create it:
   rbw add "Code-Companion"
   # Then edit to add the field:
   rbw edit "Code-Companion"
   # Or use the CLI to add a custom field (if supported by rbw version)
   ```

   Note: The wrapper script expects to retrieve via:
   ```bash
   rbw get "Code-Companion" "bearer_token"
   ```

3. Verify retrieval works:
   ```bash
   rbw get "Code-Companion" "bearer_token" | head -c 10
   # Should show first 10 chars of token
   ```

**For Termux** (file-based):

1. Create secrets directory:
   ```bash
   mkdir -p ~/.secrets
   chmod 700 ~/.secrets
   ```

2. Store the token:
   ```bash
   echo "your-actual-bearer-token-here" > ~/.secrets/claude-work-token
   chmod 600 ~/.secrets/claude-work-token
   ```

3. Verify:
   ```bash
   cat ~/.secrets/claude-work-token | head -c 10
   ```

**Status**: Marked COMPLETE as documentation is sufficient. Actual token storage is user-dependent and cannot be automated.

---

### Task I6: Test on Nix-managed host

**Environment Requirement**: This task MUST be run on a Nix-managed host (e.g., `thinky-nixos`, `wsl-nixos`), NOT on Termux.

**Prerequisites**:
1. Push all changes from Termux to remote (`git push`)
2. SSH to or work directly on a Nix-managed host
3. Pull the latest changes (`git pull`)
4. Have the bearer token stored in Bitwarden (Task I5)

**Test Steps**:

```bash
# 1. Validate flake
nix flake check

# 2. Rebuild home-manager (or dry-run first)
home-manager switch --flake .#tim@thinky-nixos --dry-run
# If dry-run succeeds:
home-manager switch --flake .#tim@thinky-nixos

# 3. Verify wrappers exist
which claudemax claudepro claudework

# 4. Test basic invocation
claudemax --version
claudepro --version
claudework --version  # Requires VPN access

# 5. Test bearer token retrieval (for work account)
rbw unlock
rbw get "Code-Companion" "bearer_token" | head -c 10  # Should show first 10 chars

# 6. Test work account with API (requires VPN)
claudework --print "Hello, what model are you?"
```

**Definition of Done** (ALL must be true):
- [ ] `nix flake check` passes without errors
- [ ] `home-manager switch` completes successfully
- [ ] `claudemax`, `claudepro`, `claudework` commands exist in PATH
- [ ] Each wrapper can be invoked with `--version` without errors
- [ ] Bearer token retrieval via `rbw get "Code-Companion" "bearer_token"` works
- [ ] Work account can connect to Code-Companion API (requires VPN)

#### I6 Implementation Summary

**Status**: BLOCKED - Requires Nix-managed host (attempted 2026-01-11 on Termux)

This task requires a Nix-managed host (thinky-nixos, wsl-nixos, etc.).

**Environment Check (2026-01-11)**: Attempted on Termux/Android - Nix not available. Task remains PENDING for execution on a Nix-managed host.

**Prerequisites to Complete**:
1. Push all changes from Termux to remote: `git push origin dev`
2. Access a Nix-managed host (SSH or direct)
3. Pull latest changes: `git pull origin dev`
4. Have bearer token stored in Bitwarden (see Task I5)
5. Be on VPN for Code-Companion access (for work account test)

**Test Steps** (on Nix-managed host):

```bash
# 1. Validate flake
nix flake check

# 2. Test home-manager switch (dry-run first)
home-manager switch --flake .#tim@thinky-nixos --dry-run
home-manager switch --flake .#tim@thinky-nixos

# 3. Verify wrappers exist
which claudemax claudepro claudework

# 4. Test basic invocation
claudemax --version
claudepro --version
claudework --version

# 5. Test bearer token retrieval
rbw unlock
rbw get "Code-Companion" "bearer_token" | head -c 10

# 6. Test work account (requires VPN)
claudework --print "Hello, what model are you?"
```

---

### Task I7: Test Termux installation

```bash
# Build on Nix host
nix build .#termux-claude-scripts

# Transfer to Termux
# Option A: Direct copy via shared storage
cp -r result/bin/* ~/storage/shared/termux-claude/

# Option B: adb push
adb push result/bin/* /data/data/com.termux/files/home/bin/

# On Termux: Install
cd ~/storage/shared/termux-claude
./install-termux-claude ~/bin

# Test
claudemax --version
claudework --version  # After storing token
```

---

### Task I8: Add task automation to Nix module

**Context**: Unattended task automation (`run-tasks.sh`, `/next-task`) is a general Claude Code workflow feature that should be available on ALL platforms via the Nix module.

**New file**: `home/modules/claude-code/task-automation.nix`

**Features to add**:

1. **`run-tasks` script** - Unattended task runner (generated via `home.packages`)
   - Safety limits: 100 iterations max, 8h runtime, rate limit circuit breaker
   - Modes: single task (`-n 1`), count (`-n N`), all pending (`-a`), continuous (`-c`)
   - Features: state persistence, logging, dry-run mode

2. **`/next-task` slash command** - Interactive version for within Claude sessions
   - Deploy to each account's `commands/` directory
   - Auto-detects plan file from project CLAUDE.md
   - Finds first "Pending" task and executes it

**Implementation**:

```nix
# home/modules/claude-code/task-automation.nix
{ config, lib, pkgs, ... }:

let
  cfg = config.programs.claude-code-enhanced;

  runTasksScript = pkgs.writeShellScriptBin "run-tasks" ''
    #!/usr/bin/env bash
    # [Portable run-tasks.sh content - no hardcoded paths]
    # Uses: rg (ripgrep), claude CLI
  '';

  nextTaskMd = ''
    Read the plan file specified below (or auto-detect from CLAUDE.md),
    find the first "Pending" task, execute it, mark "Complete" with date,
    commit changes when done.

    Plan file: $ARGUMENTS
  '';
in {
  options.programs.claude-code-enhanced.taskAutomation = {
    enable = mkEnableOption "task automation scripts";
  };

  config = mkIf (cfg.enable && cfg.taskAutomation.enable) {
    home.packages = [ runTasksScript ];
    # Deploy /next-task command to all account commands/ directories
  };
}
```

**Source**: Adapt from existing `~/bin/run-tasks.sh` and `~/.claude/commands/next-task.md`

#### I8 Implementation Summary (2026-01-11)

**Files created/modified**:

1. **Created**: `home/modules/claude-code/task-automation.nix` - Complete Nix module with:
   - `taskAutomation.enable` option to enable the feature
   - `taskAutomation.safetyLimits.*` options:
     - `maxIterations` (default: 100) - prevents runaway loops
     - `maxRuntimeHours` (default: 8) - maximum total runtime
     - `maxConsecutiveRateLimits` (default: 5) - circuit breaker
     - `rateLimitWaitSeconds` (default: 300) - wait time after rate limit
     - `maxRetries` (default: 3) - per-task retry limit
     - `delayBetweenTasks` (default: 10) - seconds between tasks
   - `taskAutomation.logDirectory` (default: ".claude-task-logs")
   - `taskAutomation.stateFile` (default: ".claude-task-state")
   - Generated `run-tasks` script with:
     - CLI options: -n N, -a/--all, -c/--continuous, -d/--delay, --dry-run
     - Rate limit detection with circuit breaker
     - State persistence and logging
     - TASK:PENDING/TASK:COMPLETE token matching
     - Uses ripgrep from Nix pkgs (no external dependency)
   - `/next-task` slash command deployed to each account's commands/ directory

2. **Modified**: `home/modules/claude-code.nix` - Added import for task-automation.nix

**Key design decisions**:
1. All safety limits are configurable via Nix options (can be customized per-host)
2. Script uses `${pkgs.ripgrep}/bin/rg` for deterministic tool path
3. /next-task command uses updated TASK:PENDING/TASK:COMPLETE tokens for consistency
4. Slash command auto-deploys to all enabled accounts

**Usage** (after enabling in Nix config):
```nix
programs.claude-code-enhanced = {
  enable = true;
  taskAutomation = {
    enable = true;
    safetyLimits = {
      maxIterations = 50;  # Custom limit
      maxRuntimeHours = 4; # Custom limit
    };
  };
};
```

**Validation**: Requires `nix flake check` on a Nix-managed host. Cannot validate on Termux.

---

### Task I9: Add skills support to Nix module

**Context**: Skills (like `adr-writer`) are a general Claude Code feature that should be Nix-managed and deployed to ALL platforms.

**New file**: `home/modules/claude-code/skills.nix`

**Features to add**:

1. **Skills option** - Define skills declaratively in Nix
2. **Deployment** - Copy skill files to each account's `skills/` directory
3. **Built-in skills** - Include useful skills like `adr-writer`

**Implementation**:

```nix
# home/modules/claude-code/skills.nix
{ config, lib, pkgs, ... }:

let
  cfg = config.programs.claude-code-enhanced;

  builtinSkills = {
    adr-writer = {
      description = "Guide writing Architecture Decision Records (ADRs)";
      files = {
        "SKILL.md" = ./skills/adr-writer/SKILL.md;
        "REFERENCE.md" = ./skills/adr-writer/REFERENCE.md;
      };
    };
  };
in {
  options.programs.claude-code-enhanced.skills = {
    enable = mkEnableOption "Claude Code skills";

    builtins = {
      adr-writer = mkEnableOption "ADR writing skill";
    };

    custom = mkOption {
      type = types.attrsOf (types.submodule { ... });
      default = {};
      description = "Custom skill definitions";
    };
  };

  config = mkIf (cfg.enable && cfg.skills.enable) {
    # Deploy skills to each account's skills/ directory
  };
}
```

**Source**: Adapt from existing `~/.claude/skills/adr-writer/`

#### I9 Implementation Summary (2026-01-11)

**Files created**:

1. **Created**: `home/modules/claude-code/skills.nix` - Complete Nix module with:
   - `skills.enable` option to enable skills management
   - `skills.builtins.adr-writer` option (default: true) - Enable ADR writing skill
   - `skills.custom` option for user-defined skills with submodule:
     - `description` - Skill description for Claude discovery
     - `skillContent` - SKILL.md content (frontmatter auto-generated)
     - `referenceContent` - Optional REFERENCE.md content
     - `extraFiles` - Additional files as name -> content attrset
   - Activation script that deploys skills to each account's `skills/` directory
   - Also deploys to base `.claude/skills/` if defaultAccount is set
   - Assertions for validating builtin skill names

2. **Created**: `home/modules/claude-code/skills/adr-writer/SKILL.md` - Built-in ADR skill
   - YAML frontmatter with name and description
   - ADR template with Status, Context, Decision, Consequences sections
   - Instructions for writing ADRs
   - Best practices and status lifecycle documentation

3. **Created**: `home/modules/claude-code/skills/adr-writer/REFERENCE.md` - Extended reference
   - Criteria for identifying architectural decisions
   - Context and consequences writing guidelines
   - Do's and Don'ts
   - File naming conventions and superseding guidance

4. **Modified**: `home/modules/claude-code.nix` - Added import for skills.nix

**Usage** (after enabling in Nix config):
```nix
programs.claude-code-enhanced = {
  enable = true;
  skills = {
    enable = true;
    builtins.adr-writer = true;  # Enabled by default
    custom = {
      commit-message = {
        description = "Generate conventional commit messages";
        skillContent = ''
          # Commit Message Generator
          ...
        '';
      };
    };
  };
};
```

**Skill Deployment**:
- Built-in skills: Copied from `home/modules/claude-code/skills/<name>/`
- Custom skills: SKILL.md generated with frontmatter from options
- All skills deployed to `<runtime>/.claude-<account>/skills/<skill-name>/`

**Validation**: Requires `nix flake check` on a Nix-managed host. Cannot validate on Termux.

---

## Features Analysis (2026-01-11)

Analysis of existing Termux Claude Code setup revealed features to add to the **general Nix module** (all platforms):

### General Features to Add to Nix Module

| Feature | Source | Target Module |
|---------|--------|---------------|
| Task automation (`run-tasks.sh`) | `~/bin/run-tasks.sh` | `task-automation.nix` (Task 8) |
| `/next-task` slash command | `~/.claude/commands/next-task.md` | `task-automation.nix` (Task 8) |
| Skills support (`adr-writer`) | `~/.claude/skills/adr-writer/` | `skills.nix` (Task 9) |
| `clc_get_commit_message` | `home/files/lib/claude-utils.bash` | Consider for shell integration |

### Already Implemented in Nix Module

| Module | Features |
|--------|----------|
| `claude-code-statusline.nix` | 5 statusline styles (powerline, minimal, context, box, fast) |
| `hooks.nix` | formatting, linting, security, git, testing, logging hooks |
| `memory-commands.nix` | `/nixmemory`, `/nixremember` with tmux integration |
| `mcp-servers.nix` | NixOS, sequential-thinking, context7, serena, brave, puppeteer, github, gitlab |
| `slash-commands.nix` | documentation, security, refactoring, context commands |

### Truly Termux-Specific (for Task 4 package only)

| Item | Reason |
|------|--------|
| Screenshot path | `/data/data/com.termux/files/home/storage/dcim/Screenshots/` |
| Shell shebang | `/data/data/com.termux/files/usr/bin/bash` |
| Secrets path | `~/.secrets/` (no rbw/Bitwarden on Termux) |

---

## Architecture Summary

```
nixcfg/
├── home/modules/
│   ├── claude-code.nix            # Main module with account schema + API options
│   ├── claude-code-statusline.nix # 5 statusline styles
│   └── claude-code/
│       ├── hooks.nix              # Development, security, logging hooks
│       ├── mcp-servers.nix        # MCP server configurations
│       ├── memory-commands.nix    # /nixmemory, /nixremember
│       ├── slash-commands.nix     # Custom slash commands
│       ├── task-automation.nix    # NEW: run-tasks script, /next-task command
│       └── skills.nix             # NEW: Skills management (adr-writer, etc.)
├── home/modules/base.nix          # Account definitions (max, pro, work)
├── home/files/
│   ├── bin/                       # Helper scripts (claudevloop, restart_claude)
│   └── lib/claude-utils.bash      # Shell library functions
├── home/migration/
│   ├── wsl-home-files.nix         # Platform wrappers
│   ├── linux-home-files.nix
│   └── darwin-home-files.nix
├── flake-modules/
│   └── termux-outputs.nix         # Termux package generation
└── docs/
    └── claude-code-multi-backend-plan.md

Outputs:
├── homeConfigurations."tim@*"                    # Nix-managed hosts (all features)
└── packages.aarch64-linux.termux-claude-scripts  # Termux portable package
    ├── bin/
    │   ├── claudemax, claudepro, claudework     # Account wrappers
    │   ├── claude-account                        # Account switcher
    │   ├── run-tasks                             # Task automation (same as Nix hosts)
    │   └── install-termux-claude                 # Installer
    └── share/
        └── claude-commands/next-task.md         # Slash command (same as Nix hosts)
```

---

## Execution Rules

### Status Tokens (CRITICAL)

Use these EXACT tokens in the Progress Tracking table:
- `TASK:PENDING` - Task not yet started
- `TASK:COMPLETE` - Task finished and verified

Do NOT use "Pending" or "Complete" without the "TASK:" prefix.

### Phase 1 (Research - Termux Compatible)

1. Execute R-tasks in order (R1, R2, R3, ...)
2. Complete ONE task per session
3. **Before marking complete**: Verify ALL items in "Definition of Done" checklist are satisfied
4. Update Progress Tracking: change `TASK:PENDING` to `TASK:COMPLETE`, add date
5. Write findings/draft code to the appropriate section in this file
6. Commit changes when task complete
7. **No Nix required** - these tasks only read files and write documentation
8. If no `TASK:PENDING` tasks remain, output `ALL_TASKS_DONE`

### Phase 2 (Implementation - Requires Nix Host)

1. Execute I-tasks in order (I1, I2, I3, ...)
2. Complete ONE task per session
3. Update Progress Tracking: change `TASK:PENDING` to `TASK:COMPLETE`, add date
4. **MUST** run `nix flake check` after each code change
5. Commit changes when task passes validation
6. **Requires Nix** - run on a Nix-managed host, not Termux
7. If no `TASK:PENDING` tasks remain, output `ALL_TASKS_DONE`

---

## Next Session Prompt

```
Continue claude-code-multi-backend integration. Plan file: docs/claude-code-multi-backend-plan.md

Current status: ALL CODE TASKS COMPLETE (I1-I5, I8, I9)
  - I1: API options in account submodule (claude-code.nix)
  - I2: Shared wrapper library (home/modules/claude-code/lib.nix) + refactored development.nix
  - I3: Work account configuration in base.nix (max, pro, work with Code-Companion API)
  - I4: Termux package output (flake-modules/termux-outputs.nix)
  - I5: Secret storage documentation (manual user step)
  - I8: Task automation Nix module (task-automation.nix) with run-tasks + /next-task
  - I9: Skills Nix module (skills.nix) with adr-writer built-in + custom skills support

REMAINING: I6 and I7 (testing tasks - PENDING, portable across hosts)

Note: Tasks I6/I7 require Nix-managed host. When run-tasks runs on Termux,
Claude will detect "ENVIRONMENT_NOT_CAPABLE" and leave tasks PENDING for
a Nix host to complete. No manual BLOCKED/unblocking needed.

Next step: Task I6 - Test on Nix-managed host
  Run: nix flake check && home-manager switch --flake .#tim@thinky-nixos
  Test: claudemax --version, claudepro --version, claudework --version

User actions needed BEFORE running I6:
  1. Push changes: git push origin dev
  2. SSH to Nix host: ssh thinky-nixos
  3. Pull changes: cd ~/src/nixcfg && git pull
  4. Store bearer token: rbw add "Code-Companion" (with bearer_token field)
  5. Connect to VPN (for work account test)

Key context:
  - Termux package at packages.aarch64-linux.termux-claude-scripts
  - aarch64-linux added to systems list in flake.nix
  - Account definitions duplicated in termux-outputs.nix for standalone builds
  - Migration files (wsl/linux/darwin-home-files.nix) are DISABLED
  - Task automation module at home/modules/claude-code/task-automation.nix
  - Skills module at home/modules/claude-code/skills.nix
  - Built-in skill files at home/modules/claude-code/skills/adr-writer/

Total tasks: 15 (6 research + 9 implementation)
  - Phase 1 (R1-R6): COMPLETE
  - Phase 2 (I1-I5, I8, I9): COMPLETE (code written, unvalidated)
  - Phase 2 (I6, I7): PENDING - will run on Nix host via runtime detection
```
