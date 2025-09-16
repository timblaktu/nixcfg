# NixOS Configuration for Le Potato (AML-S905X-CC)

## Table of Contents
1. [Hardware Overview](#hardware-overview)
2. [NixOS Configuration Files](#nixos-configuration-files)
3. [Building and Installation](#building-and-installation)
4. [Hardware-Specific Tasks](#hardware-specific-tasks)
5. [Troubleshooting](#troubleshooting)
6. [Development Prompt](#development-prompt)

## Hardware Overview

### Le Potato Specifications
- **SoC**: Amlogic S905X (Quad-core ARM Cortex-A53 @ 1.5GHz)
- **GPU**: Penta-core Mali-450 @ 750MHz
- **RAM**: 1GB or 2GB DDR3
- **Storage**: MicroSD slot, optional eMMC module connector
- **Network**: 100Mbps Ethernet (internal PHY)
- **USB**: 4x USB 2.0 ports
- **Video**: HDMI 2.0 (4K@60Hz support)
- **GPIO**: 40-pin header (Raspberry Pi compatible)
- **Power**: 5V/2A via micro-USB
- **Boot**: Vendor U-Boot 2015.01 (Amlogic customized)

### Key Challenges for NixOS
1. **Bootloader**: Uses vendor U-Boot, requires special configuration
2. **Device Tree**: Needs `meson-gxl-s905x-libretech-cc.dtb` from mainline Linux
3. **No mainline U-Boot SPL**: Must use vendor bootloader chain
4. **Boot Order**: eMMC > SD Card > USB

## NixOS Configuration Files

### Directory Structure
```
hosts/potato/
├── default.nix         # Main system configuration
├── hardware-config.nix # Hardware-specific configuration
└── bootloader.nix     # Boot configuration
```

### `default.nix` - Main Configuration
```nix
# Le Potato (AML-S905X-CC) NixOS Configuration
{ config, lib, pkgs, inputs, ... }:

{
  imports = [
    ./hardware-config.nix
    ./bootloader.nix
  ];

  # System identification
  networking = {
    hostName = "potato";
    useNetworkd = true;
    
    # Configure network interface
    interfaces.eth0 = {
      useDHCP = true;
    };
    
    firewall = {
      enable = true;
      allowedTCPPorts = [ 22 ];  # SSH
    };
  };

  # Platform settings - CRITICAL for ARM64
  nixpkgs = {
    hostPlatform = "aarch64-linux";
    
    config = {
      allowUnfree = true;  # For firmware blobs
      
      # Platform-specific overrides
      packageOverrides = pkgs: {
        # Use mainline kernel with Amlogic patches
        linux_latest = pkgs.linux_latest.override {
          extraConfig = ''
            MESON_GXL y
            MESON_GX_PM_DOMAINS y
            MESON_IRQ_GPIO y
            MMC_MESON_GX y
            PHY_MESON_GXL_USB2 y
            PHY_MESON_GXL_USB3 y
            DRM_MESON y
            VIDEO_MESON_VDEC y
            COMMON_CLK_MESON_GXL y
            SERIAL_MESON y
            SERIAL_MESON_CONSOLE y
          '';
        };
      };
    };
  };

  # Boot configuration
  boot = {
    # Use latest mainline kernel with Amlogic support
    kernelPackages = pkgs.linuxPackages_latest;
    
    # Essential kernel modules for Amlogic S905X
    kernelModules = [
      "meson_gx_mmc"      # SD/eMMC support
      "meson_drm"         # Display driver
      "meson_dw_hdmi"     # HDMI output
      "meson_vdec"        # Video decoder
      "meson_ir"          # IR receiver
      "dwc2"              # USB support
      "g_ether"           # USB gadget ethernet
    ];
    
    # Initial ramdisk modules
    initrd = {
      availableKernelModules = [
        "meson_gx_mmc"
        "sdhci_pltfm"
        "usbhid"
        "usb_storage"
        "sd_mod"
      ];
      
      # Compress initrd for faster boot
      compressor = "zstd";
      compressorArgs = ["-19"];
    };
    
    # Kernel parameters for Amlogic
    kernelParams = [
      "console=ttyAML0,115200n8"  # Amlogic UART
      "console=tty1"
      "rootwait"
      "rw"
      "no_console_suspend"
      "fsck.fix=yes"
      "net.ifnames=0"  # Use eth0 instead of enp*
      "cma=256M"       # Contiguous Memory for GPU/Video
      "video=HDMI-A-1:1920x1080@60"  # Default HDMI mode
    ];
  };

  # Hardware support
  hardware = {
    enableRedistributableFirmware = true;
    
    firmware = with pkgs; [
      linux-firmware
      # Amlogic-specific firmware if available
    ];
    
    # Enable GPU support
    opengl = {
      enable = true;
      driSupport = true;
    };
  };

  # Power management
  powerManagement = {
    enable = true;
    cpuFreqGovernor = "ondemand";
  };

  # Services
  services = {
    # SSH for headless access
    openssh = {
      enable = true;
      settings = {
        PermitRootLogin = "no";
        PasswordAuthentication = false;
        KbdInteractiveAuthentication = false;
      };
      hostKeys = [
        {
          path = "/etc/ssh/ssh_host_ed25519_key";
          type = "ed25519";
        }
      ];
    };

    # Serial console
    getty = {
      extraArgs = ["--keep-baud"];
      greetingLine = "\\l - Le Potato (AML-S905X-CC) - NixOS ${config.system.nixos.version}";
      helpLine = "";
    };
    
    # Enable time synchronization
    chrony.enable = true;
    
    # Avahi for network discovery
    avahi = {
      enable = true;
      nssmdns = true;
      publish = {
        enable = true;
        addresses = true;
        workstation = true;
      };
    };
  };

  # System packages
  environment.systemPackages = with pkgs; [
    # Core utilities
    vim
    wget
    curl
    git
    tmux
    htop
    iotop
    
    # Hardware tools
    usbutils
    pciutils
    i2c-tools
    lm_sensors
    
    # Network tools
    ethtool
    iperf3
    nmap
    
    # Development tools
    gcc
    python3
    
    # File systems
    e2fsprogs
    f2fs-tools  # Good for SD cards
    
    # ARM-specific tools
    dtc  # Device Tree Compiler
    ubootTools
  ];

  # User configuration
  users.users.tim = {
    isNormalUser = true;
    shell = pkgs.zsh;
    extraGroups = [
      "wheel"
      "dialout"
      "gpio"
      "i2c"
      "video"
    ];
    openssh.authorizedKeys.keys = [
      # Add your SSH public key here
      # "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5..."
    ];
    # Set initial password (change on first login)
    initialPassword = "changeme";
  };

  # Enable zsh
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestions.enable = true;
    syntaxHighlighting.enable = true;
  };

  # Time and locale
  time.timeZone = "America/Los_Angeles";
  i18n.defaultLocale = "en_US.UTF-8";

  # Nix settings
  nix = {
    settings = {
      experimental-features = [ "nix-command" "flakes" ];
      auto-optimise-store = true;
      
      # Binary cache for ARM
      substituters = [
        "https://cache.nixos.org"
        "https://arm.cachix.org"
      ];
      trusted-public-keys = [
        "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
        "arm.cachix.org-1:5BZ2kjoL1q6nWhlnrbAl+G7ThY7+HaBRD9PZzqZkbnM="
      ];
    };
    
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 30d";
    };
  };

  # System state version
  system.stateVersion = "24.05";
}
```

### `hardware-config.nix` - Hardware Configuration
```nix
# Hardware configuration for Le Potato (AML-S905X-CC)
{ config, lib, pkgs, modulesPath, ... }:

{
  imports = [
    (modulesPath + "/profiles/base.nix")
  ];

  # File systems
  fileSystems = {
    "/" = {
      device = "/dev/disk/by-label/NIXOS_ROOT";
      fsType = "ext4";
      options = [ 
        "defaults"
        "noatime"
        "nodiratime"
        "errors=remount-ro"
        "commit=60"  # Reduce SD card writes
      ];
    };
    
    "/boot" = {
      device = "/dev/disk/by-label/BOOT";
      fsType = "vfat";
      options = [ 
        "defaults"
        "umask=0077"
      ];
    };
    
    # Optional tmpfs to reduce SD card wear
    "/tmp" = {
      device = "tmpfs";
      fsType = "tmpfs";
      options = [ 
        "defaults"
        "size=256M"
        "mode=1777"
      ];
    };
  };

  # Swap configuration (use zram instead of swap file)
  zramSwap = {
    enable = true;
    algorithm = "zstd";
    memoryPercent = 50;  # Use 50% of RAM for compressed swap
  };

  # Boot settings
  boot = {
    # Clean /tmp on boot
    tmp.cleanOnBoot = true;
    
    # Supported filesystems
    supportedFilesystems = [ 
      "ext4"
      "vfat"
      "f2fs"  # Good for SD cards
      "ntfs"
    ];
    
    # Device tree configuration
    deviceTree = {
      enable = true;
      # Device tree will be provided by vendor U-Boot
      # But we need to ensure kernel has the right one
      name = "amlogic/meson-gxl-s905x-libretech-cc.dtb";
    };
  };

  # Hardware configuration
  hardware = {
    # Device tree overlay support
    deviceTree = {
      enable = true;
      overlays = [
        # Add any custom overlays here
      ];
    };
    
    # Enable all firmware
    enableAllFirmware = true;
  };

  # Sound support (if needed)
  sound.enable = true;
  hardware.pulseaudio.enable = false;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    pulse.enable = true;
  };

  # GPU support
  hardware.opengl = {
    enable = true;
    driSupport = true;
    extraPackages = with pkgs; [
      mesa
      mesa.drivers
    ];
  };
}
```

### `bootloader.nix` - Boot Configuration
```nix
# Bootloader configuration for Le Potato
{ config, lib, pkgs, ... }:

{
  boot = {
    loader = {
      # Disable GRUB - we use vendor U-Boot
      grub.enable = false;
      
      # Use extlinux for U-Boot compatibility
      generic-extlinux-compatible = {
        enable = true;
        configurationLimit = 10;
        
        # Custom extlinux.conf entries if needed
        extraEntries = ''
          # Additional boot entries can go here
        '';
        
        # Copy device tree to /boot
        copyKernels = true;
      };
      
      timeout = 3;
    };
    
    # Ensure kernel and DTB are in /boot
    kernelPatches = [{
      name = "amlogic-fixes";
      patch = null;
      extraConfig = ''
        ARCH_MESON y
        MESON_GXL y
      '';
    }];
  };

  # Create extlinux.conf compatible with vendor U-Boot
  system.build.installBootLoader = pkgs.writeScript "install-bootloader.sh" ''
    #!${pkgs.bash}/bin/bash
    set -e
    
    BOOT_DIR="/boot"
    EXTLINUX_DIR="$BOOT_DIR/extlinux"
    
    # Create extlinux directory
    mkdir -p "$EXTLINUX_DIR"
    
    # Generate extlinux.conf
    cat > "$EXTLINUX_DIR/extlinux.conf" <<EOF
    DEFAULT nixos
    TIMEOUT 30
    PROMPT 1
    
    LABEL nixos
      MENU LABEL NixOS
      LINUX ../Image
      INITRD ../initrd
      FDT ../dtb/amlogic/meson-gxl-s905x-libretech-cc.dtb
      APPEND ${toString config.boot.kernelParams}
    EOF
    
    echo "Bootloader configuration installed"
  '';
}
```

## Building and Installation

### Prerequisites

1. **On Development Machine (x86_64 Linux)**:
```bash
# Install Nix if not already installed
curl -L https://nixos.org/nix/install | sh

# Enable experimental features
mkdir -p ~/.config/nix
echo "experimental-features = nix-command flakes" >> ~/.config/nix/nix.conf
```

2. **Prepare SD Card Image**:

First, download a working Armbian or Debian image for Le Potato to get the vendor bootloader:
```bash
# Download Armbian for Le Potato
wget https://dl.armbian.com/lepotato/archive/Armbian_23.8.1_Lepotato_bookworm_current_6.1.50.img.xz
xz -d Armbian_*.img.xz

# Write to SD card (replace /dev/sdX with your SD card device)
sudo dd if=Armbian_*.img of=/dev/sdX bs=4M status=progress
sync
```

### Building NixOS Image

Create a build script `build-image.nix`:
```nix
{ nixpkgs ? <nixpkgs>, system ? "aarch64-linux" }:

let
  pkgs = import nixpkgs { inherit system; };
  
  nixosConfig = {
    imports = [
      ./hosts/potato/default.nix
    ];
    
    # Image-specific configuration
    sdImage = {
      compressImage = false;
      imageName = "nixos-lepotato-sd-image.img";
    };
  };
  
in
  (import "${nixpkgs}/nixos" {
    configuration = nixosConfig;
    inherit system;
  }).config.system.build.sdImage
```

Build the image:
```bash
# Cross-compile from x86_64 to aarch64
nix-build build-image.nix \
  --argstr system aarch64-linux \
  --option system-features "nixos-test benchmark big-parallel kvm" \
  --option extra-platforms aarch64-linux

# Or build natively on ARM64 machine
nix-build build-image.nix
```

### Installation Steps

1. **Preserve Vendor Bootloader**:
```bash
# Backup first 16MB of SD card (contains bootloader)
sudo dd if=/dev/sdX of=bootloader-backup.img bs=1M count=16

# After writing NixOS image, restore bootloader
sudo dd if=bootloader-backup.img of=/dev/sdX bs=1M count=16 conv=notrunc
```

2. **Manual Installation Method**:
```bash
# Mount partitions
sudo mount /dev/sdX2 /mnt  # Root partition
sudo mount /dev/sdX1 /mnt/boot  # Boot partition

# Generate hardware configuration on Le Potato
nixos-generate-config --root /mnt

# Copy configuration files
sudo cp hosts/potato/*.nix /mnt/etc/nixos/

# Install NixOS
sudo nixos-install --root /mnt
```

### Boot from eMMC Module

If you have an eMMC module:

1. **Flash eMMC via USB (pyamlboot method)**:
```bash
# Install pyamlboot
git clone https://github.com/libre-computer-project/pyamlboot.git -b scripts
sudo apt install python3-usb

# Connect Le Potato via USB A-to-A cable while holding U-Boot button
# Erase eMMC
sudo pyamlboot/run.sh aml-s905x-cc erase-emmc

# Make eMMC appear as USB storage
sudo pyamlboot/run.sh aml-s905x-cc ums-emmc

# Write image to eMMC (appears as /dev/sdX)
sudo dd if=nixos-lepotato.img of=/dev/sdX bs=4M status=progress
```

2. **Using SD card to flash eMMC**:
```bash
# Boot from SD card, then:
sudo dd if=/dev/mmcblk0 of=/dev/mmcblk1 bs=4M status=progress
```

## Hardware-Specific Tasks

### Commands to Run on Le Potato

```bash
# 1. Check hardware detection
lscpu
lsblk
lsusb
dmesg | grep -i amlogic

# 2. Get device tree info
dtc -I fs /sys/firmware/devicetree/base -o current.dts
ls -la /sys/firmware/devicetree/base/

# 3. Check kernel modules
lsmod | grep meson
find /lib/modules/$(uname -r) -name "*meson*" -o -name "*gxl*"

# 4. Test HDMI output
modetest -M meson

# 5. Check thermal zones
cat /sys/class/thermal/thermal_zone*/temp

# 6. GPIO information
ls /sys/class/gpio/
cat /sys/kernel/debug/gpio

# 7. Network interface
ip link show
ethtool eth0

# 8. Get boot environment (if accessible)
fw_printenv 2>/dev/null || echo "fw_printenv not available"

# 9. Memory information
free -h
cat /proc/meminfo

# 10. CPU frequency scaling
cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor
cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_cur_freq
```

### Vendor U-Boot Environment Variables

If you can access U-Boot console (via serial), set these for NixOS boot:
```bash
setenv bootcmd 'run distro_bootcmd'
setenv distro_bootpart 1
setenv distro_bootcmd 'for target in ${boot_targets}; do run bootcmd_${target}; done'
setenv bootcmd_mmc0 'devnum=0; run mmc_boot'
setenv scan_dev_for_boot_part 'part list ${devtype} ${devnum} -bootable devplist; env exists devplist || setenv devplist 1; for part in ${devplist}; do if fstype ${devtype} ${devnum}:${part} bootfstype; then run scan_dev_for_boot; fi; done'
saveenv
```

## Troubleshooting

### Common Issues and Solutions

1. **Boot Failure - "Starting kernel..." hang**:
   - Wrong device tree - ensure `meson-gxl-s905x-libretech-cc.dtb` is used
   - Incorrect kernel parameters - check serial console output
   - Kernel missing Amlogic support - use mainline 5.x or newer

2. **No HDMI Output**:
   - Add `drm.debug=0x1e` to kernel parameters for debug info
   - Try different HDMI modes: `video=HDMI-A-1:1280x720@60`
   - Check if `meson_drm` and `meson_dw_hdmi` modules are loaded

3. **Network Interface Not Found**:
   - Internal PHY needs `PHY_MESON_GXL` kernel config
   - Use `net.ifnames=0` for predictable `eth0` naming

4. **SD Card Performance Issues**:
   - Use A1/A2 rated SD cards
   - Enable F2FS filesystem instead of ext4
   - Reduce commit frequency with mount options
   - Use zram swap instead of swap file

5. **High Temperature**:
   - Normal operating temp is 50-70°C
   - Add heatsink for sustained loads
   - Enable `ondemand` CPU governor

### Serial Console Access

Connect USB-to-TTL adapter:
- TX -> Pin 8 (UART_TX)
- RX -> Pin 10 (UART_RX)  
- GND -> Pin 6 (GND)
- Settings: 115200 8N1

## Development Prompt

Use this prompt with Claude or other AI assistants for further development:

```markdown
I'm working on NixOS support for the Le Potato (AML-S905X-CC) single board computer. This is an ARM64 device with:
- Amlogic S905X SoC (Quad Cortex-A53)
- Vendor U-Boot 2015.01 (cannot be replaced)
- Mainline Linux support via meson-gxl platform
- 100Mbps Ethernet with internal PHY
- Boot order: eMMC > SD > USB

Current status:
- Basic NixOS configuration created
- Using extlinux-compatible boot with vendor U-Boot
- Mainline kernel with Amlogic patches

Issues to resolve:
1. [Describe specific issue you're facing]
2. [Any error messages or logs]

The configuration files are:
[Paste relevant parts of configuration]

The device tree path is: amlogic/meson-gxl-s905x-libretech-cc.dtb

Please help me:
1. Debug this specific issue
2. Optimize the configuration for this hardware
3. Add support for [specific feature]

Note: We cannot modify the bootloader, must work with vendor U-Boot limitations.
```

## Additional Resources

- [Libre Computer Hub](https://hub.libre.computer/) - Official forum
- [Linux-Meson Project](https://linux-meson.com/) - Mainline Linux for Amlogic
- [Armbian Le Potato](https://www.armbian.com/lepotato/) - Reference Linux distribution
- [Device Tree Source](https://github.com/torvalds/linux/blob/master/arch/arm64/boot/dts/amlogic/meson-gxl-s905x-libretech-cc.dts)

## Notes

- The Le Potato uses vendor U-Boot which cannot be easily replaced with mainline
- eMMC modules offer much better performance than SD cards (140MB/s vs 20MB/s)
- The board has good mainline Linux support as of kernel 5.x
- No WiFi onboard - use USB WiFi adapter if needed
- IR receiver is present but requires configuration
- GPIO header is mostly Raspberry Pi compatible

This configuration provides a solid foundation for running NixOS on the Le Potato. The key is working within the constraints of the vendor bootloader while leveraging mainline kernel support for the Amlogic platform.
