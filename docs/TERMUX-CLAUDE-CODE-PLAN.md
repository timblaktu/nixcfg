# Termux Claude Code Integration: Future Plan

## Current State (January 2026)

The current implementation provides **minimal working Termux support**:

- **Build**: `nix build .#termux-claude-scripts` (builds on any host)
- **Output**: Portable shell scripts (`claudemax`, `claudepro`, `claudework`, `install-termux-claude`)
- **Features**: Environment variable configuration, API proxy, bearer auth, model mappings
- **Limitations**: No settings.json, no MCP servers, no hooks, no coalescence

### What Works Now

```bash
# On NixOS host:
nix build .#termux-claude-scripts
# Copy result/bin/* to Termux via adb/scp/shared storage

# On Termux:
./install-termux-claude ~/bin
mkdir -p ~/.secrets && chmod 700 ~/.secrets
echo 'bearer-token' > ~/.secrets/claude-work-token

# Use:
claudemax    # Personal Anthropic account
claudework   # Work Code-Companion proxy
```

---

## Gap Analysis: NixOS vs Termux

| Feature | NixOS Host | Termux (Current) | Gap |
|---------|------------|------------------|-----|
| Account wrapper scripts | ✅ Full | ✅ Minimal | Environment only |
| Config directory isolation | ✅ | ✅ | None |
| API proxy support | ✅ | ✅ | None |
| Bearer token auth | ✅ rbw + fallback | ✅ file only | No Bitwarden |
| Model mappings | ✅ | ✅ | None |
| settings.json | ✅ Nix-managed | ❌ | Major gap |
| .mcp.json (MCP servers) | ✅ Nix-managed | ❌ | Major gap |
| Hooks (formatting, etc.) | ✅ Nix-managed | ❌ | Major gap |
| Statusline | ✅ Nix-managed | ❌ | Minor gap |
| Config coalescence | ✅ jq merge | ❌ | N/A on Termux |
| Single-instance PID mgmt | ✅ | ❌ | Minor gap |

### Why Coalescence Doesn't Apply to Termux

On NixOS, coalescence solves a specific problem: **merging Nix-managed settings into user-modified runtime config**. This prevents configuration drift while preserving session state.

On Termux without Nix:
- There's no "Nix-managed" config to enforce
- Users directly edit files - they ARE the source of truth
- Coalescence would just merge a file into itself (useless)

---

## Deployment Options Research

### Option 1: Current Approach (Shell Scripts)

**Pros:**
- Simple, works now
- No dependencies beyond bash
- Easy to understand and debug

**Cons:**
- No configuration files
- Manual setup required
- No package management

**Verdict**: Good for quick access, insufficient for full ecosystem parity.

### Option 2: Termux .deb Packages

Termux uses a modified dpkg/apt system. Packages can be created using:

