# modules/system/types/4-desktop/desktop.nix
# Desktop system configuration layer [NDnd]
#
# Provides:
#   flake.modules.nixos.system-desktop - NixOS with full desktop environment
#   flake.modules.darwin.system-desktop - Darwin with UI preferences
#   flake.modules.homeManager.home-desktop - Home Manager with GUI applications
#
# This layer IMPORTS system-cli and adds:
#   - Desktop environment (GNOME, KDE Plasma, XFCE, etc.)
#   - Display manager (GDM, SDDM, LightDM)
#   - Audio backend (PipeWire, PulseAudio)
#   - Fonts (system fonts, icon fonts, nerd fonts)
#   - Input methods (fcitx5, ibus)
#   - Printing support
#   - Bluetooth
#   - GPU/graphics configuration
#
# Does NOT include:
#   - Specific applications (use home-manager)
#   - User-specific theming (use home-manager)
#
# Usage in host config:
#   imports = [ inputs.self.modules.nixos.system-desktop ];
#   systemDesktop = {
#     environment = "gnome";
#     audioBackend = "pipewire";
#     enableBluetooth = true;
#   };
#   # Also set systemCli and systemDefault options as needed
{ config, lib, inputs, ... }:
{
  flake.modules = {
    # === NixOS Desktop Module ===
    nixos.system-desktop = { config, lib, pkgs, ... }:
      let
        cfg = config.systemDesktop;
        defaultCfg = config.systemDefault;
      in
      {
        imports = [
          # Import CLI layer (which imports default -> minimal)
          inputs.self.modules.nixos.system-cli
        ];

        options.systemDesktop = {
          # Desktop environment selection
          environment = lib.mkOption {
            type = lib.types.enum [ "gnome" "plasma" "xfce" "none" ];
            default = "gnome";
            description = ''
              Desktop environment to install.
              - gnome: GNOME Shell (Wayland-first, modern, full-featured)
              - plasma: KDE Plasma (Qt-based, highly customizable)
              - xfce: XFCE (lightweight, traditional)
              - none: No desktop environment (headless with X/Wayland support)
            '';
          };

          # Display manager selection
          displayManager = lib.mkOption {
            type = lib.types.enum [ "gdm" "sddm" "lightdm" "auto" ];
            default = "auto";
            description = ''
              Display manager to use.
              - auto: Use the DE's preferred display manager
              - gdm: GNOME Display Manager (Wayland support)
              - sddm: Simple Desktop Display Manager (KDE default)
              - lightdm: LightDM (lightweight)
            '';
          };

          # Session type preference
          sessionType = lib.mkOption {
            type = lib.types.enum [ "wayland" "x11" "auto" ];
            default = "auto";
            description = ''
              Preferred session type.
              - auto: Use DE's default (GNOME -> Wayland, Plasma -> X11)
              - wayland: Force Wayland session
              - x11: Force X11 session
            '';
          };

          # Audio configuration
          audioBackend = lib.mkOption {
            type = lib.types.enum [ "pipewire" "pulseaudio" "none" ];
            default = "pipewire";
            description = "Audio backend to use";
          };

          # Bluetooth
          enableBluetooth = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Enable Bluetooth support";
          };

          # Printing
          enablePrinting = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Enable printing support (CUPS)";
          };

          # Scanner support
          enableScanning = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Enable scanner support (SANE)";
          };

          # Input method
          inputMethod = lib.mkOption {
            type = lib.types.enum [ "none" "fcitx5" "ibus" ];
            default = "none";
            description = "Input method framework for CJK and other languages";
          };

          # Font configuration
          enableNerdFonts = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Install Nerd Fonts for terminal/IDE icons";
          };

          nerdFontFamilies = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ "jetbrains-mono" "fira-code" "hack" ];
            description = "Nerd Font families to install (use nerd-fonts.* attribute names, e.g. 'jetbrains-mono')";
          };

          extraFonts = lib.mkOption {
            type = lib.types.listOf lib.types.package;
            default = [ ];
            description = "Additional font packages to install";
          };

          # Hardware acceleration
          enableOpenGL = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Enable OpenGL/hardware acceleration";
          };

          enableVulkan = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Enable Vulkan support";
          };

          # Additional GUI packages at system level
          additionalPackages = lib.mkOption {
            type = lib.types.listOf lib.types.package;
            default = [ ];
            description = "Additional GUI packages to install system-wide";
          };
        };

        config =
          let
            # Determine actual display manager based on DE and preference
            actualDM =
              if cfg.displayManager == "auto" then
                (if cfg.environment == "gnome" then "gdm"
                else if cfg.environment == "plasma" then "sddm"
                else if cfg.environment == "xfce" then "lightdm"
                else "lightdm")
              else cfg.displayManager;

            # Determine if we're using Wayland
            useWayland =
              if cfg.sessionType == "auto" then
                (cfg.environment == "gnome" || cfg.environment == "plasma")
              else cfg.sessionType == "wayland";
          in
          lib.mkMerge [
            # Core X/Wayland configuration
            {
              # Enable X server (required even for Wayland in most cases)
              services.xserver.enable = lib.mkDefault true;

              # Add user to relevant groups
              users.users.${defaultCfg.userName}.extraGroups =
                lib.optionals cfg.enableBluetooth [ "lp" ]
                ++ lib.optionals cfg.enableScanning [ "scanner" "lp" ];
            }

            # Display manager and session configuration
            (lib.mkIf (cfg.environment != "none") {
              services.displayManager.defaultSession = lib.mkDefault (
                if cfg.environment == "gnome" && useWayland then "gnome"
                else if cfg.environment == "gnome" then "gnome-xorg"
                else if cfg.environment == "plasma" && useWayland then "plasma"
                else if cfg.environment == "plasma" then "plasmax11"
                else if cfg.environment == "xfce" then "xfce"
                else null
              );
            })

            # GDM
            (lib.mkIf (actualDM == "gdm") {
              services.displayManager.gdm = {
                enable = true;
                wayland = lib.mkDefault useWayland;
              };
            })

            # SDDM
            (lib.mkIf (actualDM == "sddm") {
              services.displayManager.sddm = {
                enable = true;
                wayland.enable = lib.mkDefault useWayland;
              };
            })

            # LightDM
            (lib.mkIf (actualDM == "lightdm") {
              services.xserver.displayManager.lightdm.enable = true;
            })

            # GNOME configuration
            (lib.mkIf (cfg.environment == "gnome") {
              services.desktopManager.gnome.enable = true;

              # GNOME-specific services
              services.gnome = {
                core-apps.enable = lib.mkDefault true;
                gnome-keyring.enable = lib.mkDefault true;
              };

              # Exclude some default GNOME packages (can be customized)
              environment.gnome.excludePackages = with pkgs; [
                gnome-tour
                gnome-music
              ];
            })

            # KDE Plasma configuration
            (lib.mkIf (cfg.environment == "plasma") {
              services.desktopManager.plasma6.enable = true;

              # Plasma-specific packages
              environment.systemPackages = with pkgs; [
                kdePackages.kate
                kdePackages.konsole
                kdePackages.dolphin
                kdePackages.ark
              ];
            })

            # XFCE configuration
            (lib.mkIf (cfg.environment == "xfce") {
              services.xserver.desktopManager.xfce.enable = true;

              # XFCE-specific packages
              environment.systemPackages = with pkgs; [
                xfce.xfce4-terminal
                xfce.thunar
                xfce.xfce4-pulseaudio-plugin
                xfce.xfce4-whiskermenu-plugin
              ];
            })

            # Headless with X/Wayland support (no DE)
            (lib.mkIf (cfg.environment == "none") {
              # Just X server and minimal window manager support
              services.xserver.windowManager.i3.enable = lib.mkDefault false;
            })

            # PipeWire audio
            (lib.mkIf (cfg.audioBackend == "pipewire") {
              # Disable PulseAudio
              services.pulseaudio.enable = false;

              # Enable PipeWire
              services.pipewire = {
                enable = true;
                alsa.enable = true;
                alsa.support32Bit = true;
                pulse.enable = true;
                jack.enable = lib.mkDefault false;
                wireplumber.enable = true;
              };

              # Allow real-time scheduling for audio
              security.rtkit.enable = true;
            })

            # PulseAudio audio
            (lib.mkIf (cfg.audioBackend == "pulseaudio") {
              services.pulseaudio = {
                enable = true;
                support32Bit = lib.mkDefault true;
              };
            })

            # Bluetooth
            (lib.mkIf cfg.enableBluetooth {
              hardware.bluetooth = {
                enable = true;
                powerOnBoot = lib.mkDefault true;
                settings = {
                  General = {
                    Enable = "Source,Sink,Media,Socket";
                  };
                };
              };

              # Bluetooth audio (when using PipeWire)
              services.pipewire.wireplumber.extraConfig = lib.mkIf (cfg.audioBackend == "pipewire") {
                "bluetooth-policy" = {
                  "bluez5.enable-sbc-xq" = true;
                  "bluez5.enable-msbc" = true;
                  "bluez5.enable-hw-volume" = true;
                };
              };

              # Bluetooth GUI (based on DE)
              environment.systemPackages =
                lib.optionals (cfg.environment == "gnome") [
                  pkgs.gnome-bluetooth
                ] ++ lib.optionals (cfg.environment == "plasma") [
                  pkgs.kdePackages.bluedevil
                ];
            })

            # Printing (CUPS)
            (lib.mkIf cfg.enablePrinting {
              services.printing = {
                enable = true;
                drivers = with pkgs; [
                  gutenprint
                  hplip
                ];
              };

              # Avahi for network printer discovery
              services.avahi = {
                enable = true;
                nssmdns4 = true;
                openFirewall = true;
              };
            })

            # Scanning (SANE)
            (lib.mkIf cfg.enableScanning {
              hardware.sane = {
                enable = true;
                extraBackends = with pkgs; [
                  sane-airscan
                ];
              };
            })

            # Input methods
            (lib.mkIf (cfg.inputMethod == "fcitx5") {
              i18n.inputMethod = {
                enable = true;
                type = "fcitx5";
                fcitx5.addons = with pkgs; [
                  fcitx5-gtk
                  fcitx5-chinese-addons
                  fcitx5-configtool
                ];
              };
            })

            (lib.mkIf (cfg.inputMethod == "ibus") {
              i18n.inputMethod = {
                enable = true;
                type = "ibus";
                ibus.engines = with pkgs.ibus-engines; [
                  libpinyin
                  anthy
                ];
              };
            })

            # Fonts
            {
              fonts = {
                enableDefaultPackages = lib.mkDefault true;

                packages = with pkgs; [
                  # Core fonts
                  noto-fonts
                  noto-fonts-cjk-sans
                  noto-fonts-cjk-serif
                  noto-fonts-color-emoji
                  liberation_ttf
                  dejavu_fonts

                  # Icon fonts
                  font-awesome

                  # Microsoft fonts (if unfree allowed)
                  corefonts
                  vista-fonts
                ] ++ lib.optionals cfg.enableNerdFonts (
                  map (name: pkgs.nerd-fonts.${name}) cfg.nerdFontFamilies
                ) ++ cfg.extraFonts;

                fontconfig = {
                  enable = lib.mkDefault true;
                  defaultFonts = {
                    serif = [ "Noto Serif" "DejaVu Serif" ];
                    sansSerif = [ "Noto Sans" "DejaVu Sans" ];
                    monospace = [ "JetBrainsMono Nerd Font" "DejaVu Sans Mono" ];
                    emoji = [ "Noto Color Emoji" ];
                  };
                };
              };
            }

            # OpenGL/Graphics
            (lib.mkIf cfg.enableOpenGL {
              hardware.graphics = {
                enable = true;
                enable32Bit = lib.mkDefault true;
              };
            })

            # Common GUI packages
            {
              environment.systemPackages = with pkgs; [
                # File manager (fallback if not using DE)
                xdg-utils
                xdg-user-dirs

                # Screenshot tools
                grim
                slurp

                # Clipboard
                wl-clipboard
                xclip
              ] ++ cfg.additionalPackages;

              # XDG portal for Wayland/flatpak integration
              xdg.portal = {
                enable = lib.mkDefault true;
                wlr.enable = lib.mkDefault useWayland;
                extraPortals =
                  lib.optionals (cfg.environment == "gnome") [
                    pkgs.xdg-desktop-portal-gnome
                  ] ++ lib.optionals (cfg.environment == "plasma") [
                    pkgs.xdg-desktop-portal-kde
                  ];
              };

              # dconf for GNOME settings
              programs.dconf.enable = lib.mkDefault (cfg.environment == "gnome");
            }
          ];
      };

    # === Darwin Desktop Module ===
    darwin.system-desktop = { config, lib, pkgs, ... }:
      let
        cfg = config.systemDesktop;
      in
      {
        imports = [
          # Import CLI layer
          inputs.self.modules.darwin.system-cli
        ];

        options.systemDesktop = {
          # Dock configuration
          dockAutoHide = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Auto-hide the Dock";
          };

          dockOrientation = lib.mkOption {
            type = lib.types.enum [ "bottom" "left" "right" ];
            default = "bottom";
            description = "Dock position on screen";
          };

          dockTileSize = lib.mkOption {
            type = lib.types.int;
            default = 48;
            description = "Dock icon size in pixels";
          };

          dockMinEffect = lib.mkOption {
            type = lib.types.enum [ "genie" "scale" "suck" ];
            default = "genie";
            description = "Window minimize animation effect";
          };

          # Finder configuration
          finderShowHiddenFiles = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Show hidden files in Finder";
          };

          finderShowExtensions = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Show file extensions in Finder";
          };

          finderDefaultViewStyle = lib.mkOption {
            type = lib.types.enum [ "Nlsv" "icnv" "clmv" "Flwv" ];
            default = "clmv";
            description = ''
              Default Finder view style.
              - Nlsv: List view
              - icnv: Icon view
              - clmv: Column view
              - Flwv: Cover flow
            '';
          };

          # Keyboard settings
          keyRepeatRate = lib.mkOption {
            type = lib.types.int;
            default = 2;
            description = "Key repeat rate (lower = faster)";
          };

          keyRepeatDelay = lib.mkOption {
            type = lib.types.int;
            default = 15;
            description = "Initial key repeat delay (lower = faster)";
          };

          # Trackpad settings
          trackpadTapToClick = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Enable tap to click on trackpad";
          };

          trackpadNaturalScrolling = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Enable natural scrolling direction";
          };

          # Font configuration
          enableNerdFonts = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Install Nerd Fonts for terminal/IDE icons";
          };

          nerdFontFamilies = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ "jetbrains-mono" "fira-code" "hack" ];
            description = "Nerd Font families to install (use nerd-fonts.* attribute names, e.g. 'jetbrains-mono')";
          };

          extraFonts = lib.mkOption {
            type = lib.types.listOf lib.types.package;
            default = [ ];
            description = "Additional font packages to install";
          };

          # Additional packages
          additionalPackages = lib.mkOption {
            type = lib.types.listOf lib.types.package;
            default = [ ];
            description = "Additional GUI packages to install";
          };
        };

        config = lib.mkMerge [
          # Dock settings
          {
            system.defaults.dock = {
              autohide = lib.mkDefault cfg.dockAutoHide;
              orientation = lib.mkDefault cfg.dockOrientation;
              tilesize = lib.mkDefault cfg.dockTileSize;
              mineffect = lib.mkDefault cfg.dockMinEffect;
              show-recents = lib.mkDefault false;
              mru-spaces = lib.mkDefault false;
            };
          }

          # Finder settings
          {
            system.defaults.finder = {
              AppleShowAllFiles = lib.mkDefault cfg.finderShowHiddenFiles;
              AppleShowAllExtensions = lib.mkDefault cfg.finderShowExtensions;
              FXPreferredViewStyle = lib.mkDefault cfg.finderDefaultViewStyle;
              ShowPathbar = lib.mkDefault true;
              ShowStatusBar = lib.mkDefault true;
              _FXShowPosixPathInTitle = lib.mkDefault true;
            };
          }

          # Keyboard settings
          {
            system.defaults.NSGlobalDomain = {
              KeyRepeat = lib.mkDefault cfg.keyRepeatRate;
              InitialKeyRepeat = lib.mkDefault cfg.keyRepeatDelay;
              ApplePressAndHoldEnabled = lib.mkDefault false;
            };
          }

          # Trackpad settings
          {
            system.defaults.trackpad = {
              Clicking = lib.mkDefault cfg.trackpadTapToClick;
              TrackpadRightClick = lib.mkDefault true;
            };

            system.defaults.NSGlobalDomain = {
              "com.apple.swipescrolldirection" = lib.mkDefault cfg.trackpadNaturalScrolling;
            };
          }

          # Fonts
          {
            fonts.packages = with pkgs; [
              # Core fonts
              noto-fonts
              noto-fonts-cjk-sans
              noto-fonts-cjk-serif
              noto-fonts-color-emoji

              # Icon fonts
              font-awesome
            ] ++ lib.optionals cfg.enableNerdFonts (
              map (name: pkgs.nerd-fonts.${name}) cfg.nerdFontFamilies
            ) ++ cfg.extraFonts;
          }

          # System packages
          {
            environment.systemPackages = with pkgs; [
              # macOS utilities
              mas # Mac App Store CLI
              dockutil # Dock management
            ] ++ cfg.additionalPackages;
          }

          # Homebrew casks (common GUI apps)
          {
            homebrew = {
              enable = lib.mkDefault true;
              onActivation = {
                autoUpdate = lib.mkDefault true;
                cleanup = lib.mkDefault "zap";
              };
              # Common macOS GUI apps - users can add more in their config
              casks = [ ];
            };
          }
        ];
      };

    # === Home Manager Desktop Module ===
    # Minimal for now - GUI-specific options to be added as needed
    homeManager.home-desktop = { config, lib, pkgs, ... }:
      let
        cfg = config.homeDesktop;
      in
      {
        imports = [
          # Import CLI layer
          inputs.self.modules.homeManager.home-cli
        ];

        options.homeDesktop = {
          # GUI packages
          guiPackages = lib.mkOption {
            type = lib.types.listOf lib.types.package;
            default = [ ];
            description = "GUI application packages";
          };
        };

        config = {
          home.packages = cfg.guiPackages;
        };
      };
  };
}
