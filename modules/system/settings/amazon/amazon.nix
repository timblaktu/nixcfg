# modules/system/settings/amazon/amazon.nix
# Amazon EC2 AMI image configuration module
#
# Provides:
#   flake.modules.nixos.amazon-image-config - Deferred module for image.modules.amazon
#
# Sets sane EC2 AMI defaults: raw format (for coldsnap upload), 6 GiB disk.
#
# This is a deferred module for the image.modules framework (NixOS 25.05+).
# It does NOT import amazon-image.nix — the framework handles that via
# the built-in imageModules.amazon registration in nixpkgs' images.nix.
#
# Runtime EC2 config (ENA drivers, SSM agent, serial console, GRUB) is
# provided by (modulesPath + "/virtualisation/amazon-image.nix") and must
# be imported separately by each EC2 host.
#
# Usage:
#   # In an EC2 host module:
#   image.modules.amazon = {
#     imports = [ inputs.self.modules.nixos.amazon-image-config ];
#     virtualisation.diskSize = 8 * 1024;  # override if needed
#   };
#
# Build AMI:
#   nix build '.#nixosConfigurations.NAME.config.system.build.images.amazon'
# Register AMI (via coldsnap):
#   coldsnap upload result/*.img --region REGION
#   aws ec2 register-image --name NAME --root-device-name /dev/xvda \
#     --block-device-mappings DeviceName=/dev/xvda,Ebs={SnapshotId=SNAP}
_:
{
  flake.modules.nixos.amazon-image-config = { lib, ... }: {
    # amazon-image.nix (maintainers/scripts/ec2/) is already registered as
    # imageModules.amazon in nixpkgs' images.nix framework. We only need to
    # set our configuration defaults here — the builder module import is
    # handled automatically.

    # === Image Format ===
    # Raw format required by coldsnap for EBS Direct API upload.
    # Default upstream is "vpc" (VHD); raw avoids conversion overhead
    # and is the standard for automated AMI pipelines.
    amazonImage.format = lib.mkDefault "raw";

    # === Disk Size ===
    # 6 GiB is sufficient for the dev-team closure (system-cli + dev-team
    # modules without desktop/GUI packages). Upstream default is 4 GiB.
    # Override per-host in image.modules.amazon if larger closure is needed.
    virtualisation.diskSize = lib.mkDefault (6 * 1024);
  };
}
