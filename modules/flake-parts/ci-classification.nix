# modules/flake-parts/ci-classification.nix
# CI is a pure function of one classification attrset.
#
# ci.classification.<checkName> = { tier; backend; systems; requires; enabled?; }
#   tier     : "pr" | "nightly" | "local"   -- WHEN it runs
#   backend  : "eval"|"lint"|"build"|"nspawn"|"qemu"|"tarball" -- HOW it runs
#   systems  : arches the check is meaningful on
#   requires : builder features ("kvm","uid-range") or [ ]
#   enabled  : optional (default true); false => classified but omitted from the
#              CI matrix. Still a real check; the drift guard still requires it.
#
# The reusable mechanism (mkMatrix + mkDriftGuard) is exported as flake.lib.ci so
# a DOWNSTREAM consumer flake (which already imports this one) can apply the same
# classify-and-generate pattern to ITS OWN checks. This flake dogfoods it: the
# classification data below is nixcfg's own, and flake.ci.matrix / ci-matrix-sync
# are produced by the very functions it exports.
{ lib, config, ... }:
let
  # ===========================================================================
  # Reusable mechanism (exported as flake.lib.ci; pure functions of their args)
  # ===========================================================================

  # mkMatrix : classification-attrset -> machine-readable manifest.
  # Tolerant of plain attrsets (defaults enabled=true, requires=[]) so a
  # downstream caller need not route its data through the option type.
  mkMatrix = classification:
    let
      names = builtins.attrNames classification;
      rows = map
        (name:
          let c = classification.${name}; in
          {
            inherit name;
            inherit (c) tier backend systems;
            requires = c.requires or [ ];
            enabled = c.enabled or true;
          })
        names;
      ciRows = builtins.filter (r: r.enabled && r.tier != "local") rows;
      isTier = t: builtins.filter (r: r.tier == t);
      byBackend = b: builtins.filter (r: r.backend == b);
    in
    {
      # Audit view: every classified row, including local + disabled.
      all = rows;
      # CI-eligible rows (enabled, non-local), grouped by tier then backend so
      # each list is a ready-to-realize job payload.
      pr = {
        lint = byBackend "lint" (isTier "pr" ciRows);
        eval = byBackend "eval" (isTier "pr" ciRows);
        build = byBackend "build" (isTier "pr" ciRows);
        nspawn = byBackend "nspawn" (isTier "pr" ciRows);
        qemu = byBackend "qemu" (isTier "pr" ciRows);
      };
      nightly = {
        build = byBackend "build" (isTier "nightly" ciRows);
        qemu = byBackend "qemu" (isTier "nightly" ciRows);
      };
      # Flat CI-eligible list for consumers that partition themselves.
      ci = ciRows;
      schemaVersion = 1;
    };

  # mkDriftGuard : { pkgs, classification, liveCheckNames } -> a check derivation
  # that fails if any live check is unclassified OR any classification names a
  # nonexistent check. `liveCheckNames` is passed in (builtins.attrNames of the
  # caller's own checks set) so this function stays a pure, repo-agnostic helper.
  mkDriftGuard = { pkgs, classification, liveCheckNames }:
    let
      classifiedNames = lib.naturalSort (builtins.attrNames classification);
      liveNames = lib.naturalSort liveCheckNames;
      unclassified = lib.subtractLists classifiedNames liveNames; # live but not classified
      phantom = lib.subtractLists liveNames classifiedNames; # classified but no such check
    in
    pkgs.runCommand "ci-matrix-sync"
      {
        meta = {
          description = "Drift guard: every live check is classified and every classification names a real check.";
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
        echo "PHANTOM classification keys (no such check):"
        for c in $phantom; do echo "   - $c"; done
        rc=1
      fi
      if [ "$rc" -ne 0 ]; then
        echo ""
        echo "The classification map is out of sync with the live checks set."
        echo "Add/remove classification rows so the two sets are identical."
        exit 1
      fi
      echo "Classification and checks are in perfect sync."
      touch $out
    '';

  # ===========================================================================
  # This flake's own classification data (nixcfg's checks)
  # ===========================================================================

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
        description = "If false, classified but omitted from the CI matrix. Still a live check the drift guard requires.";
      };
      rationale = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Human note on why this classification.";
      };
    };
  });

  # backend/tier/systems group builders (DRY)
  lintPr = { tier = "pr"; backend = "lint"; systems = x86; requires = [ ]; };
  evalPr = { tier = "pr"; backend = "eval"; systems = x86; requires = [ ]; };
  buildPr = { tier = "pr"; backend = "build"; systems = x86; requires = [ ]; };
  buildNightly = { tier = "nightly"; backend = "build"; systems = x86; requires = [ ]; };
  nspawnPr = { tier = "pr"; backend = "nspawn"; systems = linux; requires = [ "uid-range" ]; };
  qemuPr = { tier = "pr"; backend = "qemu"; systems = x86; requires = [ "kvm" ]; };
  qemuNightly = { tier = "nightly"; backend = "qemu"; systems = x86; requires = [ "kvm" ]; };
  localEval = { tier = "local"; backend = "eval"; systems = x86; requires = [ ]; };
  grp = attrs: names: lib.genAttrs names (_: attrs);

  classificationData = lib.mkMerge [
    (grp lintPr [
      "lint-formatting"
      "lint-statix"
      "lint-deadnix"
      "lint-ps1-encoding"
      "lint-version"
    ])
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
    (grp buildPr [ "activate-hm-nixvim-minimal" "activate-hm-thinky-nixos" ])
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
      "vm-monitoring"
    ])
    (grp qemuPr [
      "vm-boot-minimal"
      "vm-system-type-cli"
      "vm-system-type-desktop"
      "vm-ssh-service"
      "vm-user-config"
      "vm-wsl-dev-team-layers"
      "vm-dev-team-vm-smoketest"
    ])
    { vm-compose-stack = qemuNightly; }
    (grp buildNightly [
      "build-marker-pdf"
      "build-markitdown"
      "build-nixvim-anywhere"
      "build-termux-claude-scripts"
      "build-tomd"
    ])
    {
      build-docling = buildNightly // {
        enabled = false;
        rationale = "Disabled pending an upstream compiler-compat fix; buildable on demand.";
      };
    }
    {
      github-actions = localEval // {
        rationale = "Local-only validation harness; never scheduled by CI.";
      };
    }
    {
      ci-matrix-sync = evalPr // {
        rationale = "Self-classified drift guard; pure eval, runs on every change.";
      };
    }
  ];

  # The nightly image-tarball builds are NOT checks: they build a config's
  # tarball builder and run it. Keyed by config name, exposed in a sibling
  # manifest so the drift guard (which reconciles the checks set) ignores them.
  tarballs = [
    { config = "nixos-wsl-dev-team"; artifact = "nixcfg-wsl-dev-team"; systems = x86; requires = [ "kvm" ]; }
    { config = "thinky-nixos"; artifact = "nixcfg-thinky-nixos"; systems = x86; requires = [ "kvm" ]; }
  ];

  # The flake-level (merged) classification, captured here so the perSystem drift
  # guard can close over it without shadowing its own `config` arg. Reading the
  # option we also define is safe (the definition does not depend on the read),
  # exactly as flake.ci.matrix does below.
  ownClassification = config.dendriticMeta.ci.classification;
