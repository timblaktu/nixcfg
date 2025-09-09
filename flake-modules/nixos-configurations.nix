# flake-modules/nixos-configurations.nix
# NixOS system configurations
{ inputs, self, withSystem, ... }: {
  flake = {
    nixosConfigurations = {
      mbp = withSystem "x86_64-linux" ({ pkgs, ... }:
        inputs.nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            { nixpkgs.config.allowUnfree = true; }
            ../hosts/mbp
            {
              base = {
                sshPasswordAuth = true;
                requireWheelPassword = false;
                userGroups = [ "wheel" "networkmanager" "audio" "video" ];
                additionalPackages = with pkgs; [
                  kbd
                  terminus_font
                  powerline-fonts
                ];
                consolePackages = with pkgs; [
                  kbd
                  terminus_font
                  powerline-fonts
                ];
                additionalShellAliases = { };
              };
            }
            {
              services.openssh = {
                enable = true;
                ports = [ 22 ];
              };
            }
            inputs.sops-nix.nixosModules.sops
          ];
          specialArgs = {
            inherit inputs;
            inherit (inputs) nixpkgs-stable mcp-servers-nix;
          };
        }
      );
      
      potato = withSystem "aarch64-linux" ({ pkgs, ... }:
        inputs.nixpkgs.lib.nixosSystem {
          system = "aarch64-linux";
          modules = [
            { nixpkgs.config.allowUnfree = true; }
            ../hosts/potato
            {
              base = {
                userGroups = [ "wheel" "networkmanager" "gpio" ];
              };
            }
            {
              services.openssh = {
                enable = true;
                ports = [ 22 ];
              };
            }
            inputs.sops-nix.nixosModules.sops
          ];
          specialArgs = {
            inherit inputs;
            inherit (inputs) nixpkgs-stable mcp-servers-nix;
          };
        }
      );
      
      thinky-nixos = withSystem "x86_64-linux" ({ pkgs, ... }:
        inputs.nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            { nixpkgs.config.allowUnfree = true; }
            ../hosts/thinky-nixos
            {
              base = {
                sshPasswordAuth = true;
                requireWheelPassword = false;
                userGroups = [ "wheel" "dialout" ];
                additionalShellAliases = {
                  explorer = "explorer.exe .";
                  code = "code.exe";
                  code-insiders = "code-insiders.exe";
                };
              };
            }
            {
              services.openssh = {
                enable = true;
                ports = [ 2223 ];  # Must bind to unique port since sharing winHost with another WSL guest
              };
            }
            inputs.sops-nix.nixosModules.sops
            inputs.home-manager.nixosModules.home-manager
            
            # WSL-specific configuration
            inputs.nixos-wsl.nixosModules.default
            {
              wsl.enable = true;
              wsl.defaultUser = "tim";
              wsl.crossInstanceMount.enable = true;
              wsl.interop.register = true;
              wsl.usbip.enable = true;
              wsl.usbip.autoAttach = [ "3-1" "3-2" ];  # .. the last on new sabrent hub is 8-4
              wsl.usbip.snippetIpAddress = "localhost";  # Fix for auto-attach
            }
            
            # ESP32 USB device management
            {
              # USB device management for ESP32 development
              services.udev.packages = [
                (pkgs.writeTextFile {
                  name = "10-esp32-usb";
                  destination = "/etc/udev/rules.d/10-esp32-usb.rules";
                  text = ''
                # CP2102N USB to UART Bridge Controller - Device 1
                # Serial: a84d26d0ef5fef1186befc45d9b539e6
                SUBSYSTEM=="tty", ATTRS{idVendor}=="10c4", ATTRS{idProduct}=="ea60", ATTRS{serial}=="a84d26d0ef5fef1186befc45d9b539e6", SYMLINK+="ttyESP0", MODE="0666", GROUP="dialout"
                
                # CP2102N USB to UART Bridge Controller - Device 2  
                # Serial: 4095a7a28d1af0119da88250ac170b28
                SUBSYSTEM=="tty", ATTRS{idVendor}=="10c4", ATTRS{idProduct}=="ea60", ATTRS{serial}=="4095a7a28d1af0119da88250ac170b28", SYMLINK+="ttyESP1", MODE="0666", GROUP="dialout"
                
                # Generic rule for all CP2102N devices (fallback)
                # This ensures any CP2102N device gets proper permissions even if not explicitly listed
                SUBSYSTEM=="tty", ATTRS{idVendor}=="10c4", ATTRS{idProduct}=="ea60", MODE="0666", GROUP="dialout"
                
                # Also handle the usb-serial subsystem
                SUBSYSTEM=="usb-serial", ATTRS{idVendor}=="10c4", ATTRS{idProduct}=="ea60", MODE="0666", GROUP="dialout"
                  '';
                })
              ];
            }
            
            # Home Manager configuration for user tim
            {
              home-manager.users.tim = {
                imports = [ ../home/modules/base.nix ];
                homeBase = {
                  username = "tim";
                  homeDirectory = "/home/tim";
                  enableDevelopment = true;
                  enableEspIdf = true;
                  environmentVariables = {
                    WSL_DISTRO = "nixos";
                    EDITOR = "nvim";
                  };
                  shellAliases = {
                    explorer = "explorer.exe .";
                    code = "code.exe";
                    code-insiders = "code-insiders.exe";
                    esp32c5 = "esp-idf-shell";
                  };
                };
                terminalVerification.terminalFont = "JetBrainsMono Nerd Font";
                targets.wsl = {
                  enable = true;
                  windowsUsername = "tblack";
                  windowsTools = {
                    enablePowerShell = true;
                    enableCmd = false;
                    enableWslPath = true;
                    wslPathPath = "/bin/wslpath";
                  };
                  bindMountRoot.enable = false;
                };
              };
              home-manager.extraSpecialArgs = {
                inherit inputs;
                inherit (inputs) nixpkgs-stable;
                wslHostname = "tblack-t14-nixos";
              };
            }
          ];
          specialArgs = {
            inherit inputs;
            inherit (inputs) nixpkgs-stable mcp-servers-nix;
          };
        }
      );
      
      tblack-t14-nixos = withSystem "x86_64-linux" ({ pkgs, ... }:
        inputs.nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            { nixpkgs.config.allowUnfree = true; }
            ../hosts/tblack-t14-nixos
            {
              base = {
                requireWheelPassword = false;
                userGroups = [ "wheel" "dialout" ];
                additionalShellAliases = {
                  explorer = "explorer.exe .";
                  code = "code.exe";
                  code-insiders = "code-insiders.exe";
                };
              };
            }
            {
              services.openssh = {
                enable = true;
                ports = [ 22 ];
              };
            }
            inputs.sops-nix.nixosModules.sops
            inputs.home-manager.nixosModules.home-manager
            
            # WSL-specific configuration
            inputs.nixos-wsl.nixosModules.default
            {
              wsl.enable = true;
              wsl.defaultUser = "tim";
              wsl.crossInstanceMount.enable = true;
              wsl.interop.register = true;
              wsl.usbip.enable = true;
              # busids are non-deterministic in Windows. 
              # These are the busids that correspond to the USB hub that I use for managed USB devices.
              # It is an intentional super-set to catch most possible busids, at the risk of accidentally mapping a device to wsl.
              # Below wsl configures udev rules to map specific usbipd devices to /dev nodes, and 
              # the wsl use case is to use the udev-defined symlinks instead of relying on /dev node numbering/population
              wsl.usbip.autoAttach = [  
                 "2-1"  "2-2"  "2-3"  "2-4"
                 "3-1"  "3-2"  "3-3"  "3-4"
                 "5-1"  "5-2"  "5-3"  "5-4"
                 "6-1"  "6-2"  "6-3"  "6-4"
                 "7-1"  "7-2"  "7-3"  "7-4"
                 "8-1"  "8-2"  "8-3"  "8-4"
                 "9-1"  "9-2"  "9-3"  "9-4"
                "10-1" "10-2" "10-3" "10-4"
                "11-1" "11-2" "11-3" "11-4"
                "12-1" "12-2" "12-3" "12-4"
                "13-1" "13-2" "13-3" "13-4"
                "14-1" "14-2" "14-3" "14-4"
                "15-1" "15-2" "15-3" "15-4"
              ];
              wsl.usbip.snippetIpAddress = "localhost";
            }
            
            # USB device management
            {
              services.udev.packages =
                let
                  # Common udev rule template for Silicon Labs CP210x USB to UART Bridges
                  mkEsp32UdevRule = { serial, symlink }:
                    ''
                      # ${symlink} (usbipd serial ${serial})
                      SUBSYSTEM=="tty", ATTRS{idVendor}=="10c4", ATTRS{idProduct}=="ea60", ATTRS{serial}=="${serial}", SYMLINK+="${symlink}", MODE="0666", GROUP="dialout"'';
                  esp32Devices = [
                    { symlink = "ttyFalconTX";         serial = "8269a126ec5fef11bbbbfa45d9b539e6"; }
                    { symlink = "ttyEndeavourRX-FL";   serial = "6849b772f15fef11b58efb45d9b539e6"; }
                    { symlink = "ttyEndeavourRX-C";    serial = "4095a7a28d1af0119da88250ac170b28"; }
                    { symlink = "ttyEndeavourRX-FR";   serial = "1a198954ee5fef119a09f545d9b539e6"; }
                    { symlink = "ttyEndeavourRX-RSL";  serial = "765a0e743c1af011923f8550ac170b28"; }
                    { symlink = "ttyEndeavourRX-RSR";  serial = "de8bdd48f15fef11b36bf545d9b539e6"; }
                    { symlink = "ttyEndeavourRX-SUB";  serial = "a84d26d0ef5fef1186befc45d9b539e6"; }
                  ];
                  # Generate the complete udev rules file content with static parts
                  esp32UdevRules = ''
                    # ESP32 USB UART Bridge Rules
                    # Generated automatically - do not edit manually
                  '' + (builtins.concatStringsSep "\n\n" (map mkEsp32UdevRule esp32Devices)) + ''
                    
                    # End of ESP32 rules for specific devices
                    
                    # Generic rule for all CP2102N devices (fallback)
                    # These ensure any CP2102N tty and usb-serial device gets proper permissions even if not explicitly listed
                    SUBSYSTEM=="tty", ATTRS{idVendor}=="10c4", ATTRS{idProduct}=="ea60", MODE="0666", GROUP="dialout"
                    SUBSYSTEM=="usb-serial", ATTRS{idVendor}=="10c4", ATTRS{idProduct}=="ea60", MODE="0666", GROUP="dialout"
                  '';
                in [
                  (pkgs.writeTextFile {
                    name = "10-esp32-usb";
                    destination = "/etc/udev/rules.d/10-esp32-usb.rules";
                    text = esp32UdevRules;
                  })
              ];
            }
          ];
          specialArgs = {
            inherit inputs;
            inherit (inputs) nixpkgs-stable mcp-servers-nix;
          };
        }
      );
      
      # Minimal NixOS-WSL configuration for distribution as tarball
      nixos-wsl-minimal = withSystem "x86_64-linux" ({ pkgs, ... }:
        inputs.nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            { nixpkgs.config.allowUnfree = false; }  # Keep it free for distribution
            ../hosts/nixos-wsl-minimal
            
            # WSL module from nixos-wsl
            inputs.nixos-wsl.nixosModules.default
          ];
          specialArgs = {
            inherit inputs;
          };
        }
      );
    };
  };
}
