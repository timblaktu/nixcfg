# flake-modules/packages.nix
# Custom packages and package-related outputs
{ inputs, self, ... }: {
  perSystem = { config, self', inputs', pkgs, system, ... }: {
    packages =
      let
        customPkgs = import ../pkgs { inherit pkgs; };
      in
      {
        # Include all custom packages
        inherit (customPkgs) nixvim-anywhere markitdown;

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
      };
  };
}
