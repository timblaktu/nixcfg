# modules/programs/awscli/awscli.nix
# AWS CLI v2 with Azure AD SSO authentication
#
# Provides:
#   flake.modules.homeManager.awscli - AWS CLI v2 with Bitwarden-backed Azure AD login
#
# Features:
#   - AWS CLI v2 installation via programs.awscli
#   - Azure AD SSO via aws-azure-login with rbw credential injection
#   - Nix-managed ~/.aws/config (region, output format, session duration)
#   - Runtime credential injection from Bitwarden via ephemeral tmpfs config
#   - Optional fully non-interactive mode with auto-TOTP via expect
#   - Flexible profile support for multi-account setups
#
# Usage in host config:
#   imports = [ inputs.self.modules.homeManager.awscli ];
#   awscli = {
#     enable = true;
#     azureAuth = {
#       enable = true;
#       # Fully non-interactive with TOTP:
#       bitwarden.credentialItem = "PAC Microsoft account";
#       bitwarden.roleArnItem = "AWS Role ARN";
#       autoTotp = true;
#     };
#   };
#
# Authentication flow:
#   1. User runs `aws-azure-login` (wrapper)
#   2. Wrapper fetches credentials from Bitwarden via rbw
#   3. Wrapper creates ephemeral config on tmpfs ($XDG_RUNTIME_DIR)
#   4. AWS_CONFIG_FILE points to ephemeral config (secrets never touch disk)
#   5. Real aws-azure-login handles Azure AD SAML auth (headless Chromium)
#   6. If autoTotp: expect auto-fills TOTP from `rbw code`
#   7. Temporary AWS STS credentials written to ~/.aws/credentials
#   8. Ephemeral config cleaned up on exit (trap)
{ config, lib, inputs, ... }:
{
  flake.modules = {
    homeManager.awscli = { config, lib, pkgs, ... }:
      with lib;
      let
        cfg = config.awscli;
        bw = cfg.azureAuth.bitwarden;
        hasCredentials = bw.credentialItem != null;
        hasRoleArn = bw.roleArnItem != null || cfg.azureAuth.defaultRoleArn != null;

        roles = cfg.azureAuth.knownRoles;
        roleNames = attrNames roles;
        roleNamesStr = concatStringsSep " " roleNames;

        # Shell case arms to resolve role shortnames to full ARNs
        roleCaseArms = concatStringsSep "\n" (mapAttrsToList
          (name: arn:
            "      ${escapeShellArg name}) _AAL_ROLE_ARN=${escapeShellArg arn} ;;"
          )
          roles);

        # --list-roles output
        listRolesLines =
          if roles == { } then
            ''  echo "  (none configured - add roles to awscli.azureAuth.knownRoles)"''
          else
            concatStringsSep "\n" (mapAttrsToList
              (name: arn:
                ''  printf '  %-20s %s\n' ${escapeShellArg name} ${escapeShellArg arn}''
              )
              roles);

        # Patched aws-azure-login: fix password handler infinite loop.
        # Upstream bug: after clicking submit, the 500ms delay is too short for
        # Azure AD to process the AJAX request and navigate away. The password
        # field is re-detected, causing the password to be typed repeatedly
        # (appended each iteration). Fix: clear field before typing + wait for
        # navigation after submit instead of a fixed delay.
        # Affects v3.6.1-3.6.5. Upstream: github.com/sportradar/aws-azure-login
        #
        # WORKAROUND — remove when upstream fixes password state handler
        # ERROR: "Found state: password input" loops infinitely with --no-prompt
        patchPasswordHandler = pkgs.writeText "patch-password-handler.py" ''
          import sys
          f = sys.argv[1]
          with open(f) as fh:
              lines = fh.readlines()

          # Find the password handler's "Focusing on password input" line
          i = 0
          patched = False
          while i < len(lines):
              line = lines[i]
              if 'debug("Focusing on password input")' in line and not patched:
                  # Next line should be the page.focus call
                  if i + 1 < len(lines) and 'page.focus' in lines[i + 1]:
                      # Insert field-clear commands after the focus line
                      indent = "            "
                      clear_lines = [
                          f'{indent}debug("Clearing existing password input");\n',
                          f'{indent}await page.keyboard.down("Control");\n',
                          f'{indent}await page.keyboard.press("a");\n',
                          f'{indent}await page.keyboard.up("Control");\n',
                          f'{indent}await page.keyboard.press("Backspace");\n',
                      ]
                      lines = lines[:i+2] + clear_lines + lines[i+2:]
                      i += 2 + len(clear_lines)

                      # Find "Waiting for a delay" + delay(500) in the password handler
                      # (within the next ~10 lines)
                      for j in range(i, min(i + 10, len(lines))):
                          if 'debug("Waiting for a delay")' in lines[j]:
                              lines[j] = lines[j].replace(
                                  'debug("Waiting for a delay")',
                                  'debug("Waiting for navigation after password submit")'
                              )
                              if j + 1 < len(lines) and 'delay(500)' in lines[j + 1]:
                                  lines[j + 1] = (
                                      f'{indent}try {{ await page.waitForNavigation({{ waitUntil: "domcontentloaded", timeout: 10000 }}); }}'
                                      f' catch (e) {{ debug("Navigation wait timed out: " + e.message); }}\n'
                                      f'{indent}await bluebird_1.default.delay(1000);\n'
                                  )
                              patched = True
                              break
                      continue
              i += 1

          if not patched:
              print(f"ERROR: Could not find password handler to patch in {f}", file=sys.stderr)
              sys.exit(1)

          with open(f, "w") as fh:
              fh.writelines(lines)
          print(f"Patched {f}: password handler clears field + waits for navigation")
        '';

        # On darwin, nixpkgs' aws-azure-login hard-sets PUPPETEER_EXECUTABLE_PATH
        # to nixpkgs `chromium`, which is not built for aarch64-darwin (it aborts
        # eval). aws-azure-login drives the browser via Puppeteer (Chrome DevTools
        # Protocol), so it needs a CHROMIUM-FAMILY browser - Firefox/Gecko is not
        # supported. Swap the `chromium` dependency for a thin shim that execs the
        # Homebrew-installed Chromium app, so no nix chromium is pulled and
        # Puppeteer drives the real browser. The host must install the `chromium`
        # Homebrew cask (see hosts/...#pa163076mac). Linux is unchanged.
        chromiumDarwinShim = pkgs.writeShellScriptBin "chromium" ''
          exec /Applications/Chromium.app/Contents/MacOS/Chromium "$@"
        '';
        awsAzureLoginBase =
          if pkgs.stdenv.isDarwin
          then pkgs.aws-azure-login.override { chromium = chromiumDarwinShim; }
          else pkgs.aws-azure-login;

        aws-azure-login-patched = awsAzureLoginBase.overrideAttrs (old: {
          postInstall = (old.postInstall or "") + ''
            ${pkgs.python3}/bin/python3 ${patchPasswordHandler} \
              "$out/lib/node_modules/aws-azure-login/lib/login.js"
          '';
        });

        # ===== Inline rbw helper library =====
        rbwLib = rec {
          defaultStaleSeconds = 300;

          mkRbwGetCommand = { item, field ? null }:
            let
              rbwBin = "${pkgs.rbw}/bin/rbw";
              itemArg = escapeShellArg item;
              fieldArg =
                if field != null && field != ""
                then ''--field ${escapeShellArg field}''
                else "";
            in
            "${rbwBin} get ${itemArg} ${fieldArg}";

          mkRbwSyncIfStale = { staleSeconds ? defaultStaleSeconds }:
            let
              rbwBin = "${pkgs.rbw}/bin/rbw";
            in
            ''
              # Time-based rbw sync: only sync if last sync was >${toString staleSeconds}s ago
              _RBW_SYNC_FILE="''${XDG_RUNTIME_DIR:-/tmp}/.rbw-last-sync-$USER"
              _RBW_NOW=$(date +%s)
              _RBW_LAST_SYNC=$(stat -c %Y "$_RBW_SYNC_FILE" 2>/dev/null || echo 0)
              _RBW_SYNC_AGE=$((_RBW_NOW - _RBW_LAST_SYNC))
              if [ "$_RBW_SYNC_AGE" -gt ${toString staleSeconds} ]; then
                ${rbwBin} sync 2>/dev/null || true
                touch "$_RBW_SYNC_FILE" 2>/dev/null || true
              fi
              unset _RBW_SYNC_FILE _RBW_NOW _RBW_LAST_SYNC _RBW_SYNC_AGE
            '';
        };

        # ===== Python script to merge secrets into AWS config =====
        # Reads AAL_* env vars and injects them into the ini file
        configMergeScript = pkgs.writeScript "aws-config-merge.py" ''
          #!${pkgs.python3}/bin/python3
          import configparser, sys, os

          f = sys.argv[1]
          c = configparser.RawConfigParser()
          c.read(f)

          section = "default"
          if not c.has_section(section):
              c.add_section(section)

          env_to_key = {
              "AAL_TENANT_ID": "azure_tenant_id",
              "AAL_APP_ID_URI": "azure_app_id_uri",
              "AAL_USERNAME": "azure_default_username",
              "AAL_PASSWORD": "azure_default_password",
              "AAL_ROLE_ARN": "azure_default_role_arn",
          }

          def escape_ini_value(v):
              """Escape # and ; for the npm 'ini' parser which treats them as inline comments."""
              return v.replace("\\", "\\\\").replace(";", "\\;").replace("#", "\\#")

          for envvar, key in env_to_key.items():
              val = os.environ.get(envvar)
              if val:
                  c.set(section, key, escape_ini_value(val))

          # Auto-click "stay signed in" when credentials are injected
          if os.environ.get("AAL_USERNAME"):
              c.set(section, "azure_default_remember_me", "true")

          with open(f, "w") as fh:
              c.write(fh)
        '';

        # ===== Expect script for auto-TOTP injection =====
        # Spawns aws-azure-login, watches for TOTP prompt, feeds code from rbw.
        # When AAL_INTERACTIVE=1 (no --role-arn), hands control to user after TOTP
        # so they can respond to the interactive role selection prompt.
        expectScript = pkgs.writeScript "aws-azure-login-expect" ''
          #!${pkgs.expect}/bin/expect -f
          set timeout 300
          log_user 1

          set interactive 0
          if {[info exists env(AAL_INTERACTIVE)] && ''$env(AAL_INTERACTIVE) == 1} {
            set interactive 1
          }

          set args [lrange ''$argv 0 end]
          spawn {*}''$args

          expect {
            "Verification Code:" {
              log_user 0
              set totp [exec ${pkgs.rbw}/bin/rbw code {${bw.credentialItem}}]
              send "''$totp\r"
              log_user 1
              if {''$interactive} {
                # Hand control to user for role selection prompt
                interact
              } else {
                exp_continue
              }
            }
            eof
          }

          catch wait result
          if {[llength ''$result] >= 4} {
            exit [lindex ''$result 3]
          }
          exit 0
        '';

        # ===== aws-azure-login wrapper =====
        # Creates ephemeral config on tmpfs, injects rbw secrets, delegates to real binary.
        # Supports --role-arn <name-or-arn> for non-interactive role selection,
        # or omit for interactive role picker after SAML auth.
        aws-azure-login-wrapper = pkgs.writeShellScriptBin "aws-azure-login" ''
          set -euo pipefail

          # --- Parse wrapper-specific arguments ---
          _AAL_ROLE_ARN=""
          _AAL_PASSTHROUGH=()
          while [[ $# -gt 0 ]]; do
            case "$1" in
              --role-arn)
                [[ $# -lt 2 ]] && { echo "Error: --role-arn requires a value" >&2; exit 1; }
                _AAL_ROLE_ARN="$2"; shift 2 ;;
              --role-arn=*)
                _AAL_ROLE_ARN="''${1#--role-arn=}"; shift ;;
              --list-roles)
                echo "Known roles:"
                ${listRolesLines}
                echo ""
                echo "Use --role-arn <name> or --role-arn <full-arn> for non-interactive login."
                echo "Omit --role-arn for interactive role selection."
                exit 0 ;;
              *)
                _AAL_PASSTHROUGH+=("$1"); shift ;;
            esac
          done
          set -- "''${_AAL_PASSTHROUGH[@]+"''${_AAL_PASSTHROUGH[@]}"}"

          # --- Resolve role shortnames to full ARNs ---
          if [[ -n "$_AAL_ROLE_ARN" ]] && [[ "$_AAL_ROLE_ARN" != arn:* ]]; then
            case "$_AAL_ROLE_ARN" in
          ${roleCaseArms}
              *)
                echo "Error: Unknown role name '$_AAL_ROLE_ARN'" >&2
                echo "Known roles: ${if roleNamesStr == "" then "(none configured)" else roleNamesStr}" >&2
                echo "Use a full ARN or add to awscli.azureAuth.knownRoles in nix config." >&2
                exit 1 ;;
            esac
          fi

          ${rbwLib.mkRbwSyncIfStale { staleSeconds = cfg.rbwSyncInterval; }}

          # Fetch Azure AD config from Bitwarden
          AAL_TENANT_ID="$(${rbwLib.mkRbwGetCommand {
            inherit (bw) item;
            field = bw.tenantIdField;
          }} 2>/dev/null)" || {
            echo "Error: Failed to retrieve Azure Tenant ID from Bitwarden" >&2
            echo "  Item: ${bw.item}, Field: ${bw.tenantIdField}" >&2
            echo "  Ensure rbw is unlocked: rbw unlock" >&2
            exit 1
          }
          export AAL_TENANT_ID

          AAL_APP_ID_URI="$(${rbwLib.mkRbwGetCommand {
            inherit (bw) item;
            field = bw.appIdUriField;
          }} 2>/dev/null)" || {
            echo "Error: Failed to retrieve Azure App ID URI from Bitwarden" >&2
            echo "  Item: ${bw.item}, Field: ${bw.appIdUriField}" >&2
            exit 1
          }
          export AAL_APP_ID_URI

          ${optionalString hasCredentials ''
            # Fetch user credentials from Bitwarden
            AAL_USERNAME="$(${rbwLib.mkRbwGetCommand {
              item = bw.credentialItem;
              field = bw.usernameField;
            }} 2>/dev/null)" || {
              echo "Error: Failed to retrieve username from Bitwarden" >&2
              echo "  Item: ${bw.credentialItem}, Field: ${toString bw.usernameField}" >&2
              exit 1
            }
            export AAL_USERNAME

            AAL_PASSWORD="$(${rbwLib.mkRbwGetCommand {
              item = bw.credentialItem;
              field = bw.passwordField;
            }} 2>/dev/null)" || {
              echo "Error: Failed to retrieve password from Bitwarden" >&2
              echo "  Item: ${bw.credentialItem}" >&2
              exit 1
            }
            export AAL_PASSWORD
          ''}

          # Set role ARN only if explicitly provided via --role-arn
          if [[ -n "$_AAL_ROLE_ARN" ]]; then
            export AAL_ROLE_ARN="$_AAL_ROLE_ARN"
          fi

          # Create ephemeral config on tmpfs (secrets never touch persistent storage)
          _TMPCONFIG="$(mktemp "''${XDG_RUNTIME_DIR:-/tmp}/aws-config.XXXXXX")"
          trap 'rm -f "$_TMPCONFIG"' EXIT

          # Copy HM-generated config as base, then inject secrets
          if [ -f "$HOME/.aws/config" ]; then
            cp "$HOME/.aws/config" "$_TMPCONFIG"
          else
            touch "$_TMPCONFIG"
          fi
          ${configMergeScript} "$_TMPCONFIG"

          # When no role specified, strip any default role ARN from config
          # so aws-azure-login shows the interactive role picker
          if [[ -z "$_AAL_ROLE_ARN" ]]; then
            ${pkgs.gnused}/bin/sed -i '/^azure_default_role_arn/d' "$_TMPCONFIG"
          fi

          export AWS_CONFIG_FILE="$_TMPCONFIG"

          # Set interactive flag for expect script (enables role picker after TOTP)
          if [[ -z "$_AAL_ROLE_ARN" ]]; then
            export AAL_INTERACTIVE=1
          fi

          ${if hasCredentials && cfg.azureAuth.autoTotp then ''
            if [[ -n "$AAL_INTERACTIVE" ]]; then
              # Interactive role selection: skip expect so arrow keys work in
              # the inquirer prompt (expect's interact mangles escape sequences).
              # User types TOTP manually.
              exec ${aws-azure-login-patched}/bin/aws-azure-login --no-prompt --no-sandbox "$@"
            else
              # Fully non-interactive: expect handles TOTP prompt
              exec ${expectScript} \
                ${aws-azure-login-patched}/bin/aws-azure-login --no-prompt --no-sandbox "$@"
            fi
          '' else if hasCredentials then ''
            # Credentials from rbw, user handles TOTP + role selection interactively
            exec ${aws-azure-login-patched}/bin/aws-azure-login --no-prompt --no-sandbox "$@"
          '' else ''
            # Fully interactive: only tenant/app config injected
            exec ${aws-azure-login-patched}/bin/aws-azure-login --no-sandbox "$@"
          ''}
        '';

        # ===== Shell completions for --role-arn =====
        bashCompletionContent = ''
          _aws_azure_login() {
            local cur prev
            COMPREPLY=()
            cur="''${COMP_WORDS[COMP_CWORD]}"
            prev="''${COMP_WORDS[COMP_CWORD-1]}"

            case "$prev" in
              --role-arn)
                COMPREPLY=($(compgen -W "${roleNamesStr}" -- "$cur"))
                return ;;
            esac

            COMPREPLY=($(compgen -W "--role-arn --list-roles" -- "$cur"))
          }
          complete -F _aws_azure_login aws-azure-login
        '';

        zshCompletionContent = ''
          #compdef aws-azure-login
          _aws-azure-login() {
            _arguments -s \
              '--role-arn[AWS role ARN or known role name]:role:(${roleNamesStr})' \
              '--list-roles[List known role names and ARNs]' \
              '*::: '
          }
          _aws-azure-login "$@"
        '';

      in
      {
        options.awscli = {
          enable = mkEnableOption "AWS CLI v2 with optional Azure AD SSO integration";

          defaultRegion = mkOption {
            type = types.str;
            default = "us-west-2";
            description = "Default AWS region";
            example = "us-east-1";
          };

          outputFormat = mkOption {
            type = types.enum [ "json" "yaml" "yaml-stream" "text" "table" ];
            default = "json";
            description = "Default output format for AWS CLI commands";
          };

          rbwSyncInterval = mkOption {
            type = types.int;
            default = 300;
            description = ''
              Seconds before rbw cache is considered stale and triggers a sync.
              Default: 300 (5 minutes). Set to 0 to sync every time.
            '';
          };

          azureAuth = {
            enable = mkEnableOption "Azure AD SSO authentication via aws-azure-login";

            bitwarden = {
              item = mkOption {
                type = types.str;
                default = "Azure AD";
                description = "Bitwarden item name containing Azure AD tenant/app config";
              };

              tenantIdField = mkOption {
                type = types.str;
                default = "Azure Tenant ID";
                description = "Custom field name within the Bitwarden item for Azure Tenant ID";
              };

              appIdUriField = mkOption {
                type = types.str;
                default = "Azure App ID URI";
                description = "Custom field name within the Bitwarden item for Azure App ID URI";
              };

              credentialItem = mkOption {
                type = types.nullOr types.str;
                default = null;
                description = ''
                  Bitwarden item containing Azure AD login credentials (username/password).
                  When set, enables non-interactive mode (--no-prompt) with credentials
                  auto-filled from this item. The item should also have TOTP configured
                  if autoTotp is enabled.
                '';
                example = "PAC Microsoft account";
              };

              usernameField = mkOption {
                type = types.nullOr types.str;
                default = "username";
                description = ''
                  Field name for the username within the credential item.
                  "username" (default) retrieves the built-in Bitwarden username field.
                  Set to a custom field name if your item stores it differently.
                '';
              };

              passwordField = mkOption {
                type = types.nullOr types.str;
                default = null;
                description = ''
                  Field name for the password within the credential item.
                  null (default) retrieves the item's main password field.
                  Set to a custom field name if needed.
                '';
              };

              roleArnItem = mkOption {
                type = types.nullOr types.str;
                default = null;
                description = ''
                  Bitwarden item containing the AWS Role ARN to assume.
                  Overrides defaultRoleArn when set. Required for non-interactive
                  mode when your account has multiple roles.
                '';
                example = "AWS Role ARN";
              };

              roleArnField = mkOption {
                type = types.nullOr types.str;
                default = "Role ARN";
                description = "Field name for the role ARN within the Bitwarden item";
              };
            };

            autoTotp = mkOption {
              type = types.bool;
              default = false;
              description = ''
                Automatically fill the TOTP verification code from Bitwarden
                using `rbw code`. Requires credentialItem to be configured
                with TOTP set up on the item. Uses expect to inject the code
                into the interactive TOTP prompt.
              '';
            };

            defaultDurationHours = mkOption {
              type = types.int;
              default = 8;
              description = ''
                Default AWS session duration in hours (1-8).
                Azure AD federation typically allows up to 8 hours.
              '';
            };

            defaultRoleArn = mkOption {
              type = types.nullOr types.str;
              default = null;
              description = ''
                Default IAM role ARN baked into ~/.aws/config. Only used when
                --role-arn is passed (the config merge injects it). When omitted
                and no --role-arn is given, the interactive role picker appears.
                Prefer knownRoles for named role shortcuts.
              '';
              example = "arn:aws:iam::123456789012:role/MyRole";
            };

            knownRoles = mkOption {
              type = types.attrsOf types.str;
              default = { };
              description = ''
                Named AWS role ARNs for the --role-arn shorthand and shell completion.
                Keys are short names used on the CLI, values are full IAM role ARNs.
                Run `aws-azure-login --list-roles` to see configured roles.
              '';
              example = literalExpression ''
                {
                  dev = "arn:aws:iam::205930615774:role/app-developer";
                  vrack = "arn:aws:iam::780648478424:role/eks-admin";
                }
              '';
            };
          };

          extraSettings = mkOption {
            type = types.attrsOf (types.attrsOf types.str);
            default = { };
            description = ''
              Additional profile sections for ~/.aws/config.
              Keys are section names (e.g., "profile staging"), values are
              attribute sets of config keys.
            '';
            example = literalExpression ''
              {
                "profile staging" = {
                  region = "us-east-1";
                  output = "table";
                };
              }
            '';
          };
        };

        config = mkIf cfg.enable (mkMerge [
          # Inject Claude Code skill when both awscli and claude-code are enabled
          (mkIf (config.programs.claude-code.enable or false) {
            programs.claude-code.skills.custom.aws-cli = {
              description = "AWS CLI and SSM recipes for EC2 instance management, remote command execution, and infrastructure operations. Use when running commands on EC2 via SSM, managing AMIs, or debugging AWS infrastructure.";
              skillContent = ''
                # AWS CLI + SSM Operations Skill

                ## SSM Command Execution

                Two modes for running commands on EC2 instances via SSM:

                ### send-command (fire-and-forget, buffered output)
                - Output is buffered for ~30 seconds before becoming available
                - Good for short, simple commands where you don't need real-time output
                - Retrieve output with `list-command-invocations --details`

                ```bash
                # Send a command
                aws ssm send-command \
                  --instance-ids i-xxx \
                  --document-name AWS-RunShellScript \
                  --parameters commands=["your-command-here"]

                # Get output (wait ~30s for buffer flush)
                aws ssm list-command-invocations \
                  --command-id <id> \
                  --details \
                  --query 'CommandInvocations[0].CommandPlugins[0].Output'
                ```

                For complex commands, use a JSON parameters file:
                ```bash
                aws ssm send-command \
                  --instance-ids i-xxx \
                  --document-name AWS-RunShellScript \
                  --parameters file:///tmp/params.json
                ```

                ### start-session (real-time WebSocket streaming)
                - Real-time output, no buffering
                - Requires `session-manager-plugin` installed locally
                - Use for long-running builds, monitoring, or interactive work

                ```bash
                # Real-time streaming recipe (pipe commands into session)
                (echo "your-command-here" && cat && exit && exit) | \
                  aws ssm start-session --target i-xxx
                ```

                **CRITICAL**: Always prefer `start-session` for builds or any command >30 seconds.
                `send-command` output truncates at 48000 chars and the 30s buffer makes monitoring impossible.

                ## EC2 Operations

                ### AMI Lifecycle
                ```bash
                # Root volume gotcha: DescribeInstances doesn't include VolumeSize
                # in BlockDeviceMappings. Use describe-volumes separately:
                aws ec2 describe-volumes --volume-ids vol-xxx \
                  --query 'Volumes[0].Size'
                ```

                ### Instance Profile Auth
                EC2 instances with IAM roles need no credentials - the instance profile provides them automatically. Do NOT set `AWS_ACCESS_KEY_ID` on EC2 instances.

                ## SSM Parameter Store
                ```bash
                # Read (with decryption for SecureString)
                aws ssm get-parameter --name /path/to/param --with-decryption

                # Write
                aws ssm put-parameter --name /path/to/param --type SecureString --value "secret"
                ```

                ## Prerequisites
                - `session-manager-plugin` must be installed for `start-session` to work
                - It is a separate install from AWS CLI itself
              '';
            };
          })
          # Base: AWS CLI v2 with Nix-managed config
          {
            programs.awscli = {
              enable = true;
              package = pkgs.awscli2;
              settings = mkMerge [
                {
                  "default" = {
                    region = cfg.defaultRegion;
                    output = cfg.outputFormat;
                    cli_pager = "";
                  };
                }
                (mkIf cfg.azureAuth.enable {
                  "default" = mkMerge [
                    {
                      azure_default_duration_hours = toString cfg.azureAuth.defaultDurationHours;
                    }
                    (mkIf (cfg.azureAuth.defaultRoleArn != null) {
                      azure_default_role_arn = cfg.azureAuth.defaultRoleArn;
                    })
                  ];
                })
                cfg.extraSettings
              ];
            };
          }

          # Azure AD SSO: aws-azure-login wrapper with Bitwarden injection
          (mkIf cfg.azureAuth.enable {
            home.packages = [ aws-azure-login-wrapper ];

            # Shell completions for --role-arn
            home.file.".local/share/bash-completion/completions/aws-azure-login".text = bashCompletionContent;
            home.file.".local/share/zsh/site-functions/_aws-azure-login".text = zshCompletionContent;

            assertions = [
              {
                assertion = config.secretsManagement.enable or false;
                message = "awscli.azureAuth requires secretsManagement.enable = true (for rbw/Bitwarden)";
              }
              {
                assertion = !cfg.azureAuth.autoTotp || bw.credentialItem != null;
                message = "awscli.azureAuth.autoTotp requires bitwarden.credentialItem to be configured";
              }
            ];

            warnings =
              optional ((config.secretsManagement.rbw.email or null) == null)
                "awscli.azureAuth: Bitwarden integration enabled but secretsManagement.rbw.email not set. Run 'rbw-init' to configure.";
          })
        ]);
      };
  };
}
