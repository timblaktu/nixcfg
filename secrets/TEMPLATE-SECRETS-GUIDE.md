# Template Secrets and Placeholder Management Guide

## Purpose
This guide explains how we handle template secrets and placeholders in the nixcfg repository to avoid GitHub push protection blocks while maintaining secure practices.

## Template Secret Format

All placeholder secrets in templates and initialization scripts follow this format:
- **Prefix with "Placeholder_"** for API keys, tokens, and URLs
- **Use "GENERATE_SECURE_PASSWORD"** for password fields that need generation
- **Use obvious dummy values** (XXXXX) to indicate replacement needed

### Examples

```yaml
# CORRECT - Will not trigger GitHub secret scanning
github_token: "Placeholder_ghp_XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX"
slack_webhook_url: "Placeholder_SLACK_WEBHOOK_URL_FORMAT_hooks.slack.com/services/TEAM/CHANNEL/TOKEN"
openai_api_key: "Placeholder_sk-XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX"

# Password fields - indicate generation needed
postgres_password: "GENERATE_SECURE_PASSWORD"
admin_password: "GENERATE_SECURE_PASSWORD"
```

## Why This Matters

1. **GitHub Push Protection**: GitHub scans for patterns matching real secrets (e.g., Slack webhook URLs)
2. **Template Clarity**: Users need to see the correct format for various secret types
3. **Automation Scripts**: Our initialization scripts generate these templates for users

## Handling Push Protection Blocks

If you encounter a push protection block:

1. **Check if it's a placeholder**: Is this an example/template secret?
2. **Add "Placeholder_" prefix**: Update the secret to include the prefix
3. **Update secret_scanning.yml**: Add the file path if it contains templates
4. **Use the bypass URL**: For one-time false positives, use GitHub's bypass URL

## Files Containing Template Secrets

The following files intentionally contain placeholder secrets:
- `secrets/initialize-all-secrets.sh` - Generates template files
- `secrets/common/example.yaml.template` - Example template
- `secrets/common/*.yaml.template` - Any template files
- Documentation files with examples

## Security Best Practices

1. **Never commit real secrets** - Even with "Placeholder_" prefix
2. **Use SOPS for real secrets** - All actual secrets must be encrypted
3. **Review before committing** - Double-check that no real values are present
4. **Rotate if exposed** - If a real secret is accidentally pushed, rotate immediately

## Validating Templates

Before committing template changes:
```bash
# Check that all secrets in templates have proper prefixes
grep -E '(token|key|password|webhook|secret)' secrets/**/*.template | \
  grep -v -E '(Placeholder_|GENERATE_SECURE_PASSWORD|XXXXXXX)'
```

## References
- [GitHub Push Protection Docs](https://docs.github.com/en/code-security/secret-scanning/working-with-secret-scanning-and-push-protection)
- [SOPS-NiX Documentation](./SECRETS-MANAGEMENT.md)