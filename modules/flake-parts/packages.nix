# modules/flake-parts/packages.nix
# Custom packages and package-related outputs
{ inputs, self, lib, ... }: {
  perSystem = { config, self', inputs', pkgs, system, ... }: {
    packages =
      let
        customPkgs = import ../../pkgs { inherit pkgs; };
      in
      {
        # Include all custom packages
        inherit (customPkgs) nixvim-anywhere markitdown marker-pdf tomd confluence-markdown-exporter;

        # Docling package (using nlohmann_json 3.10.5 from nixpkgs)
        inherit (pkgs) docling;

        # nixvim-anywhere convenience targets (Type 2 conversion approach - RECOMMENDED)
        # Temporarily disabled during API migration
        # nixvim-anywhere-tblack-t14 = customPkgs.nixvim-anywhere.override {
        #   nixvim-config = {
        #     initFile = self.homeConfigurations."tim@tblack-t14-nixos".config.programs.nixvim.build.initFile;
        #     extraFiles = self.homeConfigurations."tim@tblack-t14-nixos".config.programs.nixvim.build.extraFiles;
        #     package = self.homeConfigurations."tim@tblack-t14-nixos".config.programs.nixvim.build.package;
        #   };
        #   configName = "tim@tblack-t14-nixos";
        # };
        #
        # nixvim-anywhere-mbp = customPkgs.nixvim-anywhere.override {
        #   nixvim-config = {
        #     initFile = self.homeConfigurations."tim@mbp".config.programs.nixvim.build.initFile;
        #     extraFiles = self.homeConfigurations."tim@mbp".config.programs.nixvim.build.extraFiles;
        #     package = self.homeConfigurations."tim@mbp".config.programs.nixvim.build.package;
        #   };
        #   configName = "tim@mbp";
        # };
      }
      # === Dev-team image convenience aliases ===
      # Short names for image outputs that would otherwise require long paths like:
      #   nix build '.#nixosConfigurations.nixos-dev-team.config.system.build.images.proxmox'
      // lib.optionalAttrs (system == "x86_64-linux") {
        # Proxmox VMA: result contains vzdump-qemu-*.vma.zst
        image-proxmox-dev-team =
          self.nixosConfigurations.nixos-dev-team.config.system.build.images.proxmox;
        # Amazon EC2 AMI (x86_64): result contains *.img (raw format for coldsnap)
        image-ec2-dev-team =
          self.nixosConfigurations.nixos-dev-team-ec2.config.system.build.images.amazon;
        # WSL tarball builder script: run result/bin/nixos-wsl-tarball-builder (requires sudo)
        image-wsl-dev-team =
          self.nixosConfigurations.nixos-wsl-dev-team.config.system.build.tarballBuilder;
      }
      // lib.optionalAttrs (system == "aarch64-linux") {
        # Amazon EC2 AMI (aarch64 Graviton): result contains *.img (raw format for coldsnap)
        image-ec2-dev-team-graviton =
          self.nixosConfigurations.nixos-dev-team-graviton.config.system.build.images.amazon;
      };
  };
}
