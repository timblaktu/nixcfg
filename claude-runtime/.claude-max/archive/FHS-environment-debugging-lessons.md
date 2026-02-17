# FHS Environment Debugging Lessons (2025-08-29 - Updated 2025-08-31)

## Common Issues with buildFHSEnv and User .bashrc Interaction

When working with Nix buildFHSEnv and custom user .bashrc files:

1. **Unbound variable errors**: User's .bashrc with `set -u` may reference variables not set in FHS environment
   - Solution: Export required variables early in runScript before bash initialization
   - Common variables: `IN_NIX_SHELL`, `FHS_NAME`, custom environment indicators

2. **Multiple sourcing of initialization scripts**: 
   - `/etc/profile` sourced only by login shells (`bash -l`), not by `bash -c`
   - Interactive shells may source scripts multiple times through different paths
   - Solution: Add sourcing guards using environment variables

3. **Command execution in FHS environments**:
   - `"$@"` treats quoted strings with spaces as single command name
   - Solution: Detect and route through `bash -c` for proper shell parsing

4. **Critical insight**: `nix develop -c` runs in Nix shell environment, NOT in FHS namespace
   - FHS environment only exists when the FHS binary is executed
   - This is why wrappers like nixdev.sh remain necessary

### Debugging Approach
- Test both interactive (`./wrapper`) and command (`./wrapper cmd`) modes separately
- Use verbose flags to trace initialization sequence
- Check user's .bashrc for variable references and `set -u` usage
- Understand the shell initialization chain: runScript → bash -l → /etc/profile → /etc/profile.d/* → ~/.bashrc

### Additional FHS Environment Issues (2025-08-31)

1. **PS1 prompt not persisting in interactive shells**:
   - Setting PS1 in profile.d scripts gets overridden by bash
   - Setting PS1 in buildFHSEnv's `profile` option doesn't stick
   - ANSI-C quoting (`$'...'`) needed for escape sequences but still doesn't persist
   - Pragmatic solution: Set PS1 directly in runScript before exec bash

2. **Directory changes in buildprep.env not persisting**:
   - cd inside redirection blocks `{ }` doesn't affect parent shell
   - Profile.d context vs non-profile.d context creates different behaviors
   - Solution: Add cd AFTER redirection block completes

3. **Dual execution paths in complex scripts**:
   - Scripts that detect context (profile.d vs direct sourcing) are hard to debug
   - Both paths may execute in unexpected ways
   - Consider simplifying to single execution path where possible