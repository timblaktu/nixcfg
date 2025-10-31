# NEW CHAT SESSION: CLAUDE CODE 2.0 MIGRATION

## 🎯 **MISSION**: Claude Code 2.0 Migration Implementation

### **✅ CONTEXT**: System Ready for Migration (2025-10-31)
**ARCHITECTURAL FOUNDATION COMPLETE**: All previous work successfully completed
- ✅ **Validated-scripts elimination**: 72+ scripts migrated to standard nixpkgs patterns
- ✅ **Module-based organization**: Clean separation in home/common/*.nix files  
- ✅ **Test infrastructure modernized**: Major overhaul with 76% code reduction
- ✅ **Build system validated**: All flake checks passing, home-manager deployments successful

**CURRENT SYSTEM STATE**: Stable, well-tested, production-ready configuration

### **🎯 PRIMARY OBJECTIVE**: Claude Code v1.x → v2.0 Migration
**GOAL**: Implement Claude Code 2.0 configuration schema with improved configuration/state separation
**WHY**: Leverage v2.0's enhanced permissions system, better MCP management, and improved runtime state handling

### **📊 CURRENT STATE**:
**Repository Status**:
- **Branch**: `dev`  
- **Build State**: ✅ All flake checks passing, home-manager deployments successful
- **Architecture**: ✅ Clean nixpkgs.writeShellApplication patterns throughout
- **Quality**: ✅ Shellcheck compliance, comprehensive testing

**Migration Documentation**:
- **Primary Source**: `CLAUDE-CODE-2-MIGRATION.md` (comprehensive technical specification)
- **Task Structure**: Organized in CLAUDE.md with 4 phases, 24 specific tasks
- **Implementation Details**: Code snippets and architectural guidance included

### **🔧 MIGRATION APPROACH** (4-Phase Strategy):

**Phase 1 - Nix Module Updates (v2.0 Schema)**:
1. **Update permission options schema**: Implement v2.0 allow/deny/ask structure (foundation)
2. **Update settings template**: Convert to v2.0 permissions structure (core change)  
3. **Add MCP template generation**: Create separate `.mcp.json` generation (new functionality)
4. **Remove mcpServers**: Extract from settings.json to dedicated file (cleanup)

**Phase 2 - Wrapper Updates**:
1. **Update wrapper flags**: Change `--config-dir` to `--settings` in claudemax/claudepro
2. **Add coalescence function**: Implement startup config merging for runtime state preservation
3. **Preserve single-instance logic**: Maintain existing PID management
4. **Test wrapper functionality**: Verify new flag usage and coalescence behavior

**Phase 3 - Activation Script Updates**:
1. **Update deployment logic**: Deploy both settings.json and .mcp.json (always overwrite)
2. **Preserve runtime state**: Leave .claude.json for Claude Code + coalescence to manage
3. **Test activation**: Verify template deployment and file separation
4. **Validate integration**: Ensure coalescence preserves both Nix config and runtime state

**Phase 4 - Testing & Validation**:
1. **Build system validation**: `nix flake check` and `home-manager switch --dry-run`
2. **Configuration format validation**: Verify v2.0 schema compliance
3. **Runtime testing**: Test wrapper execution and coalescence behavior
4. **End-to-end validation**: Confirm Claude Code v2.0 functionality

### **🗂️ KEY FILES FOR MIGRATION**:

**Primary Module**: `home/modules/claude-code.nix`
- Settings template generation (v2.0 schema conversion)
- MCP template generation (new .mcp.json file)
- Permission options schema (allow/deny/ask structure)
- Activation script updates

**Wrapper Scripts**: Located in `home/common/development.nix`
- `claudemax` - MAX account wrapper 
- `claudepro` - PRO account wrapper
- Both need flag updates and coalescence function

**Runtime Directories**: `claude-runtime/.claude-{max,pro}/`
- `settings.json` - Nix-managed v2.0 configuration
- `.mcp.json` - Nix-managed MCP server definitions  
- `.claude.json` - Runtime state + coalesced config (Claude Code managed)

### **🚀 STEP-BY-STEP EXECUTION**:

**Step 1**: Start with Phase 1 (Nix Module Updates)
```bash
# Work in correct location
cd /home/tim/src/nixcfg

# Read current module structure
cat home/modules/claude-code.nix

# Follow CLAUDE-CODE-2-MIGRATION.md Phase 1 specifications
# Update permission options schema first (foundation)
```

**Step 2**: Implement v2.0 schema systematically  
```bash
# Update each component following priority order in CLAUDE.md:
# 1. Permission options schema update
# 2. Settings template v2.0 structure  
# 3. MCP template generation
# 4. Remove mcpServers from settings

# Validate each change with nix flake check
```

**Step 3**: Phase 2 wrapper updates (requires Phase 1 completion)
```bash
# Update wrapper scripts with new flags and coalescence
# Test flag changes and runtime behavior
# Preserve all existing functionality
```

**Step 4**: Complete remaining phases with full validation
```bash
# Phase 3: Activation script updates
# Phase 4: Comprehensive testing and validation

# Final validation commands:
nix flake check
nix run home-manager -- switch --flake '.#tim@thinky-nixos' --dry-run
claudemax --print "test"  # Test v2.0 wrapper functionality
```

### **⚠️ CRITICAL SUCCESS CRITERIA**:
1. **No functionality regression**: All existing Claude Code features must continue working
2. **V2.0 schema compliance**: Settings.json must use v2.0 permissions structure  
3. **Proper file separation**: MCP servers in .mcp.json, not settings.json
4. **Runtime state preservation**: Coalescence must preserve auth tokens, projects, etc.
5. **Build integrity**: All flake checks and deployments must continue passing

### **🔍 VALIDATION COMMANDS**:
```bash
# Verify v2.0 schema compliance
jq '.permissions.allow' claude-runtime/.claude-max/settings.json
jq '.mcpServers' claude-runtime/.claude-max/.mcp.json

# Test wrapper functionality  
claudemax --print "echo test"  # Should use --settings flag internally

# Verify coalescence behavior
# Start session, check that runtime .claude.json has Nix config applied

# Complete system validation
nix flake check && echo "✅ Build check passes"
nix run home-manager -- switch --flake '.#tim@thinky-nixos' --dry-run && echo "✅ Deployment succeeds"
```

### **📚 CONTEXT FROM PREVIOUS WORK**:
**Proven Implementation Patterns**: All scripts use standard nixpkgs.writeShellApplication
**Quality Standards**: Shellcheck compliance enforced at build time  
**Testing Infrastructure**: Comprehensive test suites with nixpkgs-standard patterns
**Module Organization**: Clean separation by functionality proven effective

**Known Working Architecture**:
- **Settings management**: Template-based configuration deployment
- **Wrapper patterns**: Single-instance enforcement with PID management
- **Runtime integration**: Activation scripts for configuration management
- **Quality assurance**: Build-time validation with flake check

### **🎯 SESSION GOALS**:
1. **Complete Phase 1**: Nix module updates with v2.0 schema implementation
2. **Begin Phase 2**: Wrapper updates with new flags and coalescence
3. **Validate progress**: Ensure no functionality regression at each step
4. **Document findings**: Update CLAUDE.md with progress and any discoveries
5. **Prepare for Phase 3/4**: Set up remaining phases for subsequent sessions

### **🔧 REPOSITORY STATE**:
- **Branch**: `dev`
- **Status**: Clean, all major migrations complete
- **Build state**: ✅ Stable (all checks passing, deployments successful)  
- **Current milestone**: Claude Code 2.0 migration (immediate priority)
- **Next milestone**: Cross-platform validation and enhancement

### **💡 SUCCESS INDICATOR**:
When complete, Claude Code should run with v2.0 configuration schema, proper file separation (settings.json + .mcp.json), and seamless coalescence preserving runtime state. All existing functionality preserved while gaining v2.0 benefits.

**TASK**: Begin with Phase 1 Nix module updates, following the priority order specified in CLAUDE.md. Start with permission options schema update as the foundation, then proceed systematically through the remaining Phase 1 tasks.