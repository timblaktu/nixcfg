# Unified Nix Configuration - Working Document

## ⚠️ CRITICAL PROJECT-SPECIFIC RULES ⚠️ 
- **SESSION CONTINUITY**: Update this CLAUDE.md file with task progress and provide end-of-response summary of changes made
- **COMPLETION STANDARD**: Tasks complete ONLY when: (1) `git add` all files, (2) `nix flake check` passes, (3) `nix run home-manager -- switch --flake '.#TARGET' --dry-run` succeeds, (4) end-to-end functionality demonstrated. **Writing code ≠ Working system**
- **NEVER WORK ON MAIN OR MASTER BRANCH**: ALWAYS ask user what branch to work on, and switch to or create it from main or master before starting work
- **MANDATORY GIT COMMITS AT INFLECTION POINTS**: ALWAYS `git add` and `git commit` ALL relevant changes before finalizing your response to user
- **CONSERVATIVE TASK COMPLETION**: NEVER mark tasks as "completed" prematurely. Err on side of leaving tasks "in_progress" or "pending" for review in next session. 
- **VALIDATION ≠ FIXING**: Validation tasks should identify and document issues, not necessarily resolve them  
- **STOP AND SUMMARIZE**: When discovering architectural issues during validation, STOP and provide a clear summary rather than attempting immediate fixes
- **DEPENDENCY ANALYSIS BOUNDARY**: When hitting build system complexity (Nix dependency injection, flake outputs), document the issue and recommend next steps rather than deep-diving into the build system
- **NIX FLAKE CHECK DEBUGGING**: When `nix flake check` fails, debug in-place using: (1) `nix log /nix/store/...` for detailed failure logs, (2) `nix flake check --verbose --debug --print-build-logs`, (3) `nix build .#checks.SYSTEM.TEST_NAME` for individual test execution, (4) `nix repl` + `:lf .` for interactive flake exploration. NEVER waste time on manual test reproduction - use Nix's built-in debugging tools.

## CURRENT FOCUS: **CLAUDE CODE 2.0 MIGRATION**

**IMMEDIATE PRIORITY**: Migrate from Claude Code v1.x to v2.0 configuration schema with improved configuration/state separation architecture.

### IMPORTANT PATHS

1. /home/tim/src/nixpkgs
2. /home/tim/src/home-manager  
3. /home/tim/src/NixOS-WSL

## 🚨 IMMEDIATE PRIORITY: CLAUDE CODE 2.0 MIGRATION

### 📋 **CLAUDE CODE 2.0 MIGRATION TASKS**

**🎯 MIGRATION OVERVIEW**: Clean migration to Claude Code v2.0 leveraging improved configuration/state separation

**Core Architecture Changes**:
1. **CLI Flag**: `--config-dir` → `--settings` flag
2. **Schema**: `allowedTools`/`ignorePatterns` → `permissions.{allow,deny,ask}`
3. **File Separation**: MCP servers moved from settings.json to `.mcp.json`
4. **Runtime State**: Add coalescence hook for proper state management

### 🎯 **PHASE 1: Nix Module Updates (v2.0 Schema)** - ⚠️ **CRITICAL BUG FOUND**

**📋 Phase 1 Status**: 
- ✅ **Nix module code**: All v2.0 schema changes implemented correctly  
- ✅ **Template generation**: Both settings.json and .mcp.json templates being generated
- ✅ **Build validation**: `nix flake check` passes, `home-manager switch --dry-run` succeeds
- ❌ **Deployment logic**: Activation script preserves existing files instead of updating to v2.0

**🚨 CRITICAL ISSUE DISCOVERED**:
- **Problem**: Activation script only creates templates if files don't exist (lines 453-461 in claude-code.nix)
- **Impact**: Existing installations keep v1.x settings.json with mcpServers, missing v2.0 permissions structure  
- **Evidence**: Live settings.json still has `mcpServers`, missing `ask`/`defaultMode`/etc., no `.mcp.json` file
- **Root Cause**: Conditional deployment logic `if [[ -f "$accountDir/settings.json" ]]; then echo "preserved"`

**📋 IMMEDIATE FIX NEEDED**:
- [ ] **Always deploy templates**: Force deployment of v2.0 settings.json and .mcp.json files
- [ ] **Migration strategy**: Handle existing v1.x → v2.0 upgrade path
- [ ] **Template validation**: Verify deployed files match v2.0 schema  
- [ ] **Runtime testing**: Test actual Claude Code v2.0 functionality

**🎯 PHASE 1 PRIORITY ORDER**:
1. Start with permission options schema update (foundation)
2. Update settings template with v2.0 structure (core change)
3. Add MCP template generation (new functionality)
4. Remove mcpServers from settings template (cleanup)

