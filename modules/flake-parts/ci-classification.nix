# modules/flake-parts/ci-classification.nix
# Plan 054 P11: CI is a pure function of this ONE classification attrset.
#
# ci.classification.<checkName> = { tier; backend; systems; requires; enabled?; }
#   tier     : "pr" | "nightly" | "local"   -- WHEN it runs
#   backend  : "eval"|"lint"|"build"|"nspawn"|"qemu"|"tarball" -- HOW it runs
#   systems  : arches the check is meaningful on
#   requires : builder features ("kvm","uid-range") or [ ]
#   enabled  : optional; false => classified but omitted from the CI matrix
#              (still a real check; the drift guard still requires it to exist).
#
# This attrset lives under `dendriticMeta` (NOT `flake.*`) so it is plain config
# data and does not create an unknown flake output (same rationale as
# systems.nix). The machine-readable manifest is derived in `flake.ci.matrix`,
# and the `ci-matrix-sync` drift guard (a perSystem check) keeps this map and the
# live `.#checks` set bidirectionally in sync.
#
# ONE module supplies options + flake.* + perSystem (the shape version.nix uses);
# import-tree auto-loads it (flake.nix imports ./modules/flake-parts), so no
# manual wiring is needed.
{ lib, config, ... }:
let
  # System-set shorthands sourced from the SSOT in systems.nix so an arch rename
  # can never desync classification from the flake's real systems.
  linux = config.dendriticMeta.systems.linux; # [ x86_64-linux aarch64-linux ]
  x86 = [ "x86_64-linux" ];

  classificationType = lib.types.submodule (_: {
    options = {
      tier = lib.mkOption {
        type = lib.types.enum [ "pr" "nightly" "local" ];
        description = "When the check runs: per-PR gate, nightly/dispatch, or local-only (skip CI).";
      };
      backend = lib.mkOption {
        type = lib.types.enum [ "eval" "lint" "build" "nspawn" "qemu" "tarball" ];
        description = "How the check runs / what runner it needs.";
      };
      systems = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        description = "Arches the check is meaningful on.";
      };
      requires = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Builder features required (e.g. kvm, uid-range).";
      };
      enabled = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "If false, classified but omitted from the CI matrix (e.g. build-docling pending plan 054 P10). Still a live check; the drift guard still requires it to exist.";
      };
      rationale = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Human note on why this classification (from plan 054 P5c evidence).";
      };
    };
  });

  # --- backend/tier/systems group builders (DRY) ---
  lintPr = { tier = "pr"; backend = "lint"; systems = x86; requires = [ ]; };
  evalPr = { tier = "pr"; backend = "eval"; systems = x86; requires = [ ]; };
  buildPr = { tier = "pr"; backend = "build"; systems = x86; requires = [ ]; };
  buildNightly = { tier = "nightly"; backend = "build"; systems = x86; requires = [ ]; };
  nspawnPr = { tier = "pr"; backend = "nspawn"; systems = linux; requires = [ "uid-range" ]; };
  qemuPr = { tier = "pr"; backend = "qemu"; systems = x86; requires = [ "kvm" ]; };
  qemuNightly = { tier = "nightly"; backend = "qemu"; systems = x86; requires = [ "kvm" ]; };
  localEval = { tier = "local"; backend = "eval"; systems = x86; requires = [ ]; };
  # Attach the same group to a list of check names.
  grp = attrs: names: lib.genAttrs names (_: attrs);

  classificationData = lib.mkMerge [
    # --- job 'lint' (per-PR, x86 only) ---
    (grp lintPr [
      "lint-formatting"
      "lint-statix"
      "lint-deadnix"
      "lint-ps1-encoding"
      "lint-version"
    ])
    # --- job 'checks' (per-PR, x86 only): pure eval / light runCommand ---
    (grp evalPr [
      "regression-test"
      "eval-hm-modules"
      "eval-nixos-modules"
      "eval-wsl-settings-ssh-port"
      "eval-nixos-dev-team-toplevel"
      "eval-nixos-wsl-minimal-toplevel"
      "eval-thinky-nixos-toplevel"
      "eval-nixos-wsl-dev-team-tarball"
      "eval-thinky-nixos-tarball"
      "eval-images-dev-team"
      "eval-images-ec2"
      "eval-images-graviton"
      "files-module-test"
      "module-base-integration"
      "module-binfmt-integration"
      "tmux-picker-syntax"
      "user-configured"
      "wsl-dev-team-setup-username-user"
      "opencode-json-syntax"
      "opencode-mcp-structure"
      "skill-injection-awscli"
      "skill-injection-glab"
      "skill-injection-negative"
      "skill-injection-pulumi"
    ])
    # --- job 'checks' build-tier (per-PR, x86; HM activation BUILD) ---
    (grp buildPr [ "activate-hm-nixvim-minimal" "activate-hm-thinky-nixos" ])
    # --- job 'vmtest-nspawn' (per-PR, BOTH arches; needs uid-range, NO kvm) ---
    (grp nspawnPr [
      "vm-nspawn-smoke"
      "vm-system-type-default"
      "vm-sops-secrets"
      "vm-hm-activation"
      "vm-shell-env"
      "vm-neovim"
      "vm-tmux"
      "vm-git-advanced"
      "vm-hm-composition-pairs"
      "vm-hm-module-isolation"
      "vm-development-tools"
    ])
    # --- job 'vmtest-qemu' (per-PR, x86 only; needs /dev/kvm) ---
    (grp qemuPr [
      "vm-boot-minimal"
      "vm-system-type-cli"
      "vm-system-type-desktop"
      "vm-ssh-service"
      "vm-user-config"
      "vm-wsl-dev-team-layers"
      "vm-dev-team-vm-smoketest"
    ])
    # --- job 'vmtest-compose-stack' (NIGHTLY, x86, heavy QEMU) ---
    { vm-compose-stack = qemuNightly; }
    # --- job 'pkgs' (NIGHTLY, x86) ---
    (grp buildNightly [
      "build-marker-pdf"
      "build-markitdown"
      "build-nixvim-anywhere"
      "build-termux-claude-scripts"
      "build-tomd"
    ])
    # build-docling: nightly/build but DISABLED pending plan 054 P10
    # (docling-parse won't compile vs nlohmann under GCC14). Still a live check
    # (tests.nix: build-docling = self'.packages.docling), so it must be
    # classified; enabled=false so consumers omit it from the matrix. Re-enabling
    # after P10 is a single flag flip here.
    {
      build-docling = buildNightly // {
        enabled = false;
        rationale = "DISABLED pending plan 054 P10 (docling-parse GCC14/nlohmann). Buildable on demand via workflow_dispatch.";
      };
    }
    # github-actions: act-based local validation runCommand. tier=local =>
    # excluded from every CI job (would be recursive; needs podman). It IS a live
    # check (github-actions.nix root override sets enable=true), so it must be
    # classified; tier=local keeps it out of the CI matrix.
    {
      github-actions = localEval // {
        rationale = "act+podman local GitHub Actions validation; skip-ci (recursive, needs podman).";
      };
    }
    # ci-matrix-sync: the drift guard itself is a live check, so it must be
    # classified too (no guard exception needed). Pure eval gate; per-PR checks.
    {
      ci-matrix-sync = evalPr // {
        rationale = "Self-classified drift guard; pure eval, runs in per-PR checks.";
      };
    }
  ];

  # --- Derived, machine-readable manifest (.#ci.matrix) ---
  # Reads the MERGED option value (the SSOT) so any future extension is seen.
  cls = config.dendriticMeta.ci.classification;
  names = builtins.attrNames cls;

  # One normalized manifest row per check. `name` is folded in so the JSON is a
  # flat list (ideal for GitHub matrix.include fromJSON / GitLab child pipeline).
  rows = map
    (name:
      let c = cls.${name}; in
      { inherit name; inherit (c) tier backend systems requires enabled; })
    names;

  # `enabled == false` and `tier == "local"` rows are dropped from CI views but
  # kept in `all` for transparency/auditing.
  ciRows = builtins.filter (r: r.enabled && r.tier != "local") rows;
  isTier = t: r: r.tier == t;
  byBackend = backend: builtins.filter (r: r.backend == backend);

  matrix = {
    # Full classification (audit view, includes disabled + local).
    all = rows;

    # Per-PR gate, split by the runner class each backend needs. Each list is a
    # ready matrix.include payload: fromJSON(...) in GitHub, or iterate in a
    # GitLab child-pipeline generator.
    pr = {
      lint = byBackend "lint" (builtins.filter (isTier "pr") ciRows);
      eval = byBackend "eval" (builtins.filter (isTier "pr") ciRows);
      build = byBackend "build" (builtins.filter (isTier "pr") ciRows);
      nspawn = byBackend "nspawn" (builtins.filter (isTier "pr") ciRows);
      qemu = byBackend "qemu" (builtins.filter (isTier "pr") ciRows);
    };

    nightly = {
      build = byBackend "build" (builtins.filter (isTier "nightly") ciRows);
      qemu = byBackend "qemu" (builtins.filter (isTier "nightly") ciRows);
    };

    # Flat CI-eligible list (all tiers except local, enabled only).
    ci = ciRows;

    # Schema/version marker so consumers can guard against drift.
    schemaVersion = 1;
  };
