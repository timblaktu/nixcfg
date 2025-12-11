# ⚠️ CRITICAL PROJECT-SPECIFIC RULES ⚠️
- **SESSION CONTINUITY**: Update this CLAUDE.md file with task progress and provide end-of-response summary of changes made
- **COMPLETION STANDARD**: Tasks complete ONLY when: (1) `git add` all files, (2) `nix flake check` passes, (3) `nix run home-manager -- switch --flake '.#TARGET' --dry-run` succeeds, (4) end-to-end functionality demonstrated. **Writing code ≠ Working system**
- **NEVER WORK ON MAIN OR MASTER BRANCH**: ALWAYS ask user what branch to work on, and switch to or create it from main or master before starting work
- **MANDATORY GIT COMMITS AT INFLECTION POINTS**: ALWAYS `git add` and `git commit` ALL relevant changes before finalizing your response to user
- **CONSERVATIVE TASK COMPLETION**: NEVER mark tasks as "completed" prematurely. Err on side of leaving tasks "in_progress" or "pending" for review in next session.
- **VALIDATION ≠ FIXING**: Validation tasks should identify and document issues, not necessarily resolve them
- **STOP AND SUMMARIZE**: When discovering architectural issues during validation, STOP and provide a clear summary rather than attempting immediate fixes
- **DEPENDENCY ANALYSIS BOUNDARY**: When hitting build system complexity (Nix dependency injection, flake outputs), document the issue and recommend next steps rather than deep-diving into the build system
- **NIX FLAKE CHECK DEBUGGING**: When `nix flake check` fails, debug in-place using: (1) `nix log /nix/store/...` for detailed failure logs, (2) `nix flake check --verbose --debug --print-build-logs`, (3) `nix build .#checks.SYSTEM.TEST_NAME` for individual test execution, (4) `nix repl` + `:lf .` for interactive flake exploration. NEVER waste time on manual test reproduction - use Nix's built-in debugging tools.
- **RAPID ITERATION = FREQUENT CHECK-INS**: When user says "rapid iteration" or "quick/short responses", this means STOP AFTER EACH SMALL STEP and report back for guidance. Do NOT interpret as "work faster" - it means "communicate more frequently". After each change, explain what you did and ask what to do next.

# 🔧 **DEVELOPMENT ENVIRONMENT**
- Claude code may be running in the terminal or the web. Both use the same .claude/ and CLAUDE.md files in the repo.
- We define a session startup hook to ensure nix is installed in the environment.
  - **Web** environments are ephemeral, so nix will always need to be installed every session startup
  - **Local** environments already have nix, so hook should be a no-op (fast)
- **Environment config**: `flake-modules/dev-shells.nix` defines tooling

# CLAUDE-CODE CONFIGURATION AND STATE MANAGEMENT

**Local sessions:**
- Use `CLAUDE_CONFIG_DIR` → `claude-runtime/.claude-{account}/`
- Never touch `.claude/`
- Hook script at `home/files/bin/ensure-nix.sh` is fine (not web-specific)

**Web sessions:**
- Use `.claude/settings.json` for hooks
- Create runtime state in `.claude/` (all ignored except settings.json)
- Hook runs `bin/ensure-nix.sh` (same script, works in both contexts)

## Filesystem View of Claude Configuration and Runtime State

```
nixcfg/
├── home/files/bin/
│   └── ensure-nix.sh          # Shared hook script
├── claude-runtime/
│   ├── .claude-default/
│   │   ├── settings.json      # ✅ Checked in (Nix-managed)
│   │   ├── .claude.json       # ❌ Ignored (runtime)
│   │   └── .mcp.json          # ❌ Ignored (runtime)
│   ├── .claude-max/
│   │   └── ... (same)
│   └── .claude-pro/
│       └── ... (same)
└── .claude/                   # Web sessions ONLY
    ├── settings.json          # ✅ Checked in (web hooks)
    ├── .claude.json           # ❌ Ignored (runtime)
    ├── .mcp.json              # ❌ Ignored (runtime)
    └── logs/                  # ❌ Ignored (runtime)
```

