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
#   - Runtime secret injection from Bitwarden via ENV (never written to disk)
#   - Optional fully non-interactive mode with auto-TOTP via expect
#   - Per-session profile isolation: each non-default profile gets its own
#     credentials file (~/.aws/credentials.d/<name>) so concurrent auths of
#     different profiles never clobber each other
#   - Optional direnv helper (azureAuth.direnvHelper) for per-directory binding
#   - Optional zero-touch refresh (profiles.<name>.credentialProcess): emits a
#     credential_process line so aws/boto/pulumi auto-refresh a profile on demand
#     (headless + autoTotp) with no explicit aws-azure-login run (needs rbw
#     unlocked; opt-in per profile)
#
# Per-session usage modes (bind a shell/dir to a distinct AWS profile):
#   1. Ad-hoc, per shell:
#        export AWS_PROFILE=eks-admin        # aws-azure-login + aws both honour it
#        aws-azure-login                     # wrapper isolates creds by profile
#        aws sts get-caller-identity
#      (or one-shot: `AWS_PROFILE=eks-admin aws-azure-login`)
#   2. Per-directory, via direnv (azureAuth.direnvHelper installs the stdlib fn
#      `use_aws_profile` into ~/.config/direnv/lib/aws-profile.sh). A project
#      .envrc then needs a single line:
#        use aws_profile eks-admin
#      On `direnv allow`, entering the dir exports AWS_PROFILE and the matching
#      AWS_SHARED_CREDENTIALS_FILE. Equivalent explicit form (no helper):
#        export AWS_PROFILE=eks-admin
#        export AWS_SHARED_CREDENTIALS_FILE="$HOME/.aws/credentials.d/eks-admin"
#
# Concurrency: shells using the SAME profile share one credentials file (fine —
# they authenticate the same identity). Shells using DIFFERENT profiles are fully
# isolated: each writes/reads its own ~/.aws/credentials.d/<name>, so concurrent
# logins never clobber each other (aws-azure-login's credential write is unlocked).
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
#       knownRoles = { dev = "arn:...:role/dev"; eks-admin = "arn:...:role/eks-admin"; };
#       # Per-session profiles (each isolates its own STS creds):
#       profiles = {
#         default = { role = "dev"; };
#         eks-admin = { role = "eks-admin"; region = "us-west-2"; };
#       };
#     };
#   };
#
# Authentication flow:
#   1. User runs `AWS_PROFILE=<name> aws-azure-login` (wrapper) or `--profile <name>`
#   2. Wrapper resolves the target profile (--profile > $AWS_PROFILE > "default")
#      and its role ARN (from azureAuth.profiles via knownRoles)
#   3. Wrapper fetches secrets from Bitwarden via rbw and exports them as AZURE_*
#      env vars (aws-azure-login overrides the on-disk profile config at runtime)
#   4. AWS_CONFIG_FILE points at the Nix-managed ~/.aws/config (non-secret stub);
#      AWS_SHARED_CREDENTIALS_FILE isolates the profile's STS creds
#   5. Real aws-azure-login handles Azure AD SAML auth (headless Chromium)
#   6. If autoTotp: expect auto-fills TOTP from `rbw code`
#   7. Temporary AWS STS credentials written to the per-profile credentials file
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

        # ===== Per-session profile stubs =====
        # Each named profile emits a NON-SECRET [profile <name>] (or [default])
        # stub into ~/.aws/config so aws-azure-login's "must be configured" check
        # passes. Role ARNs / secrets are injected via env at run time (T2), never
        # written here.
        profiles = cfg.azureAuth.profiles;

        # The "default" key maps to the [default] section; every other <name> maps
        # to [profile <name>].
        profileSectionName = name: if name == "default" then "default" else "profile ${name}";

        # Non-secret config stub: region (fallback defaultRegion), duration
        # (fallback azureAuth.defaultDurationHours), plus `output` as a benign
        # marker so the section is always non-empty.
        mkProfileSection = _name: p:
          {
            region = if p.region != null then p.region else cfg.defaultRegion;
            azure_default_duration_hours =
              toString (if p.durationHours != null then p.durationHours else cfg.azureAuth.defaultDurationHours);
            output = cfg.outputFormat;
          }
          # Opt-in zero-touch refresh (T4): wire this profile's on-demand refresh
          # shim. Only emitted when the profile sets credentialProcess = true.
          // optionalAttrs p.credentialProcess {
            credential_process =
              "${aws-azure-login-credential-process}/bin/aws-azure-login-credential-process ${_name}";
          };

        # Profiles that opted into credential_process zero-touch refresh.
        credentialProcessProfiles = filter (name: profiles.${name}.credentialProcess) (attrNames profiles);

        profileSettings = mapAttrs'
          (name: p: nameValuePair (profileSectionName name) (mkProfileSection name p))
          profiles;

        # Profiles whose `role` is neither an arn:* literal nor a knownRoles key.
        # Surfaced as an eval-time assertion so a bad reference can never become a
        # runtime blocking failure.
        unknownRoleProfiles = filter
          (name: let r = profiles.${name}.role; in !(hasPrefix "arn:" r) && !(roles ? ${r}))
          (attrNames profiles);

        # Resolve a profile's `role` to a full ARN at eval time. `role` is either
        # an arn:* literal or a knownRoles key (validated by the assertion above).
        # `roles.${p.role} or ""` keeps a bad reference from throwing hard here so
        # the friendly assertion message is what surfaces (the build still fails).
        resolveProfileRoleArn = p:
          if hasPrefix "arn:" p.role then p.role else (roles.${p.role} or "");

        # Shell case arms mapping a resolved profile name -> its role ARN and
        # (optional) duration. Consumed by the wrapper to export AZURE_DEFAULT_*.
        profileCaseArms = concatStringsSep "\n" (mapAttrsToList
          (name: p:
            "        ${escapeShellArg name}) "
            + "_AAL_PROFILE_ROLE_ARN=${escapeShellArg (resolveProfileRoleArn p)}; "
            + "_AAL_PROFILE_DURATION=${escapeShellArg (if p.durationHours != null then toString p.durationHours else "")} ;;"
          )
          profiles);

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

        # Force the Chrome DevTools Protocol *pipe* transport instead of the
        # default WebSocket-over-loopback transport.
        #
        # ROOT CAUSE (diagnosed 2026-07-17, supersedes the "Puppeteer<->Chromium
        # version mismatch" hypothesis): aws-azure-login failed at launch with
        #   Error: connect ECONNREFUSED 127.0.0.1:<port>
        #   _url: 'ws://127.0.0.1:<port>/devtools/browser/...'
        # Chromium starts, prints "DevTools listening on ws://127.0.0.1:<port>",
        # but Puppeteer's WebSocket connect to that loopback port is refused.
        # This is a transport problem, NOT a version problem:
        #   - The bundled Puppeteer 13.6.0 fails over WS against modern Chromium.
        #   - A modern Puppeteer (25.3.0) ALSO fails over WS in the same env.
        #   - BOTH succeed once launched with `pipe: true` (fd 3/4 instead of a
        #     loopback socket). So upgrading Puppeteer alone would not have fixed
        #     it; switching transports does.
        # The loopback DevTools endpoint is unreachable under this WSL/Chromium
        # combination (Chromium >=111 tightened the DevTools socket handshake);
        # the pipe transport sidesteps the socket entirely and is version-robust.
        #
        # WORKAROUND — remove if a future aws-azure-login opts into pipe transport
        # itself, or if the loopback WS endpoint becomes reachable again.
        patchPipeTransport = pkgs.writeText "patch-pipe-transport.py" ''
          import sys
          f = sys.argv[1]
          with open(f) as fh:
              src = fh.read()

          anchor = "puppeteer_1.default.launch({\n"
          if "pipe: true" in src:
              print(f"{f}: pipe transport already present, skipping")
          elif anchor not in src:
              print(f"ERROR: Could not find puppeteer launch call to patch in {f}", file=sys.stderr)
              sys.exit(1)
          else:
              # Insert `pipe: true,` as the first launch option (16-space indent,
              # matching the sibling `headless,` key).
              src = src.replace(anchor, anchor + "                pipe: true,\n", 1)
              with open(f, "w") as fh:
                  fh.write(src)
              print(f"Patched {f}: forced Chrome DevTools pipe transport (bypasses WS loopback)")
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
            ${pkgs.python3}/bin/python3 ${patchPipeTransport} \
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
        # Profile-aware wrapper. Resolves a target AWS profile
        # (explicit --profile > $AWS_PROFILE > "default"), injects Azure AD secrets
        # from Bitwarden (rbw) via ENV (never written to disk), points the real
        # binary at the Nix-managed ~/.aws/config for the profile's non-secret stub,
        # and isolates each non-default profile's STS creds in its own file under
        # ~/.aws/credentials.d/<name> (aws-azure-login's credential write is
        # unlocked, so separate files prevent concurrent-auth clobber).
        #
        # Supports --role-arn <name-or-arn> for non-interactive role selection
        # (overrides the profile's role); omit for the interactive role picker.
        aws-azure-login-wrapper = pkgs.writeShellScriptBin "aws-azure-login" ''
                    set -euo pipefail

                    # --- Parse wrapper-specific arguments ---
                    # --profile is captured for our own resolution (cred file + role lookup)
                    # and re-appended to the real binary's args below (never in passthrough).
                    _AAL_ROLE_ARN=""
                    _AAL_PROFILE_ARG=""
                    _AAL_PASSTHROUGH=()
                    while [[ $# -gt 0 ]]; do
                      case "$1" in
                        --profile)
                          [[ $# -lt 2 ]] && { echo "Error: --profile requires a value" >&2; exit 1; }
                          _AAL_PROFILE_ARG="$2"; shift 2 ;;
                        --profile=*)
                          _AAL_PROFILE_ARG="''${1#--profile=}"; shift ;;
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

                    # --- Resolve the target profile: --profile > $AWS_PROFILE > "default" ---
                    if [[ -n "$_AAL_PROFILE_ARG" ]]; then
                      _AAL_PROFILE="$_AAL_PROFILE_ARG"
                    else
                      _AAL_PROFILE="''${AWS_PROFILE:-default}"
                    fi

                    # Only pass --profile to the real binary for non-default profiles
                    # (aws-azure-login already defaults to "default"), keeping the default
                    # invocation byte-identical to the pre-profiles behaviour.
                    _AAL_PROFILE_ARGS=()
                    if [[ "$_AAL_PROFILE" != "default" ]]; then
                      _AAL_PROFILE_ARGS=(--profile "$_AAL_PROFILE")
                    fi

                    # --- Resolve the profile's role ARN + duration (from awscli.azureAuth.profiles) ---
                    _AAL_PROFILE_ROLE_ARN=""
                    _AAL_PROFILE_DURATION=""
                    case "$_AAL_PROFILE" in
          ${profileCaseArms}
                      *) : ;;
                    esac

                    # --- Resolve an explicit --role-arn shortname to a full ARN ---
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

                    # --- Inject Azure AD secrets via ENV (aws-azure-login reads AZURE_* and
                    # overrides the on-disk profile config; secrets never touch disk) ---
                    AZURE_TENANT_ID="$(${rbwLib.mkRbwGetCommand {
                      inherit (bw) item;
                      field = bw.tenantIdField;
                    }} 2>/dev/null)" || {
                      echo "Error: Failed to retrieve Azure Tenant ID from Bitwarden" >&2
                      echo "  Item: ${bw.item}, Field: ${bw.tenantIdField}" >&2
                      echo "  Ensure rbw is unlocked: rbw unlock" >&2
                      exit 1
                    }
                    export AZURE_TENANT_ID

                    AZURE_APP_ID_URI="$(${rbwLib.mkRbwGetCommand {
                      inherit (bw) item;
                      field = bw.appIdUriField;
                    }} 2>/dev/null)" || {
                      echo "Error: Failed to retrieve Azure App ID URI from Bitwarden" >&2
                      echo "  Item: ${bw.item}, Field: ${bw.appIdUriField}" >&2
                      exit 1
                    }
                    export AZURE_APP_ID_URI

                    ${optionalString hasCredentials ''
                      # Fetch user credentials from Bitwarden
                      AZURE_DEFAULT_USERNAME="$(${rbwLib.mkRbwGetCommand {
                        item = bw.credentialItem;
                        field = bw.usernameField;
                      }} 2>/dev/null)" || {
                        echo "Error: Failed to retrieve username from Bitwarden" >&2
                        echo "  Item: ${bw.credentialItem}, Field: ${toString bw.usernameField}" >&2
                        exit 1
                      }
                      export AZURE_DEFAULT_USERNAME

                      AZURE_DEFAULT_PASSWORD="$(${rbwLib.mkRbwGetCommand {
                        item = bw.credentialItem;
                        field = bw.passwordField;
                      }} 2>/dev/null)" || {
                        echo "Error: Failed to retrieve password from Bitwarden" >&2
                        echo "  Item: ${bw.credentialItem}" >&2
                        exit 1
                      }
                      export AZURE_DEFAULT_PASSWORD
                    ''}

                    # --- Resolve the effective role: explicit --role-arn wins over the
                    # profile's role. Export AZURE_DEFAULT_ROLE_ARN only when a role is
                    # known; otherwise the interactive role picker appears after SAML. ---
                    _AAL_EFFECTIVE_ROLE_ARN=""
                    if [[ -n "$_AAL_ROLE_ARN" ]]; then
                      _AAL_EFFECTIVE_ROLE_ARN="$_AAL_ROLE_ARN"
                    elif [[ -n "$_AAL_PROFILE_ROLE_ARN" ]]; then
                      _AAL_EFFECTIVE_ROLE_ARN="$_AAL_PROFILE_ROLE_ARN"
                    fi
                    if [[ -n "$_AAL_EFFECTIVE_ROLE_ARN" ]]; then
                      export AZURE_DEFAULT_ROLE_ARN="$_AAL_EFFECTIVE_ROLE_ARN"
                    fi

                    # Export the profile's session duration when configured (falls back to
                    # the on-disk stub's azure_default_duration_hours otherwise).
                    if [[ -n "$_AAL_PROFILE_DURATION" ]]; then
                      export AZURE_DEFAULT_DURATION_HOURS="$_AAL_PROFILE_DURATION"
                    fi

                    # --- Point at the Nix-managed config (holds every profile's stub) ---
                    export AWS_CONFIG_FILE="$HOME/.aws/config"

                    # --- Isolate each non-default profile's STS creds in its own file ---
                    # aws-azure-login's credential write is a full-file read-modify-write with
                    # no locking, so concurrent auths of DIFFERENT profiles must not share one
                    # file. `default` keeps ~/.aws/credentials for tool compatibility.
                    # If the caller already pinned AWS_SHARED_CREDENTIALS_FILE (e.g. the
                    # credential_process shim, or a Model-1 direnv binding), respect it.
                    if [[ -z "''${AWS_SHARED_CREDENTIALS_FILE:-}" ]]; then
                      if [[ "$_AAL_PROFILE" == "default" ]]; then
                        export AWS_SHARED_CREDENTIALS_FILE="$HOME/.aws/credentials"
                      else
                        mkdir -p "$HOME/.aws/credentials.d"
                        chmod 0700 "$HOME/.aws/credentials.d"
                        export AWS_SHARED_CREDENTIALS_FILE="$HOME/.aws/credentials.d/$_AAL_PROFILE"
                      fi
                    fi

                    # Interactive when no role resolved: enables the role picker after TOTP.
                    if [[ -n "$_AAL_EFFECTIVE_ROLE_ARN" ]]; then
                      export AAL_INTERACTIVE=0
                    else
                      export AAL_INTERACTIVE=1
                    fi

                    ${if hasCredentials && cfg.azureAuth.autoTotp then ''
                      if [[ "$AAL_INTERACTIVE" == 1 ]]; then
                        # Interactive role selection: skip expect so arrow keys work in
                        # the inquirer prompt (expect's interact mangles escape sequences).
                        # User types TOTP manually.
                        exec ${aws-azure-login-patched}/bin/aws-azure-login --no-prompt --no-sandbox \
                          "''${_AAL_PROFILE_ARGS[@]+"''${_AAL_PROFILE_ARGS[@]}"}" "$@"
                      else
                        # Fully non-interactive: expect handles TOTP prompt
                        exec ${expectScript} \
                          ${aws-azure-login-patched}/bin/aws-azure-login --no-prompt --no-sandbox \
                          "''${_AAL_PROFILE_ARGS[@]+"''${_AAL_PROFILE_ARGS[@]}"}" "$@"
                      fi
                    '' else if hasCredentials then ''
                      # Credentials from rbw, user handles TOTP + role selection interactively
                      exec ${aws-azure-login-patched}/bin/aws-azure-login --no-prompt --no-sandbox \
                        "''${_AAL_PROFILE_ARGS[@]+"''${_AAL_PROFILE_ARGS[@]}"}" "$@"
                    '' else ''
                      # Fully interactive: only tenant/app config injected
                      exec ${aws-azure-login-patched}/bin/aws-azure-login --no-sandbox \
                        "''${_AAL_PROFILE_ARGS[@]+"''${_AAL_PROFILE_ARGS[@]}"}" "$@"
                    ''}
        '';

        # ===== credential_process shim (T4, opt-in per profile) =====
        # Optional zero-touch refresh. When a profile sets `credentialProcess =
        # true`, its ~/.aws/config stub gets a `credential_process = <this> <name>`
        # line. The aws CLI (and boto/pulumi) then invoke this shim on demand: it
        # refreshes the profile via the profile-aware aws-azure-login wrapper
        # (headless + autoTotp) ONLY when the cached STS creds are missing or
        # within 5 minutes of expiry, then reads them back from the per-profile
        # credentials file and emits the credential_process JSON
        # ({Version:1, AccessKeyId, SecretAccessKey, SessionToken, Expiration}).
        #
        # Requires autoTotp (login must be non-interactive) AND rbw to be UNLOCKED.
        # A locked vault makes the refresh fail — the triggering `aws` command
        # errors until `rbw unlock`. This is the trade-off for zero-touch refresh,
        # which is why it is opt-in per profile rather than always-on.
        #
        # Test seam: AAL_CP_LOGIN_CMD overrides the login binary (defaults to the
        # profile-aware wrapper) so a dry harness can inject a mock recorder that
        # simulates a login without touching the network.
        aws-azure-login-credential-process = pkgs.writeShellScriptBin "aws-azure-login-credential-process" ''
          set -euo pipefail

          _CP_PROFILE="''${1:?usage: aws-azure-login-credential-process <profile>}"

          # The shim's PRIVATE cache: always ~/.aws/credentials.d/<name>, for EVERY
          # profile including `default`. It must NOT be ~/.aws/credentials — that is
          # the file a bare `aws` reads, and a static [<name>] section there would
          # be picked up by botocore's SharedCredentialProvider (which runs BEFORE
          # the credential_process ProcessProvider and ignores aws_expiration),
          # shadowing this shim and returning expired creds after the session ages.
          mkdir -p "$HOME/.aws/credentials.d"
          chmod 0700 "$HOME/.aws/credentials.d" 2>/dev/null || true
          _CP_CRED_FILE="$HOME/.aws/credentials.d/$_CP_PROFILE"

          # Read one key from the [<profile>] section of the credentials file.
          # Header lines are compared literally (a profile name like "dev" must not
          # be treated as an awk regex); values keep any '=' (base64 tokens).
          _cp_get() {
            [[ -f "$_CP_CRED_FILE" ]] || return 0
            ${pkgs.gawk}/bin/awk -F= -v section="[$_CP_PROFILE]" -v key="$1" '
              /^[ \t]*\[/ {
                line=$0; gsub(/^[ \t]+|[ \t]+$/,"",line);
                in_s = (line == section); next
              }
              in_s {
                k=$1; gsub(/[ \t]/,"",k);
                if (k == key) {
                  val=substr($0, index($0,"=")+1);
                  gsub(/^[ \t]+|[ \t]+$/,"",val);
                  print val; exit;
                }
              }
            ' "$_CP_CRED_FILE"
          }

          # Refresh needed if creds are absent or expiring within 5 minutes.
          _cp_needs_refresh() {
            local exp exp_epoch now
            exp="$(_cp_get aws_expiration)"
            [[ -z "$exp" ]] && return 0
            exp_epoch="$(${pkgs.coreutils}/bin/date -d "$exp" +%s 2>/dev/null)" || return 0
            now="$(${pkgs.coreutils}/bin/date +%s)"
            [[ "$exp_epoch" -le $((now + 300)) ]]
          }

          if _cp_needs_refresh; then
            _CP_LOGIN_CMD="''${AAL_CP_LOGIN_CMD:-${aws-azure-login-wrapper}/bin/aws-azure-login}"
            # Pin the wrapper's output to the shim's private cache file (the wrapper
            # honours a pre-set AWS_SHARED_CREDENTIALS_FILE) so `default` writes to
            # credentials.d/default, NOT ~/.aws/credentials.
            # Login chatter must not pollute stdout — credential_process stdout is
            # JSON ONLY. Redirect the login's stdout to stderr.
            AWS_SHARED_CREDENTIALS_FILE="$_CP_CRED_FILE" "$_CP_LOGIN_CMD" --profile "$_CP_PROFILE" 1>&2
          fi

          _CP_AKID="$(_cp_get aws_access_key_id)"
          _CP_SAK="$(_cp_get aws_secret_access_key)"
          _CP_TOK="$(_cp_get aws_session_token)"
          _CP_EXP="$(_cp_get aws_expiration)"

          if [[ -z "$_CP_AKID" || -z "$_CP_SAK" ]]; then
            echo "aws-azure-login-credential-process: no credentials for profile '$_CP_PROFILE' in $_CP_CRED_FILE after refresh (is rbw unlocked?)" >&2
            exit 1
          fi

          ${pkgs.jq}/bin/jq -n \
            --arg akid "$_CP_AKID" \
            --arg sak "$_CP_SAK" \
            --arg tok "$_CP_TOK" \
            --arg exp "$_CP_EXP" \
            '{Version:1, AccessKeyId:$akid, SecretAccessKey:$sak}
             + (if $tok == "" then {} else {SessionToken:$tok} end)
             + (if $exp == "" then {} else {Expiration:$exp} end)'
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

            profiles = mkOption {
              type = types.attrsOf (types.submodule {
                options = {
                  role = mkOption {
                    type = types.str;
                    description = "knownRoles key or full role ARN for this profile.";
                  };
                  region = mkOption {
                    type = types.nullOr types.str;
                    default = null;
                    description = "AWS region for this profile (falls back to awscli.defaultRegion).";
                  };
                  durationHours = mkOption {
                    type = types.nullOr types.int;
                    default = null;
                    description = "Session duration in hours (falls back to azureAuth.defaultDurationHours).";
                  };
                  credentialProcess = mkOption {
                    type = types.bool;
                    default = false;
                    description = ''
                      Opt this profile into zero-touch refresh: emit a
                      `credential_process = <shim> <name>` line into its
                      ~/.aws/config stub so `aws`/boto/pulumi auto-refresh the
                      profile on demand (headless aws-azure-login + autoTotp),
                      instead of requiring an explicit `aws-azure-login` run.
                      Requires azureAuth.autoTotp = true and rbw to stay UNLOCKED
                      (a locked vault makes the triggering aws command fail until
                      `rbw unlock`). Off by default — set true per profile you want
                      auto-refreshed.
                    '';
                  };
                };
              });
              default = { };
              description = ''
                Named AWS profiles for per-session isolation. Each profile emits a
                NON-SECRET [profile <name>] stub into ~/.aws/config (region +
                duration + benign marker); the `default` key emits the [default]
                section. Role ARNs and secrets are injected via environment at run
                time (never written to disk). Each `role` must be a knownRoles key
                or an arn:* literal (validated at eval via an assertion).
              '';
              example = literalExpression ''
                {
                  default = { role = "dev"; };
                  eks-admin = { role = "eks-admin"; region = "us-west-2"; };
                }
              '';
            };

            direnvHelper = mkOption {
              type = types.bool;
              default = true;
              description = ''
                Install a direnv stdlib function `use_aws_profile <name>` into
                ~/.config/direnv/lib/aws-profile.sh so a project `.envrc` can bind
                an AWS profile per-directory with a single line:
                    use aws_profile eks-admin
                It exports AWS_PROFILE and the matching per-profile
                AWS_SHARED_CREDENTIALS_FILE, mirroring the wrapper's isolation
                scheme (default -> ~/.aws/credentials, else
                ~/.aws/credentials.d/<name>). Set to false to omit the helper and
                write the two `export` lines in `.envrc` manually.
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

                ## Per-session AWS profile isolation (Azure AD SSO)

                Each shell / process / Claude session can authenticate and use a
                DISTINCT AWS profile concurrently without colliding in
                `~/.aws/credentials`. Non-default profiles get their own
                credentials file at `~/.aws/credentials.d/<name>`, so concurrent
                logins never clobber each other.

                Two ways to bind a shell or directory to a profile:

                ### 1. Ad-hoc, per shell
                ```bash
                export AWS_PROFILE=eks-admin      # both aws-azure-login and aws honour it
                aws-azure-login                   # wrapper isolates creds by profile
                aws sts get-caller-identity
                # one-shot form:
                AWS_PROFILE=eks-admin aws-azure-login
                ```

                ### 2. Per-directory, via direnv
                Add a project `.envrc` (needs `direnv allow` once). With the
                `awscli.azureAuth.direnvHelper` (default on) the whole `.envrc` is:
                ```bash
                use aws_profile eks-admin
                ```
                Equivalent explicit form (no helper):
                ```bash
                export AWS_PROFILE=eks-admin
                export AWS_SHARED_CREDENTIALS_FILE="$HOME/.aws/credentials.d/eks-admin"
                ```
                Entering the directory then exports both vars automatically.

                **Concurrency:** shells on the SAME profile share one credentials
                file (fine — same identity). Shells on DIFFERENT profiles are fully
                isolated (separate `~/.aws/credentials.d/<name>` files).

                ### 3. Zero-touch refresh (opt-in per profile)
                Set `credentialProcess = true` on a profile in Nix to auto-refresh
                it on demand — no explicit `aws-azure-login` run:
                ```nix
                profiles.eks-admin = { role = "eks-admin"; credentialProcess = true; };
                ```
                This emits a `credential_process = ...` line into that profile's
                `~/.aws/config` stub, so any `aws`/boto/pulumi call re-authenticates
                headlessly (aws-azure-login + autoTotp) when the cached creds are
                missing or within 5 min of expiry. **Requires `autoTotp = true` and
                rbw to stay UNLOCKED** — a locked vault makes the triggering command
                fail until `rbw unlock`. Off by default; opt in per profile.

                **Bind these profiles with `AWS_PROFILE` ONLY** (e.g.
                `export AWS_PROFILE=eks-admin`, or `use aws_profile eks-admin` — the
                helper knows to skip the shared-file export). Do NOT also set
                `AWS_SHARED_CREDENTIALS_FILE`, and make sure `~/.aws/credentials` has
                NO static `[<name>]` section for the profile: botocore's
                SharedCredentialProvider runs before credential_process and ignores
                `aws_expiration`, so any static section (including the shim's own
                per-profile cache if you point `aws` at it) shadows the auto-refresh
                and returns expired creds. The shim caches under
                `~/.aws/credentials.d/<name>`, which `aws` must NOT read directly.

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
                # Per-session profile stubs (non-secret): [default] / [profile <name>]
                (mkIf cfg.azureAuth.enable profileSettings)
                cfg.extraSettings
              ];
            };
          }

          # Azure AD SSO: aws-azure-login wrapper with Bitwarden injection
          (mkIf cfg.azureAuth.enable {
            home.packages = [ aws-azure-login-wrapper aws-azure-login-credential-process ];

            # Shell completions for --role-arn
            home.file.".local/share/bash-completion/completions/aws-azure-login".text = bashCompletionContent;
            home.file.".local/share/zsh/site-functions/_aws-azure-login".text = zshCompletionContent;

            # direnv stdlib helper: `use aws_profile <name>` in a project .envrc
            # binds that directory to a distinct AWS profile + its isolated
            # credentials file (mirrors the wrapper's scheme). Concurrent SAME
            # profile shells share creds (fine); DIFFERENT profiles are isolated.
            home.file.".config/direnv/lib/aws-profile.sh" = mkIf cfg.azureAuth.direnvHelper {
              text = ''
                # Installed by awscli.azureAuth.direnvHelper — do not edit.
                # Usage in a project .envrc:   use aws_profile <profile-name>
                #
                # Profiles in _AWS_CP_PROFILES use credential_process (zero-touch
                # refresh): for them we export ONLY AWS_PROFILE and UNSET
                # AWS_SHARED_CREDENTIALS_FILE, so `aws` reads the default credentials
                # file (no static section for the profile) and falls through to
                # credential_process. Pinning the per-profile file would let the shim's
                # own cache shadow the process once the creds expire. Non-CP (Model-1)
                # profiles keep the isolated-file export.
                _AWS_CP_PROFILES="${concatStringsSep " " credentialProcessProfiles}"
                use_aws_profile() {
                  local _name="''${1:?usage: use aws_profile <profile-name>}"
                  export AWS_PROFILE="$_name"
                  case " $_AWS_CP_PROFILES " in
                    *" $_name "*)
                      unset AWS_SHARED_CREDENTIALS_FILE ;;
                    *)
                      if [ "$_name" = "default" ]; then
                        export AWS_SHARED_CREDENTIALS_FILE="$HOME/.aws/credentials"
                      else
                        export AWS_SHARED_CREDENTIALS_FILE="$HOME/.aws/credentials.d/$_name"
                      fi ;;
                  esac
                }
              '';
            };

            assertions = [
              {
                assertion = config.secretsManagement.enable or false;
                message = "awscli.azureAuth requires secretsManagement.enable = true (for rbw/Bitwarden)";
              }
              {
                assertion = !cfg.azureAuth.autoTotp || bw.credentialItem != null;
                message = "awscli.azureAuth.autoTotp requires bitwarden.credentialItem to be configured";
              }
              {
                assertion = unknownRoleProfiles == [ ];
                message = "awscli.azureAuth.profiles: each profile's `role` must be an 'arn:...' literal or a key in azureAuth.knownRoles. Unknown role reference in profile(s): ${concatStringsSep ", " unknownRoleProfiles}.";
              }
              {
                assertion = credentialProcessProfiles == [ ] || cfg.azureAuth.autoTotp;
                message = "awscli.azureAuth.profiles.<name>.credentialProcess = true requires azureAuth.autoTotp = true (zero-touch refresh must inject the TOTP non-interactively). Offending profile(s): ${concatStringsSep ", " credentialProcessProfiles}.";
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
