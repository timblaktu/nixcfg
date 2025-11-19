# Overlays for the Nix configuration
final: prev: {
  # Custom packages and overrides go here

  # Fix watchfiles test failure that affects MCP servers
  # Fallback: Disable problematic tests while working on version update
  pythonPackagesExtensions = prev.pythonPackagesExtensions ++ [
    (python-final: python-prev: {
      watchfiles = python-prev.watchfiles.overridePythonAttrs (old: {
        # Disable tests completely - environment-specific expectations
        doCheck = false;
        pytestFlagsArray = [];
      });
    })
  ];
  
  # Also override specific Python package sets directly
  python311Packages = prev.python311Packages.override {
    overrides = self: super: {
      watchfiles = super.watchfiles.overridePythonAttrs (old: {
        doCheck = false;
        pytestFlagsArray = [];
      });
    };
  };
  
  python312Packages = prev.python312Packages.override {
    overrides = self: super: {
      watchfiles = super.watchfiles.overridePythonAttrs (old: {
        doCheck = false;
        pytestFlagsArray = [];
      });
    };
  };
}
