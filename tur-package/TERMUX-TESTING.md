# Termux Testing Guide

Testing instructions for claude-code, opencode, and wrapper packages on Termux device.

## Pre-Testing Checklist

Before testing on the Termux device, verify:

1. **Packages are published**: https://timblaktu.github.io/tur/dists/stable/main/binary-all/
   - claude-code_0.1.0-1.deb (22 MB)
   - claude-wrappers_1.0.1-1.deb (3.9 KB)
   - opencode_0.1.0-1.deb (44 KB)
   - opencode-wrappers_1.0.0-1.deb (3.9 KB)

2. **APT repository is accessible**: https://timblaktu.github.io/tur

3. **Dependencies available in Termux**:
   - nodejs-lts (for npm packages)
   - bash (for wrappers)

## Installation Steps

### 1. Add APT Repository

```bash
# Add TUR repository
echo "deb [trusted=yes] https://timblaktu.github.io/tur stable main" | \
  tee $PREFIX/etc/apt/sources.list.d/timblaktu-tur.list

# Update package list
pkg update
```

### 2. Install Packages

```bash
# Install Claude Code packages
pkg install claude-code claude-wrappers

# Install OpenCode packages
pkg install opencode opencode-wrappers
```

### 3. Verify Installation

```bash
# Check binaries exist
which claude claudemax claudepro claudework
which opencode opencodemax opencodepro opencodework

# Check versions
claude --version
opencode --version

# Check wrapper functionality
claudemax --help
opencodemax --help
```

## Testing Checklist

### Basic Functionality Tests

- [ ] **claude-code binary**: `claude --version` shows correct version
- [ ] **opencode binary**: `opencode --version` shows correct version
- [ ] **claudemax wrapper**: Launches with correct config directory
- [ ] **claudepro wrapper**: Launches with correct config directory
- [ ] **claudework wrapper**: Template exists (needs configuration)
- [ ] **opencodemax wrapper**: Launches with correct config directory
- [ ] **opencodepro wrapper**: Launches with correct config directory
- [ ] **opencodework wrapper**: Template exists (needs configuration)

### Configuration Tests

- [ ] **Config directories created**:
  - `~/.claude/.claude-max/`
  - `~/.claude/.claude-pro/`
  - `~/.claude/.claude-work/`
  - `~/.opencode/.opencode-max/`
  - `~/.opencode/.opencode-pro/`
  - `~/.opencode/.opencode-work/`

- [ ] **Telemetry disabled**: Check config files have `telemetryDisabled: true`

- [ ] **Environment variables set correctly**:
  ```bash
  # For claudemax/claudepro
  echo $CLAUDE_CODE_CONFIG_DIR
  echo $ANTHROPIC_DISABLE_TELEMETRY

  # For opencodemax/opencodepro
  echo $OPENCODE_CONFIG_DIR
  echo $ANTHROPIC_DISABLE_TELEMETRY
  ```

### Advanced Tests (Optional)

- [ ] **claudework setup**: Run `claude-setup-work` to configure proxy
- [ ] **opencodework setup**: Run `opencode-setup-work` to configure proxy
- [ ] **Multiple accounts**: Launch multiple wrappers simultaneously
- [ ] **Upgrade test**: Modify version, rebuild, test `pkg upgrade`

## Troubleshooting

### Installation Issues

**Problem**: `pkg install` fails with "Unable to locate package"
```bash
# Solution: Verify repository added correctly
cat $PREFIX/etc/apt/sources.list.d/timblaktu-tur.list
pkg update
```

**Problem**: `nodejs-lts` not found
```bash
# Solution: Install from Termux main repo first
pkg install nodejs-lts
```

**Problem**: npm install fails during post-install
```bash
# Solution: Check npm and node are working
node --version
npm --version

# Check npm global directory is writable
npm config get prefix
ls -ld $(npm config get prefix)
```

### Runtime Issues

**Problem**: `claude: command not found`
```bash
# Solution: Check installation
pkg list-installed | grep claude-code
which claude

# Reinstall if needed
pkg reinstall claude-code
```

**Problem**: Wrapper launches wrong account
```bash
# Solution: Check environment variables
claudemax --version  # Should show CLAUDE_CODE_CONFIG_DIR=~/.claude/.claude-max
```

**Problem**: Telemetry not disabled
```bash
# Solution: Check config files
cat ~/.claude/.claude-max/.claude.json | grep telemetry
cat ~/.opencode/.opencode-max/.opencode.json | grep telemetry
```

### Logs and Debugging

**Check system logs**:
```bash
# APT installation logs
cat $PREFIX/var/log/apt/term.log | tail -100

# Package post-install output
# (shown during pkg install)
```

**Check package contents**:
```bash
# List files installed by package
dpkg -L claude-code
dpkg -L claude-wrappers
dpkg -L opencode
dpkg -L opencode-wrappers
```

**Verify package integrity**:
```bash
# Show package info
dpkg -s claude-code
dpkg -s claude-wrappers
dpkg -s opencode
dpkg -s opencode-wrappers
```

## Reporting Issues

If you encounter issues during testing:

1. **Capture the exact error message**: Copy the full terminal output
2. **Check package version**: `dpkg -s <package-name> | grep Version`
3. **Verify dependencies**: `dpkg -s <package-name> | grep Depends`
4. **Check logs**: Include relevant sections from apt logs
5. **Test with verbose output**: Add `-v` or `--verbose` flags if available

## Uninstallation (If Needed)

```bash
# Remove packages
pkg uninstall claude-wrappers claude-code
pkg uninstall opencode-wrappers opencode

# Remove repository (optional)
rm $PREFIX/etc/apt/sources.list.d/timblaktu-tur.list
pkg update
```

## Next Steps After Testing

Once testing is complete:

1. **Document results**: Update CLAUDE.md with test outcomes
2. **Report issues**: Create issues in TUR fork or nixcfg repo
3. **Plan enhancements**: Identify missing features vs nixcfg HM module
4. **Consider v2 features**: PID management, rbw integration, headless mode

## References

- **APT Repository**: https://timblaktu.github.io/tur
- **TUR Fork**: https://github.com/timblaktu/tur
- **Package Source**: ~/termux-src/nixcfg/tur-package/
- **nixcfg Documentation**: ~/termux-src/nixcfg/CLAUDE.md
