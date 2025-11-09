# What Claude Learned

## 2025-01-29 14:30 UTC - Unified Files Module Production Migration

### Key Technical Lessons

1. **Conditional imports in Nix cause infinite recursion**
   - Cannot use `config` values in `imports` section
   - Must import unconditionally and use `mkIf` for control
   - Solution: Import both modules, control via options

2. **Function naming conflicts require careful resolution**
   - Multiple modules exposing same function names cause build failures
   - Example: `mkScriptLibrary` conflict between validated-scripts and unified files
   - Solution: Use prefixed alternatives (`mkUnifiedFile`/`mkUnifiedLibrary`)

3. **Test integration needs compatible targets**
   - When disabling modules on some machines, tests break if referencing those machines
   - Must update test configurations to use machines that still have required modules
   - Solution: Switch test targets from `tim@thinky-nixos` to `tim@mbp`

4. **Production migration requires incremental approach**
   - Coexistence systems work better than big-bang replacements
   - Conditional loading allows gradual machine-by-machine migration
   - Backward compatibility essential during transition periods

5. **Build-time validation ≠ Runtime validation**
   - `nix flake check` validates build correctness but not script functionality
   - Dry-runs test configuration parsing but don't execute actual scripts
   - Runtime bugs (like `mytree --help` showing `dirname` help) require functional testing
   - Need both: build validation AND functional testing of deployed scripts

### Migration Architecture Success

- **Hybrid autoWriter + enhanced libraries** successfully deployed to production
- **Conditional loading system** enables safe incremental migration
- **Function isolation** prevents conflicts between old and new systems
- **Test compatibility** maintained across all 38 flake checks

### Validation Commands

```bash
# Test migration
nix run home-manager -- switch --flake '.#tim@thinky-nixos' --dry-run

# Verify all checks
nix flake check

# Validate functionality
mytree --help && stress --help && claude-max --help
```

**Status**: Production deployment successful on thinky-nixos, ready for expansion to additional machines.