# Common Nix Development Workflow Commands
```bash
nixpkgs-fmt <file>              # Format Nix files
nix flake check                 # Validate entire flake (MANDATORY before commits)
nix flake update                # Update flake inputs
nix build .#homeConfigurations."tim@thinky-nixos".activationPackage
home-manager switch --flake .#tim@thinky-nixos  # Test config switch
```

# 🔧 **IMPORTANT PATHS for LOCAL sessions**

1. `/home/tim/src/nixpkgs` - Local nixpkgs fork (active development: writers-auto-detection)
2. `/home/tim/src/home-manager` - Local home-manager fork (active development: autoValidate + fcitx5 fixes)  
3. `/home/tim/src/NixOS-WSL` - WSL-specific configurations (active development: plugin shim integration)
4. `/home/tim/src/git-worktree-superproject` - working tree for MY PROJECT implementing fast worktree switching for multi-repo and nix flake projects. We will eventually USE this here in nixcfg to facilitate multiple concurrent nix- development efforts


## 📋 **CURRENT TASKS** (2025-12-10)

### ✅ Recently Completed

#### **Git Branch Synchronization** (2025-12-10)
**Branch**: `dev`
**Status**: READY FOR MANUAL PUSH - Merge aborted, waiting for force push

**Problem**: Local and remote dev branches diverged significantly:
- Local `dev`: 9 commits ahead (18c24a6) - Contains claude-code-enhanced work
- Remote `origin/dev`: 176 commits on different path (413d3ea) - Old unified files module work
- Attempted `git pull --all` resulted in 7 merge conflicts

**Analysis**:
- Local branches (dev + main) contain validated, current work (claude-code-enhanced migration)
- Remote dev contains superseded work from unified files module era
- Common ancestor: e233a2a "Improvements to tmux-session-picker..."
- Remote dev's 176 commits preserved in backup tag: `backup/origin-dev-20251210`

**Resolution Strategy**:
- Aborted merge (7 conflicted files: .gitignore, CLAUDE.md, settings.json files, tmux.nix, claude-code.nix)
- Treating local branches as source of truth
- Force push will overwrite remote with current validated work

**Manual Commands to Complete** (Claude hit auth issues):
```bash
git push --force-with-lease origin dev  # Overwrites origin/dev with local
git checkout main
git push origin main                     # Fast-forward push
git checkout dev
git branch -a -vv                        # Verify sync
```

**After Sync**:
- origin/main will be at 17f6281 (git options fix)
- origin/dev will be at 18c24a6 (claude command symlinks ignore)
- Both remotes will match local state
- Old remote dev work preserved in backup tag

#### **Claude Code Module Rename** (2025-12-10)
**Branch**: `dev`
**Status**: COMPLETE - Ready for deployment

**Problem**: Upstream home-manager added `programs.claude-code` module that conflicts with our custom implementation.

**Solution**: Renamed our module to `programs.claude-code-enhanced`

**Changes Made**:
1. ✅ Renamed namespace: `programs.claude-code` → `programs.claude-code-enhanced`
2. ✅ Updated all sub-modules (hooks, mcp-servers, statusline, sub-agents, slash-commands, memory-commands)
3. ✅ Re-enabled module in base.nix with new namespace
4. ✅ Fixed pre-existing .zshenv conflict (changed to programs.zsh.envExtra)
5. ✅ Fixed missing disableBypassPermissionsMode option reference
6. ✅ All validation passed (nix flake check, home-manager dry-run, nixos-rebuild dry-build)

**Documentation**:
- `docs/claude-code-home-manager-program-analysis.md` - Comprehensive analysis
- `docs/claude-code-module-comparison.md` - Feature comparison
- `home/modules/claude-code/UPSTREAM-CONTRIBUTION-PLAN.md` - Phased contribution strategy

**Commit**: `4f5a67b feat: rename claude-code module to avoid upstream conflict`

