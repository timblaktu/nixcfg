# GitHub Actions local validation configuration
{
  enable = true; # Enable GitHub Actions validation in flake checks

  jobs = {
    # Fast security checks (~30s each)
    verify-sops = { enable = true; timeout = 30; };
    audit-permissions = { enable = true; timeout = 30; };

    # Comprehensive security checks (~2min each)  
    gitleaks = { enable = true; timeout = 120; };
    semgrep = { enable = true; timeout = 120; };
    trufflehog = { enable = true; timeout = 120; };
  };
}