in
{
  options.dendriticMeta.ci.classification = lib.mkOption {
    type = lib.types.attrsOf classificationType;
    default = { };
    description = "Single source of truth: per-check CI classification. Consumed by flake.ci.matrix and the ci-matrix-sync drift guard.";
  };

  config = {
    dendriticMeta.ci.classification = classificationData;

    # flake.ci becomes the .#ci flake output; .#ci.matrix is the manifest
    # (arch-agnostic, one eval). Escape-hatch attr like flake.lib in lib.nix.
    flake.ci.matrix = matrix;

    # ci-matrix-sync: bidirectional drift guard (perSystem check). Fails if any
    # LIVE check is unclassified OR any classification key names a nonexistent
    # check. `cls` is the flake-level classification captured lexically from the
    # outer scope (the perSystem `config` arg has no dendriticMeta). Only
    # attrNames of config.checks is read, never forcing sibling derivations, so
    # adding ci-matrix-sync to the set does not recurse.
    perSystem = { config, pkgs, lib, ... }:
      let
        classifiedNames = lib.naturalSort (builtins.attrNames cls);
        liveNames = lib.naturalSort (builtins.attrNames config.checks);
        unclassified = lib.subtractLists classifiedNames liveNames; # live but not classified
        phantom = lib.subtractLists liveNames classifiedNames; # classified but no such check
      in
      {
        checks.ci-matrix-sync = pkgs.runCommand "ci-matrix-sync"
          {
            meta = {
              description = "Drift guard: every live check is classified and every classification names a real check (plan 054 P11).";
              maintainers = [ ];
              timeout = 30;
            };
            unclassified = builtins.concatStringsSep " " unclassified;
            phantom = builtins.concatStringsSep " " phantom;
            liveCount = toString (builtins.length liveNames);
            classifiedCount = toString (builtins.length classifiedNames);
          } ''
          echo "Live checks:        $liveCount"
          echo "Classified entries: $classifiedCount"
          rc=0
          if [ -n "$unclassified" ]; then
            echo "UNCLASSIFIED live checks (add to ci.classification):"
            for c in $unclassified; do echo "   - $c"; done
            rc=1
          fi
          if [ -n "$phantom" ]; then
            echo "PHANTOM classification keys (no such check in .#checks):"
            for c in $phantom; do echo "   - $c"; done
            rc=1
          fi
          if [ "$rc" -ne 0 ]; then
            echo ""
            echo "ci.classification (modules/flake-parts/ci-classification.nix) is out of"
            echo "sync with the live .#checks set. Add/remove classification rows so the"
            echo "two sets are identical, then re-run."
            exit 1
          fi
          echo "ci.classification and .#checks are in perfect sync."
          touch $out
        '';
      };
  };
}
