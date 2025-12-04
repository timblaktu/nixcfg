# Windows Terminal Font Management Solution

## Problem Statement

There's a fundamental disconnect between:
1. Font names in Nix packages (e.g., `nerd-fonts.caskaydia-mono`)
2. Font family names Windows recognizes (e.g., `CaskaydiaMono NFM`)
3. What Windows Terminal can actually find and use
4. User expectations for seamless configuration

This leads to errors where fonts are installed but Terminal can't find them, or the configuration references non-existent fonts.

## Current Issues

1. **Name Mismatch**: Nix font package names don't match Windows font family names
2. **Missing Validation**: No pre-flight check if fonts are actually installed in Windows
3. **No Auto-Installation**: Users must manually download and install fonts
4. **Poor Error Messages**: Terminal just says "font not found" without actionable fixes
5. **Emoji Font Confusion**: Noto Color Emoji vs Noto Emoji vs Segoe UI Emoji

## Proposed Solution Architecture

### 1. Unified Font Configuration Schema

```nix
windowsTerminal.fonts = {
  primary = {
    # Nix package name for Linux side
    nixPackage = "nerd-fonts.caskaydia-mono";

    # Exact Windows font family name (from installed font)
    windowsFamilyName = "CaskaydiaMono NFM";

    # Alternative names Terminal might recognize
    alternativeNames = [
      "CaskaydiaMono Nerd Font Mono"
      "CaskaydiaCove Nerd Font Mono"
      "Cascadia Mono"
    ];

    # Download URL for Windows installation
    downloadUrl = "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/CascadiaMono.zip";

    # Files to extract from download
    fontFiles = [
      "CaskaydiaMonoNerdFontMono-Regular.ttf"
      "CaskaydiaMonoNerdFontMono-Bold.ttf"
    ];
  };

  emoji = {
    nixPackage = null;  # Not available in nixpkgs
    windowsFamilyName = "Noto Color Emoji";
    alternativeNames = [
      "Segoe UI Emoji"  # Windows built-in fallback
      "Noto Emoji"
    ];
    downloadUrl = "https://github.com/googlefonts/noto-emoji/raw/main/fonts/NotoColorEmoji.ttf";
    fontFiles = [ "NotoColorEmoji.ttf" ];
  };
};
```

### 2. Font Detection and Validation

```powershell
# PowerShell function to detect installed fonts
function Get-InstalledFont {
    param([string]$FontName)

    Add-Type -AssemblyName System.Drawing
    $fonts = [System.Drawing.Text.InstalledFontCollection]::new()

    # Check exact match first
    $exact = $fonts.Families | Where-Object { $_.Name -eq $FontName }
    if ($exact) { return $exact.Name }

    # Check partial match
    $partial = $fonts.Families | Where-Object { $_.Name -like "*$FontName*" }
    if ($partial) { return $partial[0].Name }

    return $null
}
```

### 3. Dynamic Font Face Builder

```nix
# Build font face string based on what's actually installed
buildFontFace = cfg: let
  checkFont = fontCfg: ''
    FONT=$(powershell.exe -NoProfile -Command "
      Add-Type -AssemblyName System.Drawing
      \$fonts = [System.Drawing.Text.InstalledFontCollection]::new().Families

      # Try primary name
      if (\$fonts | Where-Object { \$_.Name -eq '${fontCfg.windowsFamilyName}' }) {
        Write-Output '${fontCfg.windowsFamilyName}'
        exit
      }

      # Try alternatives
      ${concatMapStringsSep "\n" (alt: ''
        if (\$fonts | Where-Object { \$_.Name -eq '${alt}' }) {
          Write-Output '${alt}'
          exit
        }
      '') fontCfg.alternativeNames}
    " 2>/dev/null | tr -d '\r')
  '';
in ''
  PRIMARY_FONT=$(${checkFont cfg.fonts.primary})
  EMOJI_FONT=$(${checkFont cfg.fonts.emoji})

  if [[ -n "$PRIMARY_FONT" && -n "$EMOJI_FONT" ]]; then
    FONT_FACE="$PRIMARY_FONT, $EMOJI_FONT"
  elif [[ -n "$PRIMARY_FONT" ]]; then
    FONT_FACE="$PRIMARY_FONT"
  else
    FONT_FACE="Cascadia Mono"  # Ultimate fallback
  fi
'';
```

### 4. Automatic Font Installation

