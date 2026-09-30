<#
.SYNOPSIS
  Find a Microsoft Edge tab by title substring across ALL Edge windows, select it,
  and bring its window to the foreground. Optionally open a URL first if no tab
  matches, or force a dedicated new window.

.NOTES
  Every Edge window shares ONE msedge PID, so AppActivate-by-PID / MainWindowHandle
  cannot target a specific window. This drives the exact window HWND via UI Automation
  (find TabItem by Name -> SelectionItemPattern.Select) then foregrounds it with the
  AttachThreadInput + SetForegroundWindow unlock dance (minimize/restore fallback).

.USAGE
  powershell -NoProfile -ExecutionPolicy Bypass -File Focus-EdgeTab.ps1 \
      -Match "<substr>" [-Url "<url>"] [-NewWindow] [-List]
#>
param(
  [string]$Match,
  [string]$Url,
  [switch]$List,
  [switch]$NewWindow
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes

Add-Type @"
using System;
using System.Runtime.InteropServices;
public class W32 {
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c);
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
  [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr h);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, IntPtr pid);
  [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint a, uint b, bool f);
  [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
}
"@

$AE  = [System.Windows.Automation.AutomationElement]
$TS  = [System.Windows.Automation.TreeScope]
$CT  = [System.Windows.Automation.ControlType]
$SIP = [System.Windows.Automation.SelectionItemPattern]

function Get-EdgeWindows {
  $root = $AE::RootElement
  $cond = New-Object System.Windows.Automation.PropertyCondition($AE::ClassNameProperty, 'Chrome_WidgetWin_1')
  $out = @()
  foreach ($w in $root.FindAll($TS::Children, $cond)) {
    $p = Get-Process -Id $w.Current.ProcessId -ErrorAction SilentlyContinue
    if ($p -and $p.ProcessName -eq 'msedge') { $out += $w }
  }
  return $out
}

$tabCond = New-Object System.Windows.Automation.PropertyCondition($AE::ControlTypeProperty, $CT::TabItem)

if ($List) {
  $wi = 0
  foreach ($w in Get-EdgeWindows) {
    $wi++
    Write-Output ("WINDOW #$wi hwnd=" + $w.Current.NativeWindowHandle)
    foreach ($t in $w.FindAll($TS::Descendants, $tabCond)) {
      Write-Output ("   [" + $t.Current.Name + "]")
    }
  }
  exit 0
}

function Find-Tab([string]$m) {
  foreach ($w in Get-EdgeWindows) {
    foreach ($t in $w.FindAll($TS::Descendants, $tabCond)) {
      if ($t.Current.Name -like "*$m*") { return [pscustomobject]@{ Tab = $t; Win = $w } }
    }
  }
  return $null
}

if (-not $Match) { Write-Output "ERR: -Match required"; exit 3 }

$hit = $null
if ($NewWindow) {
  # Always open a fresh standalone window (do not reuse an existing tab).
  if (-not $Url) { Write-Output "ERR: -NewWindow needs -Url"; exit 3 }
  Write-Output "opening dedicated window..."
  Start-Process 'msedge' -ArgumentList '--new-window', $Url | Out-Null
  for ($i=0; $i -lt 15 -and -not $hit; $i++) { Start-Sleep -Milliseconds 800; $hit = Find-Tab $Match }
}
else {
  $hit = Find-Tab $Match
  if (-not $hit -and $Url) {
    Write-Output "no tab matched; opening url..."
    Start-Process 'msedge' -ArgumentList $Url | Out-Null
    for ($i=0; $i -lt 15 -and -not $hit; $i++) { Start-Sleep -Milliseconds 800; $hit = Find-Tab $Match }
  }
}

if (-not $hit) { Write-Output "NOTFOUND: $Match"; exit 2 }

# 1) Select the tab within its window.
try { $hit.Tab.GetCurrentPattern($SIP::Pattern).Select() } catch { Write-Output ("select warn: " + $_.Exception.Message) }

# 2) Foreground the owning window by HWND.
$h = [IntPtr]$hit.Win.Current.NativeWindowHandle
if ($h -ne [IntPtr]::Zero) {
  if ([W32]::IsIconic($h)) { [W32]::ShowWindow($h, 9) | Out-Null }  # SW_RESTORE
  else { [W32]::ShowWindow($h, 5) | Out-Null }                      # SW_SHOW
  $fg = [W32]::GetForegroundWindow()
  $fgThread = [W32]::GetWindowThreadProcessId($fg, [IntPtr]::Zero)
  $me = [W32]::GetCurrentThreadId()
  [W32]::AttachThreadInput($me, $fgThread, $true) | Out-Null
  [W32]::BringWindowToTop($h) | Out-Null
  [W32]::SetForegroundWindow($h) | Out-Null
  [W32]::AttachThreadInput($me, $fgThread, $false) | Out-Null
  if ([W32]::GetForegroundWindow() -ne $h) {
    [W32]::ShowWindow($h, 6) | Out-Null   # SW_MINIMIZE
    [W32]::ShowWindow($h, 9) | Out-Null   # SW_RESTORE (forces activation)
  }
}

$nowFg = [W32]::GetForegroundWindow()
Write-Output ("FOCUSED tab=[" + $hit.Tab.Current.Name + "] hwnd=" + $hit.Win.Current.NativeWindowHandle + " fgMatch=" + ($nowFg -eq $h))
exit 0
