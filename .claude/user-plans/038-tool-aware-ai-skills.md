# Plan 038: Tool-Aware AI Agent Skills

## Context

Claude Code skills are currently defined as builtins inside the `claude-code` module (`skills.nix`). Three exist: adr-writer, diagram, mikrotik-management. They provide domain knowledge that Claude doesn't have out of the box.

The same need exists for CLI tools like AWS CLI, glab, vtecli, and Pulumi. Each tool has non-obvious patterns, gotchas, and recipes that agents repeatedly rediscover (and get wrong). Examples:

- **AWS CLI/SSM**: `send-command` is 30s buffered; `start-session` with piped commands gives real-time streaming. Agents keep using `send-command` for long builds then can't monitor progress.
- **glab**: Token retrieval is `glab config get token --host <hostname>`, not `glab auth token` (doesn't exist). Agents try the wrong subcommand every session.
- **Pulumi**: EC2 AMI changes don't force instance replacement unless the module tracks AMI as a replace-triggering property. Agents discover this the hard way.

These learnings currently live in per-project memory files, which means they're only available in projects where the mistake was already made. Skills are global and loaded on demand.

## Design

**Approach**: Program modules inject Claude Code custom skills when both the program module and `claude-code` are enabled. This uses the existing `programs.claude-code.skills.custom` mechanism; no new skill infrastructure needed.

```
modules/programs/awscli/awscli.nix
  └── config.programs.claude-code.skills.custom.aws-cli = { ... }
      (conditional on programs.claude-code.enable && cfg.enable)

modules/programs/gitlab-auth/
  └── config.programs.claude-code.skills.custom.glab-cli = { ... }

etc.
```

The skill content is defined inline in the program module (via `skillContent`), not as separate SKILL.md files. This keeps tool knowledge co-located with the tool's nix configuration.

**Alternative considered**: Adding builtin skills to `skills.nix` for each tool. Rejected because it couples claude-code to unrelated program modules and doesn't compose -- a user who doesn't have awscli enabled shouldn't see an AWS skill.

## Progress Table

| Task | Status | Description |
|------|--------|-------------|
| T1 | `TASK:PENDING` | AWS CLI + SSM skill (awscli module) |
| T2 | `TASK:PENDING` | glab CLI skill (gitlab-auth module) |
| T3 | `TASK:PENDING` | Pulumi skill (pulumi module) |
| T4 | `TASK:PENDING` | vtecli skill (location TBD, may need new module) |
| T5 | `TASK:PENDING` | Verify skill injection pattern works (home-manager switch + test) |

## Task Details

### T1: AWS CLI + SSM Skill
**Status**: `TASK:PENDING`

Add to `modules/programs/awscli/awscli.nix`:

```nix
config = mkIf cfg.enable {
  programs.claude-code.skills.custom.aws-cli = mkIf config.programs.claude-code.enable {
    description = "AWS CLI and SSM recipes for EC2 instance management, remote command execution, and infrastructure operations. Use when running commands on EC2 via SSM, managing AMIs, or debugging AWS infrastructure.";
    skillContent = ''
      # AWS CLI + SSM Operations Skill
      ...
    '';
  };
};
```

**Skill content to include**:
- SSM command execution: `send-command` (fire-and-forget, 30s buffered output) vs `start-session` (real-time WebSocket streaming)
- Real-time streaming recipe: `(echo "cmd" && cat && exit && exit) | aws ssm start-session --target i-xxx`
- `send-command` with JSON parameters file for complex commands: `--parameters file:///tmp/params.json`
- SSM output retrieval: `list-command-invocations --details --query 'CommandInvocations[0].CommandPlugins[0].Output'`
- EC2 instance profile auth (no credentials needed on EC2 instances with IAM roles)
- EC2 AMI lifecycle: build image, coldsnap upload, register-image, create-tags
- Root volume gotcha: `DescribeInstances` doesn't include VolumeSize in BlockDeviceMappings; use `describe-volumes` separately
- SSM Parameter Store patterns: `get-parameter --with-decryption`, `put-parameter --type SecureString`
- `session-manager-plugin` is required for `start-session` (separate install from AWS CLI)

**DoD**: awscli module conditionally adds the skill. `home-manager switch` succeeds. Skill appears in `~/.claude-*/skills/aws-cli/SKILL.md`.

### T2: glab CLI Skill
**Status**: `TASK:PENDING`

Add to `modules/programs/gitlab-auth/` (or whichever module manages glab).

**Skill content to include**:
- Token retrieval: `glab config get token --host <hostname>` (NOT `glab auth token`, which doesn't exist)
- Pipeline triggering: `glab ci run --branch <branch>` with `--variables KEY:VALUE` (colon separator, not `=`)
- Pipeline status: `glab ci status --branch <branch>` (no `glab ci view <pid>`)
- API calls: `glab api <endpoint>` for REST. For pipeline variables, use `curl` with JSON body (glab api `-f` doesn't pass pipeline variables)
- Runner management: `glab api -X PUT runners/<id> -f paused=true`
- MR creation: `glab mr create --title "..." --description "..."`

**DoD**: gitlab-auth module conditionally adds the skill. Skill appears after home-manager switch.

### T3: Pulumi Skill
**Status**: `TASK:PENDING`

Add to `modules/programs/pulumi/` (if a pulumi HM module exists, otherwise create minimal one).

**Skill content to include**:
- State backend: `PULUMI_BACKEND_URL` for S3, `PULUMI_CONFIG_PASSPHRASE` for encryption
- Stack config (`Pulumi.dev.yaml`) is LOCAL (gitignored), not in state backend
- `pulumi config set` / `pulumi config rm` for stack configuration
- State surgery: `pulumi state delete <urn>` to remove orphaned resources
- AMI changes in EC2 modules may NOT force instance replacement; verify module behavior
- `pulumi preview` before `pulumi up` (always)
- Sensitive values: `pulumi config set --secret <key> <value>`
- `IgnoreChanges` pattern for SSM parameters that get manually overwritten

**DoD**: Pulumi module conditionally adds the skill.

### T4: vtecli Skill
**Status**: `TASK:PENDING`

Determine where vtecli is configured in nixcfg. May need a new module or could piggyback on an existing one.

**Skill content to include**:
- vtecli auto-reads `vrack.env` (don't prepend `source vrack.env &&`)
- Instance management: `vtecli instance list`, `vtecli instance command`
- Image publishing: push to registry.git then cross-copy to gitdock:4567 (`cp` qcow2, not symlink)
- SSH via gateway (8h cert expiry by design)
- VTE has no serial console; use in-image diagnostics only
- Use "hsw-" prefix for instance names, not "n3x-"

**DoD**: vtecli skill is injected by appropriate module.

### T5: Integration Test
**Status**: `TASK:PENDING`

- Run `home-manager switch` on a machine with all four tools enabled
- Verify all four skills appear in `~/.claude-*/skills/`
- Verify skills are NOT present when the corresponding program module is disabled
- Verify skill content renders correctly (no nix string escaping issues)

**DoD**: All skills conditional, all present when expected, none present when tool disabled.

## Execution Notes

- All work in `~/src/nixcfg` on a feature branch
- The `programs.claude-code.skills.custom` attrset requires `programs.claude-code.enable = true`. The `mkIf config.programs.claude-code.enable` guard handles the case where claude-code isn't enabled.
- Nix module system handles cross-module option setting via `config.*` -- no imports needed
- Skill content uses Nix multiline strings (`'' ... ''`); escape `${` as `''${` and `''` within content as `'''`