```powershell
# PowerShell script to install fonts
function Install-NerdFont {
    param(
        [string]$DownloadUrl,
        [string[]]$FontFiles
    )

    $tempDir = New-TemporaryFile | %{ Remove-Item $_; New-Item -ItemType Directory -Path $_ }
    $zipPath = Join-Path $tempDir "font.zip"

    # Download
    Invoke-WebRequest -Uri $DownloadUrl -OutFile $zipPath

    # Extract
    Expand-Archive -Path $zipPath -DestinationPath $tempDir

    # Install fonts
    $fontsDir = "$env:WINDIR\Fonts"
    $fontReg = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts"

    foreach ($file in $FontFiles) {
        $fontPath = Get-ChildItem -Path $tempDir -Filter $file -Recurse | Select -First 1
        if ($fontPath) {
            # Copy to Fonts directory
            Copy-Item $fontPath.FullName $fontsDir -Force

            # Register in registry (requires admin)
            $fontName = [System.Drawing.Text.PrivateFontCollection]::new()
            $fontName.AddFontFile($fontPath.FullName)
            $regName = $fontName.Families[0].Name + " (TrueType)"
            New-ItemProperty -Path $fontReg -Name $regName -Value $file -Force
        }
    }

    # Clean up
    Remove-Item -Recurse -Force $tempDir

    # Notify font cache update
    Add-Type @"
        using System;
        using System.Runtime.InteropServices;
        public class FontCache {
            [DllImport("gdi32.dll")]
            public static extern int AddFontResource(string lpszFilename);

            [DllImport("user32.dll")]
            public static extern int SendMessage(IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam);

            public static void Refresh() {
                SendMessage(new IntPtr(0xFFFF), 0x001D, IntPtr.Zero, IntPtr.Zero);
            }
        }
"@
    [FontCache]::Refresh()
}
```

### 5. Module Implementation Structure

```
home/modules/
├── windows-terminal.nix          # Main configuration
├── windows-terminal-fonts.nix    # Font management submodule
└── scripts/
    ├── install-terminal-fonts.ps1
    ├── detect-terminal-fonts.ps1
    └── build-font-face.sh
```

## Implementation Phases

### Phase 1: Detection and Validation (Immediate)
- Check what fonts are actually installed
- Build font face from available fonts
- Use fallbacks when preferred fonts unavailable

### Phase 2: Assisted Installation (Short-term)
- Provide PowerShell scripts for font installation
- Clear instructions with exact commands
- Verification after installation

### Phase 3: Automatic Management (Long-term)
- Auto-detect missing fonts
- Prompt for installation during activation
- Handle font updates and changes

## Font Name Mapping Reference

| Nix Package | Windows Family Name | Terminal Display Name | Notes |
|-------------|--------------------|--------------------|--------|
| `nerd-fonts.caskaydia-mono` | `CaskaydiaMono NFM` | CaskaydiaMono Nerd Font Mono | NFM = Nerd Font Mono |
| `nerd-fonts.caskaydia-cove` | `CaskaydiaCove NFP` | CaskaydiaCove Nerd Font Propo | NFP = Nerd Font Proportional |
| Built-in | `Cascadia Mono` | Cascadia Mono | Windows 11 default |
| Built-in | `Cascadia Code` | Cascadia Code | With ligatures |
| Not in Nix | `Noto Color Emoji` | Noto Color Emoji | Google emoji font |
| Built-in | `Segoe UI Emoji` | Segoe UI Emoji | Windows default emoji |

## Known Issues and Workarounds

### Issue: "Unable to find font" despite installation
**Cause**: Windows Terminal font cache not updated
**Fix**:
1. Close all Windows Terminal instances
2. Run: `powershell.exe -Command "Get-Process WindowsTerminal | Stop-Process -Force"`
3. Reopen Terminal

### Issue: Emoji font not rendering
**Cause**: Noto Color Emoji not installed or wrong variant
**Fix**: Use Segoe UI Emoji as fallback (built into Windows)

### Issue: Font looks different than expected
**Cause**: Using wrong variant (NFM vs NF vs NFP)
**Fix**: NFM (Nerd Font Mono) for terminals, NF for regular, NFP for proportional

## Testing Checklist

- [ ] Font detected correctly in Windows
- [ ] Font face string built properly
- [ ] Settings.json updated without corruption
- [ ] Terminal starts without font warnings
- [ ] Emojis render (if emoji font configured)
- [ ] Nerd Font icons display correctly
- [ ] Fallback fonts work when primary unavailable

## Future Enhancements

1. **Font Preview**: Show sample text with configured font
2. **Font Picker**: Interactive selection from installed fonts
3. **Profile-Specific Fonts**: Different fonts per Terminal profile
4. **Font Size Validation**: Ensure readable sizes
5. **Ligature Control**: Enable/disable based on font capabilities
6. **Performance**: Cache font detection results