**Key Implementation Details**:
```nix
# V2.0 permissions structure
permissions = {
  allow = cfg.permissions.allow;
  deny = cfg.permissions.deny;
  ask = cfg.permissions.ask;
  defaultMode = cfg.permissions.defaultMode;
  disableBypassPermissionsMode = cfg.permissions.disableBypass;
  additionalDirectories = cfg.permissions.additionalDirs;
};
# MCP servers REMOVED from settings.json → separate .mcp.json file
```

### 🎯 **PHASE 2: Wrapper Updates** 

**📋 Phase 2 Tasks**:
- [ ] **Update wrapper flags**: Change `--config-dir` to `--settings` in claudemax/claudepro
- [ ] **Add coalescence function**: Implement startup config merging for runtime state preservation  
- [ ] **Preserve single-instance**: Maintain existing PID management logic
- [ ] **Test wrapper functionality**: Verify new flag usage and coalescence behavior

**🚨 CRITICAL**: Phase 2 depends on Phase 1 completion (requires .mcp.json template)

**Key Implementation Details**:
```bash
# NEW: Coalescence function preserves runtime state while applying Nix config
coalesce_nix_config() {
  # Apply Nix-managed fields, preserve runtime state (oauthAccount, projects, etc.)
  jq --slurpfile settings <(cat "$SETTINGS_FILE") \
     --slurpfile mcp <(cat "$CONFIG_BASE/.claude-$ACCOUNT/.mcp.json") \
     '...' "$config" > "$config.tmp" && mv "$config.tmp" "$config"
}

# CHANGED: v2.0 flag  
exec claude --settings "$SETTINGS_FILE" "$@"
```

### 🎯 **PHASE 3: Activation Script Updates**

**📋 Phase 3 Tasks**:
- [ ] **Update deployment logic**: Deploy both settings.json and .mcp.json (always overwrite)
- [ ] **Preserve runtime state**: Leave .claude.json for Claude Code + coalescence to manage
- [ ] **Test activation**: Verify template deployment and file separation
- [ ] **Validate integration**: Ensure coalescence preserves both Nix config and runtime state

### 🎯 **PHASE 4: Testing & Validation**

**📋 Phase 4 Tasks**:
- [ ] **Build system validation**: `nix flake check` and `home-manager switch --dry-run`
- [ ] **Configuration format validation**: Verify v2.0 schema compliance
- [ ] **Runtime testing**: Test wrapper execution and coalescence behavior
- [ ] **End-to-end validation**: Confirm Claude Code v2.0 functionality

## 📋 **MIGRATION CHECKLIST**

- [ ] Update `claude-code.nix`: v2.0 permissions structure
- [ ] Add `.mcp.json` template generation
- [ ] Update wrappers: `--settings` flag + coalescence
- [ ] Update activation script: deploy both files
- [ ] Test: `home-manager switch`
- [ ] Verify: Check settings.json, .mcp.json format
- [ ] Test: Run `claudemax --print "test"`
- [ ] Commit: Git add new template files

## 🔧 **V2.0 FEATURE OPPORTUNITIES**

**Model Override per Session**:
```bash
claudemax --model opus "refactor this codebase"
claudepro --model sonnet --print "fix typo"
```

**Permission Modes**:
```bash
claudemax --permission-mode acceptEdits "routine update"
```

**Session Management**:
```bash
claudemax -c                    # Continue previous session
claudemax --resume <session-id> # Resume specific session
claudemax -p "git status"       # Non-interactive mode
```

## 📊 **SYSTEM STATUS**

**Current Branch**: `dev`
**Build State**: ✅ All flake checks passing, home-manager deployments successful
**Architecture**: ✅ Clean nixpkgs.writeShellApplication patterns throughout (validated-scripts eliminated)
**Quality**: ✅ Shellcheck compliance, comprehensive testing

**Major Completed Work**:
- ✅ **Validated-scripts elimination**: Complete migration to standard nixpkgs patterns (72+ scripts)
- ✅ **Test infrastructure modernization**: Major overhaul with 76% code reduction
- ✅ **Module-based organization**: All scripts properly categorized in home/common/*.nix files
- ✅ **Quality assurance**: Strict shellcheck compliance + nixpkgs-standard testing

**Next Major Priority**: Cross-platform validation and enhancement (after Claude Code 2.0 migration)

## 🎯 **SESSION HANDOFF NOTES**

**Previous Priority**: Validated-scripts module elimination successfully completed (all 4 phases)
**Current Priority**: Claude Code 2.0 migration (immediate priority per CLAUDE-CODE-2-MIGRATION.md)  
**Next Priority**: Cross-platform validation and enhancement (per NEW_CHAT_PROMPT.md)

**Key Architecture Files**:
- `home/modules/claude-code.nix` - Main Claude Code module orchestrator
- `claude-runtime/.claude-max/` - Account-specific configuration directories
- Wrapper scripts: claudemax, claudepro in development.nix