#### **GitHub Authentication & Flake Integration** (2025-12-09)
**Branch**: `pa161878`
**Status**: COMPLETE - Successfully integrated and validated

**Accomplishments**:
1. ✅ GitHub PAT configured for Nix operations
2. ✅ Refactored flake inputs to use upstream sources with minimal custom forks
3. ✅ Successfully ran `nix flake update` with all remote URLs
4. ✅ Merged 134 commits from PDF-to-markdown development
5. ✅ All flake validation passed

#### **PDF-to-Markdown Tools** (2025-12-08)
- marker-pdf, docling, and tomd packages added and tested
- GPU detection issues documented for future optimization

#### **Repository Cleanup - Phase 1** (2025-12-11)
**Branch**: `dev`
**Status**: COMPLETE - ~750KB removed, ready for commit

**Removed Items** (40 files/directories):
1. **Backup files** (7): `.archive/backups/*.backup`, `claude-runtime/*/.claude.json.backup`, stray `~` directory, `null` file
2. **Abandoned docling-parse variants** (11): All `pkgs/docling-parse-*-fix/` directories superseded by nixpkgs-docling flake input
3. **Ad-hoc test files** (9): `test*.cpp`, `test*.py`, `test*.md`, `test_input.pdf` (679KB)
4. **Obsolete scripts** (4): `debug_workspace.sh`, `simple_debug.sh`, `fix-*-tests.*`
5. **Editor/cache artifacts** (2): `Session.vim`, `home/files/bin/__pycache__/`
6. **Obsolete session docs** (9): `SESSION-HANDOFF-SUMMARY.md`, `WHAT_CLAUDE_LEARNED.md`, `CLAUDE-CODE-2-MIGRATION.md`, various tomd/docling session prompts

#### **Repository Cleanup - Phase 2** (2025-12-11)
**Branch**: `dev`
**Status**: COMPLETE - 464 lines removed
**Commit**: `482953b`

**Removed Files** (3 modules):
1. **claude-code-simplified.nix** (404 lines): Old version using deprecated `programs.claude-code` namespace, superseded by `claude-code.nix`
2. **mcp-servers.nix** (10 lines): Empty placeholder, functionality moved to `claude-code/mcp-servers.nix` submodule
3. **autovalidate-demo.nix** (46 lines): Demo module for home-manager autoValidate integration, never activated

**Updates**:
- Removed 4 imports of mcp-servers.nix from home-configurations.nix (mbp, thinky-ubuntu, pa161878-nixos, thinky-nixos)
- Validation: `nix flake check` passed
- **Preserved**: uv-mcp-servers.nix (WIP, user requested retention)

#### **Repository Cleanup - Phase 3** (2025-12-11)
**Branch**: `dev`
**Status**: COMPLETE - Auth documentation consolidated
**Files Modified**: 1 enhanced, 7 removed

**Consolidation Summary**:
1. **Enhanced** `docs/GITHUB-AUTH-SETUP.md` (302→496 lines):
   - Added Quick Start Guide section (5-minute setup)
   - Added Architecture section (wrapper-based design documentation)
   - Added History & References section (design evolution timeline)
   - Added Table of Contents for better navigation
   - Now serves as single source of truth for GitHub/GitLab auth

2. **Removed Files** (7 docs, ~2,500 lines):
   - `QUICK-GITHUB-AUTH-SETUP.md` (165 lines) - Content extracted to main doc
   - `docs/auth-refactoring-session-2025-12-05.md` (306 lines) - Historical session prompt
   - `docs/git-auth-integration-research-2025-12-05.md` (449 lines) - Historical research
   - `docs/git-auth-next-steps-2025-12-06.md` (248 lines) - Historical deployment guide
   - `docs/redesigns/github-auth-redesign-2025-11-20.md` (705 lines) - Superseded design
   - `docs/redesigns/github-auth-tasks-2025-11-20.md` (1068 lines) - Superseded tasks
   - `docs/redesigns/gitlab-auth-fix-2025-12-04.md` (195 lines) - Completed fix documentation

