# nixcfg Integration Guide for TUR Packages

Guide for integrating TUR packages (claude-wrappers) with the nixcfg repository.

## Architecture

```
TUR Repository (timblaktu/tur)      nixcfg Repository
─────────────────────────────       ─────────────────
Produces .deb packages          →   Consumes packages
GitHub Pages APT repo           →   Documents installation
                                    Provides setup scripts
```

**Key Principle**: Separation of concerns
- TUR fork: Package building and distribution (producer)
- nixcfg: System configuration and documentation (consumer)

## Integration Options

### Option 1: Termux Setup Script (Recommended)

**Location**: `tur-package/nixcfg-integration/setup-termux-repos.sh`

**Usage on Termux**:
```bash
# Copy script to Termux
cd ~/termux-src/nixcfg/tur-package/nixcfg-integration
chmod +x setup-termux-repos.sh

# Run setup
./setup-termux-repos.sh
```

**What it does**:
1. Adds timblaktu-tur APT repository
2. Updates package lists
3. Optionally installs Claude Code
4. Installs claude-wrappers package

**Advantages**:
- ✅ Simple, one-command setup
- ✅ Interactive prompts
- ✅ No Nix required on Termux
- ✅ Standard Termux workflow

### Option 2: Manual Installation (Documentation Only)

Document in nixcfg README:

```markdown
## Installing on Termux

### Add Repository
\`\`\`bash
echo "deb [trusted=yes] https://timblaktu.github.io/tur stable main" | \
  tee $PREFIX/etc/apt/sources.list.d/timblaktu-tur.list
pkg update
\`\`\`

### Install Packages
\`\`\`bash
pkg install claude-wrappers
\`\`\`
```

**Advantages**:
- ✅ Minimal integration
- ✅ User has full control
- ✅ Clear documentation

### Option 3: NixOS-on-Termux Integration (Future)

If you implement NixOS-on-Termux via proot-distro:

```nix
# home/termux/default.nix
{ config, lib, pkgs, ... }:

{
  # Custom Termux packages
  home.packages = [
    # Note: These would need to be built or fetched from TUR
    # Not straightforward since Nix doesn't natively support APT repos
  ];

  # Generate installation script instead
  home.file.".local/bin/setup-tur".source =
    tur-package/nixcfg-integration/setup-termux-repos.sh;
}
```

**Note**: This is complex and probably not worth the effort. Termux isn't a Nix target.

## Recommended Integration Approach

### Step 1: Add Documentation to nixcfg

Create or update `docs/TERMUX-CLAUDE-CODE.md`:

```markdown
# Claude Code on Termux

Multi-account Claude Code setup using custom APT packages.

## Quick Start

\`\`\`bash
# Download setup script
cd /tmp
wget https://raw.githubusercontent.com/timblaktu/nixcfg/main/tur-package/nixcfg-integration/setup-termux-repos.sh
chmod +x setup-termux-repos.sh

# Run setup
./setup-termux-repos.sh
\`\`\`

## Manual Installation

[... detailed steps ...]

## Source

- Packages: https://github.com/timblaktu/tur
- Configuration: https://github.com/timblaktu/nixcfg
```

### Step 2: Update Main README

In `nixcfg/README.md`, add a section:

```markdown
## Termux Integration

Claude Code multi-account wrappers are available as Termux packages.

**Quick setup**:
\`\`\`bash
curl -sSL https://raw.githubusercontent.com/timblaktu/nixcfg/main/tur-package/nixcfg-integration/setup-termux-repos.sh | bash
\`\`\`

**Documentation**: [docs/TERMUX-CLAUDE-CODE.md](docs/TERMUX-CLAUDE-CODE.md)

**Package source**: [tur-package/](tur-package/)
```

### Step 3: Keep Setup Script in nixcfg

Store the setup script in the nixcfg repo, not the TUR fork:

```
nixcfg/
├── tur-package/
│   ├── claude-wrappers/        # Package definition (copy to TUR)
│   ├── .github/workflows/      # CI/CD config (copy to TUR)
│   ├── TUR-FORK-SETUP.md       # Fork setup guide
│   └── nixcfg-integration/     # Scripts for nixcfg users
│       ├── setup-termux-repos.sh
│       └── INTEGRATION-GUIDE.md (this file)
└── docs/
    └── TERMUX-CLAUDE-CODE.md   # User-facing documentation
```

**Reasoning**:
- TUR fork is for package building
- nixcfg is for user-facing documentation and scripts
- Users of nixcfg repo can easily access setup script
- No mixing of concerns

## File Placement Summary

| File | Location | Purpose |
|------|----------|---------|
| Package definition (build.sh, wrappers) | `tur-package/claude-wrappers/` | Copy to TUR fork |
| CI/CD workflow | `tur-package/.github/workflows/` | Copy to TUR fork |
| TUR fork guide | `tur-package/TUR-FORK-SETUP.md` | How to set up TUR fork |
| Integration guide | `tur-package/nixcfg-integration/INTEGRATION-GUIDE.md` | This file |
| Setup script | `tur-package/nixcfg-integration/setup-termux-repos.sh` | Termux setup |
| User documentation | `docs/TERMUX-CLAUDE-CODE.md` | End-user guide |

