# OpenCode channel-aware DB migration snippet generator.
#
# OpenCode 1.3.x stores session history in a per-channel SQLite file:
#   - CHANNEL=latest|beta → opencode.db
#   - CHANNEL=stable      → opencode-stable.db   (etc.)
# (See packages/opencode/src/storage/db.ts:31-36 in upstream opencode.)
#
# When the nixpkgs derivation rebuilds with a different OPENCODE_CHANNEL value,
# OC silently writes to a new filename and the user's prior history appears lost.
# This helper emits a wrapper-embedded shell snippet that, on each invocation,
# detects a legacy `opencode.db` with no channel-specific counterpart and
# auto-migrates it (with a timestamped backup first). The legacy file is never
# deleted, so rollback is always available.
#
# Schema-migration footgun: a future OC version with a breaking schema migration
# will run that migration on the copied DB. The timestamped backup in
# $XDG_DATA_HOME/opencode/backups/ is the rollback path. Set
# OPENCODE_NIXCFG_SKIP_MIGRATE=1 to disable the auto-migration entirely.
{ pkgs, lib }:

{
  mkChannelMigrateSnippet = { ocPackage }:
    let
      drvAttrs = ocPackage.drvAttrs or { };
      hasChannel = drvAttrs ? OPENCODE_CHANNEL;
      # Loud assertion: if upstream renames the env attr, we want a noisy
      # eval-time failure rather than a silent fallback that masks regressions.
      _ = lib.assertMsg hasChannel ''
        opencode derivation is missing env.OPENCODE_CHANNEL — upstream may have
        renamed the attribute. Update modules/programs/opencode/_hm/channel-migrate.nix
        to use the new name (or pass an explicit fallback if intentional).
      '';
      channel = drvAttrs.OPENCODE_CHANNEL or "stable";
      # Channels that map to the legacy unsuffixed filename.
      isLegacyChannel = channel == "latest" || channel == "beta";
      channelDbName = if isLegacyChannel then "opencode.db" else "opencode-${channel}.db";
    in
    if isLegacyChannel then ''
      # OpenCode channel "${channel}" already uses the legacy opencode.db filename;
      # no migration needed.
    '' else ''
      # OpenCode channel-aware DB migration (channel: ${channel}).
      # Migrates legacy opencode.db → ${channelDbName} once, with a timestamped
      # backup. Skip with OPENCODE_NIXCFG_SKIP_MIGRATE=1.
      if [ "''${OPENCODE_NIXCFG_SKIP_MIGRATE:-0}" != "1" ]; then
        _OC_DATA="''${XDG_DATA_HOME:-$HOME/.local/share}/opencode"
        _OC_LEGACY="$_OC_DATA/opencode.db"
        _OC_CHANNEL_DB="$_OC_DATA/${channelDbName}"
        if [ -f "$_OC_LEGACY" ] && [ ! -f "$_OC_CHANNEL_DB" ]; then
          _OC_BACKUP_DIR="$_OC_DATA/backups"
          mkdir -p "$_OC_BACKUP_DIR" 2>/dev/null || true
          _OC_TS="$(date +%Y%m%d-%H%M%S)"
          _OC_BACKUP="$_OC_BACKUP_DIR/opencode.db.pre-${channel}.$_OC_TS"
          if cp "$_OC_LEGACY" "$_OC_BACKUP" 2>/dev/null \
             && cp "$_OC_LEGACY" "$_OC_CHANNEL_DB" 2>/dev/null; then
            [ -f "$_OC_LEGACY-wal" ] && cp "$_OC_LEGACY-wal" "$_OC_CHANNEL_DB-wal" 2>/dev/null || true
            [ -f "$_OC_LEGACY-shm" ] && cp "$_OC_LEGACY-shm" "$_OC_CHANNEL_DB-shm" 2>/dev/null || true
            echo "[opencode-wrapper] migrated session history → ${channelDbName} (backup: $_OC_BACKUP)" >&2
          else
            echo "[opencode-wrapper] WARNING: failed to migrate $_OC_LEGACY → $_OC_CHANNEL_DB" >&2
          fi
          unset _OC_BACKUP_DIR _OC_TS _OC_BACKUP
        fi
        unset _OC_DATA _OC_LEGACY _OC_CHANNEL_DB
      fi
    '';
}