**Result**: Single comprehensive 496-line guide replaces 8 fragmented documents totaling ~3,000 lines

#### **Repository Cleanup - Phase 4** (2025-12-11)
**Branch**: `dev`
**Status**: COMPLETE - Session prompts and redundant docs removed
**Commit**: `efe72d7`

**Removed Files** (3 docs, ~323 lines):
1. **TESTING-MIGRATION.md** (96 lines): Redundant with TESTING_JOURNAL.md content
2. **WSL-MOUNT-VALIDATION-PROMPT.md** (180 lines): Obsolete session prompt from Sep 2025
3. **prompts/docling-parse-fix-iterative-prompt.md** (47 lines): Superseded by nixpkgs-docling flake input

**Removed Directories** (2 empty):
1. **docs/prompts/** - Now empty after removing last session prompt
2. **docs/redesigns/** - Already empty after Phase 3 auth doc consolidation

**Impact**:
- Cleaner documentation structure
- Easier to find current/active documentation
- Reduced maintenance burden
- TESTING_JOURNAL.md remains as historical archive

**Cleanup Summary (All Phases)**:
- Phase 1: ~750KB (40 files/directories) - backups, abandoned packages, test files, scripts
- Phase 2: 464 lines (3 modules) - redundant Nix modules
- Phase 3: ~2,900 lines (7 docs + 1 enhanced) - auth documentation consolidation
- Phase 4: ~323 lines (3 docs + 2 empty dirs) - session prompts and redundant docs
- **Total**: ~4,437 lines and ~750KB removed, repository significantly cleaner

### 🚧 **Pending Deployment**

#### **Claude Code Enhanced Module** (Ready to Deploy)
**Branch**: `dev` (ahead of origin/main by 1 commit)
**Next Steps**:
1. Run `home-manager switch --flake '.#tim@thinky-nixos' -b backup`
2. Run `sudo nixos-rebuild switch --flake '.#thinky-nixos'`
3. Verify Claude Code functionality with new namespace
4. Push dev branch or merge to main

### 🚧 **Incomplete/Deferred Tasks**

#### **Fork Development Work** (DEFERRED)
**Status**: On hold pending git-worktree-superproject implementation

**Active Forks Requiring Upstream Coordination**:
1. **nixpkgs** (`writers-auto-detection` branch): autoWriter implementation
2. **home-manager** (custom fork): autoValidate + fcitx5 fixes
3. **NixOS-WSL** (`plugin-shim-integration` branch): VSOCK + bare mount

#### **Claude Code Upstream Contributions** (PLANNED)
**See**: `home/modules/claude-code/UPSTREAM-CONTRIBUTION-PLAN.md`
- Phase 2 (2-4 weeks): Statusline styles, MCP helpers PRs
- Phase 3 (1-2 months): Categorized hooks PR
- Phase 4 (quarter): Multi-account RFC

#### **PDF-to-Markdown GPU Optimization** (IDENTIFIED BUT NOT FIXED)
**Problem**: marker-pdf runs on CPU despite CUDA availability
**Status**: Documented but not implemented

### 📌 **Next Priority Actions**

1. **Complete Git Synchronization**: Run manual push commands (see Git Branch Synchronization section above)
2. **Deploy Claude Code Enhanced**: Run home-manager and nixos-rebuild switch
3. **Verify Deployment**: Test Claude Code with new `programs.claude-code-enhanced` namespace
4. **Consider Branch Strategy**: Decide whether to merge dev → main or continue dev branch work
5. **Begin upstream contribution**: Start with statusline styles PR

## MANDATORY: Next Session Prompt Template
After EVERY response, provide this format:
```
Continue working on [SPECIFIC TASK]. Current status: [WHAT WAS JUST DONE].
Next step: [SPECIFIC ACTION].
Key context: [CRITICAL INFO].
Check: [FILE/LOCATION TO VERIFY].
```
