# Windows Terminal Stale Profile Debug Notes

**Created**: 2026-02-14
**Resolved**: 2026-02-15
**Status**: RESOLVED
**Machine**: thinky (Win11 laptop hosting WSL guests)
**Branch**: `refactor/dendritic-pattern`

## Root Cause

WSL's `wsl --import` has known bugs (microsoft/WSL#13064, #13129, #13339) where it
fails to create the fragment file that Windows Terminal needs to discover WSL profiles.
The fragment file should be created at:

```
%LOCALAPPDATA%\Microsoft\Windows Terminal\Fragments\Microsoft.WSL\{guid}.json
```

Without this file, Terminal shows a ghost "Profile no longer detected" entry from the
previous registration and cannot discover the newly imported distro.

The existing `Remove-StaleTerminalProfiles` also had a bug: it only matched
`source == "Windows.Terminal.Wsl"` (line 142 of the old code) but modern WSL profiles
use `source == "Microsoft.WSL"`, so name-based cleanup never matched.

## Solution

`Import-NixOSWSL.ps1` now handles fragment creation and comprehensive cleanup:

1. **Deterministic profile GUID**: Uses RFC 4122 UUIDv5 with a fixed namespace to
   generate a stable GUID from the distro name. Same distro name always produces the
   same GUID, so Terminal user customizations survive reimports.

2. **Enhanced cleanup** (`Remove-StaleTerminalArtifacts`):
   - Iterates ALL Terminal installations (Stable, Preview, Unpackaged)
   - Matches both `Windows.Terminal.Wsl` and `Microsoft.WSL` sources
   - Cleans `settings.json` profiles (by Lxss GUID, profile GUID, name, commandline)
   - Cleans `state.json` generatedProfiles array
   - Removes stale fragment files (by filename and content scan)

3. **Fragment creation** (`New-TerminalFragment`):
   - Reads `/etc/wsl-terminal-profile.json` from inside the distro for display name,
     font, and color scheme
   - Locates icon at `%LOCALAPPDATA%\wsl\<name>\shortcut.ico`
   - Writes fragment JSON to the standard Terminal fragments directory

## Verification

After running the updated import script:
1. Fragment file exists at `Fragments\Microsoft.WSL\{profile-guid}.json`
2. Close and reopen Windows Terminal
3. Profile appears in tab dropdown with correct name, icon, and font
4. No ghost "Profile no longer detected" entry

## Related Files

- `docs/tools/Import-NixOSWSL.ps1` — Import script with fragment creation
- `modules/system/settings/wsl-enterprise/wsl-enterprise.nix` — Terminal profile options + tarball builder override
- `modules/system/settings/wsl-tiger-team/wsl-tiger-team.nix` — Team-specific terminal overrides
- `docs/WSL-CONFIGURATION-GUIDE.md` — User-facing documentation

## References

- [microsoft/WSL#13064](https://github.com/microsoft/WSL/issues/13064) — Fragment not created on import
- [microsoft/WSL#13129](https://github.com/microsoft/WSL/issues/13129) — Related fragment bug
- [microsoft/WSL#13339](https://github.com/microsoft/WSL/issues/13339) — Related fragment bug
- [Windows Terminal fragments](https://learn.microsoft.com/en-us/windows/terminal/json-fragment-extensions)
- [WSL distro packaging docs](https://learn.microsoft.com/en-us/windows/wsl/build-custom-distro)