in
{
  options.dendriticMeta.ci.classification = lib.mkOption {
    type = lib.types.attrsOf classificationType;
    default = { };
    description = "Single source of truth: per-check CI classification. Consumed by flake.ci.matrix and the drift guard.";
  };

  config = {
    dendriticMeta.ci.classification = classificationData;

    # flake.ci is this module's own output (single owner, no cross-module merge):
    #   .ci.lib      -- reusable mechanism a downstream consumer imports
    #                   (inputs.<this>.ci.lib.{mkMatrix,mkDriftGuard})
    #   .ci.matrix   -- this flake's own derived manifest (arch-agnostic, one eval)
    #   .ci.tarballs -- this flake's image-tarball builds (config-keyed)
    flake.ci.lib = { inherit mkMatrix mkDriftGuard; };
    flake.ci.matrix = mkMatrix config.dendriticMeta.ci.classification;
    flake.ci.tarballs = tarballs;

    # The drift guard as a per-system check. The classification is the outer
    # (flake-level) merged option, captured lexically; the perSystem `config` arg
    # (renamed psArgs here to avoid shadowing it) has no dendriticMeta. Only
    # attrNames of the checks set is read (never forcing sibling derivations), so
    # adding this check does not recurse.
    perSystem = { config, pkgs, ... }: {
      checks.ci-matrix-sync = mkDriftGuard {
        inherit pkgs;
        classification = ownClassification;
        liveCheckNames = builtins.attrNames config.checks;
      };
    };
  };
}