## Usage Workflow

### For nixcfg Users

```bash
# Clone nixcfg
git clone https://github.com/timblaktu/nixcfg.git
cd nixcfg

# On Termux device, run setup
./tur-package/nixcfg-integration/setup-termux-repos.sh

# Follow prompts
```

### For TUR Maintainer (You)

```bash
# Update package definition in nixcfg
cd ~/termux-src/nixcfg/tur-package/claude-wrappers
vim claudework  # Make changes

# Copy to TUR fork
cp -r ~/termux-src/nixcfg/tur-package/claude-wrappers ~/path/to/tur/tur/

# Commit and push (triggers CI/CD)
cd ~/path/to/tur
git add tur/claude-wrappers/
git commit -m "Update claude-wrappers to 1.0.1"
git push origin master

# GitHub Actions builds and publishes automatically
# Users can upgrade: pkg upgrade claude-wrappers
```

## Alternative: Nix-Generated Setup Script

If you want Nix to generate the setup script (for consistency with your workflow):

```nix
# flake-modules/termux-outputs.nix
{
  packages.x86_64-linux.termux-setup-script = pkgs.writeShellScriptBin "setup-termux-repos" ''
    # Same content as setup-termux-repos.sh
  '';
}
```

Build and deploy:
```bash
nix build .#termux-setup-script
cp result/bin/setup-termux-repos ~/android-shared/
```

**Decision**: Static script is simpler. Only use Nix if you need templating.

## Testing Integration

### Test 1: Fresh Termux Install

```bash
# On new Termux device
pkg install curl
curl -sSL https://raw.githubusercontent.com/timblaktu/nixcfg/main/tur-package/nixcfg-integration/setup-termux-repos.sh | bash
```

Should result in:
- Repository added
- claude-wrappers installed
- Commands available: claudemax, claudepro, claudework

### Test 2: Upgrade Path

```bash
# After updating package in TUR
pkg update
pkg show claude-wrappers  # Check new version
pkg upgrade claude-wrappers
```

### Test 3: Removal

```bash
pkg remove claude-wrappers
# Verify wrappers removed
which claudemax  # Should fail
```

## Maintenance

### Updating Documentation

When you update the package in TUR:

1. Update `tur-package/claude-wrappers/README.md`
2. Update `docs/TERMUX-CLAUDE-CODE.md` if user-facing changes
3. Update `tur-package/TUR-FORK-SETUP.md` if process changes
4. Bump version in TUR and push

### Keeping in Sync

```bash
# Periodically sync package definition
cd ~/termux-src/nixcfg
cp -r tur-package/claude-wrappers /tmp/

cd ~/path/to/tur
cp -r /tmp/claude-wrappers tur/

# Review changes
git diff tur/claude-wrappers/

# Commit if needed
```

Or use git submodule (more complex, probably overkill).

## Future Enhancements

### 1. Automated Sync

GitHub Actions workflow to sync package definition from nixcfg to TUR fork.

### 2. Version Management

Use git tags in nixcfg to track package versions:

```bash
git tag -a claude-wrappers-1.0.0 -m "Release 1.0.0"
git push --tags
```

### 3. Integration Tests

Add tests to verify:
- Package builds correctly
- Wrappers work on Termux
- Repository is accessible
- Installation succeeds

### 4. Multi-Repository Support

If you create more Termux packages:

```
tur-package/
├── claude-wrappers/
├── another-package/
└── yet-another-package/
```

All go into your TUR fork.

## Questions and Decisions

### Q: Should nixcfg reference TUR or vice versa?

**A**: nixcfg references TUR (consumer references producer).

- TUR package mentions nixcfg in TERMUX_PKG_HOMEPAGE
- nixcfg docs reference TUR for installation
- Setup script in nixcfg uses TUR repository

### Q: Where to store package source of truth?

**A**: TUR fork is the source of truth for built packages.

- nixcfg/tur-package/ is for preparation and iteration
- Copy to TUR fork when ready
- TUR fork is what gets built and distributed

### Q: How to handle Nix configuration management?

**A**: Don't. Termux isn't a Nix target.

- Use plain bash scripts
- Document in markdown
- Embrace platform conventions

## Conclusion

**Recommended approach**:

1. ✅ Keep setup script in nixcfg: `tur-package/nixcfg-integration/setup-termux-repos.sh`
2. ✅ Document in nixcfg: `docs/TERMUX-CLAUDE-CODE.md`
3. ✅ Copy package definition to TUR fork when ready
4. ✅ Let GitHub Actions handle building and publishing
5. ✅ Users run setup script from nixcfg or curl it directly

This maintains clean separation and leverages each repo's strengths.