1. **[termux-create-package](https://github.com/termux/termux-create-package)**: Python tool to create .deb files from YAML manifests
2. **[termux-packages build system](https://github.com/termux/termux-packages)**: Full build infrastructure for official packages

**Important Caveat**: Termux .deb packages are NOT compatible with standard Debian/Ubuntu packages due to different install paths (`/data/data/com.termux/files/usr/` vs `/usr/`).

**What a Termux Package Would Include:**
```
claude-code-accounts/
├── DEBIAN/
│   ├── control
│   └── postinst (creates config dirs, prints setup instructions)
├── data/data/com.termux/files/usr/bin/
│   ├── claudemax
│   ├── claudepro
│   └── claudework
└── data/data/com.termux/files/home/.config/
    └── claude-code-templates/  (optional config templates)
```

**Nix Integration**: Could generate .deb in flake output:
```nix
packages.x86_64-linux.termux-claude-deb = pkgs.runCommand "termux-claude.deb" {} ''
  # Use termux-create-package or manual dpkg-deb
'';
```

**Pros:**
- Proper package management
- Versioning, upgrades, removal
- Can include config templates

**Cons:**
- More complex build
- Still doesn't solve config management
- No automatic updates from nixcfg

**Verdict**: Worth exploring if we want cleaner installation, but doesn't solve the core config problem.

### Option 3: Nix-on-Droid

[Nix-on-Droid](https://github.com/nix-community/nix-on-droid) is a **separate Android app** (available on [F-Droid](https://f-droid.org/en/packages/com.termux.nix/)) that provides a Nix-enabled terminal environment.

**How It Works:**
- Fork of Termux terminal emulator
- Runs Nix inside proot (user-space fake root)
- Supports Home Manager integration
- Has its own module system (`nix-on-droid.nix`)

**Configuration Example:**
```nix
# ~/.config/nixpkgs/nix-on-droid.nix
{ pkgs, ... }: {
  environment.packages = with pkgs; [
    nodejs  # For claude CLI
    jq
  ];

  # Could potentially add Claude Code configuration here
  home-manager.config = ./home.nix;

  system.stateVersion = "24.05";
}
```

**Integration Possibilities:**
1. Create a `nixOnDroidModules.claude-code` that mirrors our Home Manager module
2. Share account definitions between flake and nix-on-droid config
3. Full parity with NixOS hosts (settings, MCP, hooks)

**Pros:**
- Full Nix ecosystem
- Home Manager support
- Can reuse most of our module code
- Proper package management

**Cons:**
- Requires using a different app (not standard Termux)
- PRoot overhead (30-50% performance hit)
- ~200MB additional storage
- Some packages don't work in proot

**Verdict**: Best option for full parity. Main downside is switching from Termux.

### Option 4: Nix-in-Termux

[nix-in-termux](https://github.com/t184256/nix-in-termux) installs Nix package manager inside standard Termux.

**Pros:**
- Keep using Termux
- Get Nix package management

**Cons:**
- Described as "alpha-quality"
- Same proot limitations as nix-on-droid
- Less mature than nix-on-droid

**Verdict**: Potential middle ground, but risky due to low maintenance.

### Option 5: Android Virtualization Framework (AVF)

[AVF/pKVM](https://source.android.com/docs/core/virtualization) provides **hardware-accelerated VMs** on supported Android devices.

**Supported Devices:**
- Pixel 6 and newer (must be on Android 14+)
- Some other ARM64 devices with AVF support

**NixOS on AVF:**
[nixos-avf](https://github.com/nix-community/nixos-avf) provides NixOS images for AVF:
- Full NixOS in a VM on your phone
- Near-native performance (KVM, not proot)
- Full systemd, all packages work
- Requires Android 16+ or patched Android 15

**How to Use:**
```bash
# Build NixOS AVF image
nix-build initial.nix -A config.system.build.avfImage

# Copy to phone
adb push result/images.tar.gz /sdcard/linux/

# On phone: Settings > Developer Options > Linux development environment
```

**Integration Path:**
- Add nixcfg as flake input to AVF NixOS config
- Full Home Manager support
- Complete parity with desktop NixOS hosts

**Pros:**
- Full NixOS (not proot)
- Near-native performance
- All packages work
- Complete module reuse

**Cons:**
- Requires newer Pixel phone
- Requires Android 16+ (or patched 15)
- Separate VM (not integrated with Android)
- Higher storage requirements

**Verdict**: Best long-term solution if you upgrade to supported hardware.

---

## Recommended Path Forward

### Short Term (Now)
1. **Use current shell scripts** - they work for basic account switching
2. **Document manual config setup** - users can create settings.json manually
3. **Test on actual Termux** - validate current implementation

### Medium Term (If Termux Usage Grows)
1. **Create Termux .deb package** - cleaner installation
2. **Add config templates** - static files users can customize
3. **Consider nix-on-droid** - if you're comfortable switching apps

### Long Term (Hardware Upgrade)
1. **Get a Pixel 6+ with Android 16+**
2. **Use AVF with nixos-avf**
3. **Full nixcfg integration** - same config as desktop hosts

---

## Implementation Priorities

If continuing Termux development:

### Phase 1: Configuration Templates
Add static config templates to the build output:
```nix
termux-claude-scripts/
├── bin/{claudemax,claudepro,claudework,install-termux-claude}
└── share/claude-code-templates/
    ├── settings.json.template
    ├── .mcp.json.template  (simplified - no MCP servers with binary deps)
    └── CLAUDE.md.template
```

### Phase 2: Termux Package
Create proper .deb package with postinst script that:
- Creates account directories
- Copies templates
- Prints setup instructions

### Phase 3: Shared Account Definitions
Refactor to eliminate duplication:
```nix
# lib/claude-accounts.nix - shared between:
# - home/modules/base.nix
# - flake-modules/termux-outputs.nix
# - (future) nix-on-droid module
```

### Phase 4: Nix-on-Droid Module (Optional)
If switching to nix-on-droid:
```nix
# modules/nix-on-droid/claude-code.nix
# Adapted from home/modules/claude-code.nix
```

---

## Decision Matrix

| If You Want... | Best Option |
|----------------|-------------|
| Quick testing now | Current shell scripts |
| Full parity, keep Termux | Nix-on-Droid |
| Full parity, newer phone | AVF + NixOS |
| Cleaner Termux install | Custom .deb package |

---

## References

- [Termux Package Management](https://wiki.termux.com/wiki/Package_Management)
- [termux-create-package](https://github.com/termux/termux-create-package)
- [Nix-on-Droid](https://github.com/nix-community/nix-on-droid) / [F-Droid](https://f-droid.org/en/packages/com.termux.nix/)
- [nix-in-termux](https://github.com/t184256/nix-in-termux)
- [Android Virtualization Framework](https://source.android.com/docs/core/virtualization)
- [nixos-avf](https://github.com/nix-community/nixos-avf)
- [NixOS VM on phone discussion](https://discourse.nixos.org/t/nixos-vm-on-my-phone-lol-android-virtualization-framework/62890)
