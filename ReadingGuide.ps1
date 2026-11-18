# =====================================================================
#  ReadingGuide.ps1  (v1.1)  -  an on-screen reading strip for Windows
#  (c) 2026 Sarah Clemencia Gomes (esorhizome) - CC BY 4.0 (creativecommons.org/licenses/by/4.0)
# =====================================================================
#  The digital version of laying a thin cut of paper against the line
#  you are reading, so your eyes never lose their place.
#
#  What this program does, in full:
#    1. Draws one borderless, click-through, always-on-top strip of
#       color over the line you are reading. Two looks:
#         - "Colored strip":  a translucent highlight over the line.
#         - "Clear band":     the reverse - the line stays untouched
#                             and everything above/below is veiled,
#                             like two sheets of paper around it.
#    2. The strip can follow your mouse (gently eased, no jitter) or
#       stay put and move only when you press the up/down hotkeys.
#    3. Shows a tray icon with a settings panel: color presets, a
#       custom color, and sliders for thickness, length, horizontal
#       position, strip opacity, and surround dim.
#    4. Remembers your choices in "settings.json" next to this file.
#    5. Keeps the guide visible: about twice a second a small "guard"
#       checks that no other app's window has slid on top of the strip
#       and that Windows hasn't hidden ("cloaked") it - and quietly
#       fixes either. (This replaces turning "Guide on" off and on.)
#    6. The settings panel can be dark: match Windows, always dark,
#       always light, or light by day / dark by night.
#
#  What it deliberately does NOT do:
#    - It never reads your screen. It only draws over it.
#    - It never touches the network. There is no networking code of
#      any kind in this file.
#    - It never logs keys. The only keyboard code is RegisterHotKey,
#      which asks Windows to deliver your four chosen shortcuts
#      and nothing else.
#    - It needs no administrator rights. Its only registry write is
#      one autostart entry for your own user account, created only if
#      you tick "Start with Windows" (removed when you untick).
#
#  Hotkeys (change them in settings.json, "hotkeys" section):
#      toggle = Ctrl+Shift+F8       strip on/off
#      follow = Ctrl+Shift+F10      follow-the-mouse on/off
#      up     = Ctrl+Shift+F7       move strip up one step
#      down   = Ctrl+Shift+F6      move strip down one step
#  (Pressing up/down while "follow" is on parks the strip where it is
#   and switches to manual moving; press the follow hotkey to resume.)
#  Format: modifiers Ctrl / Alt / Shift / Win joined with "+", then one
#  key: A-Z, 0-9, F1-F24, Home, End, PgUp, PgDn, Up, Down, Left, Right,
#  Space, Tab, Ins, Del, Pause. "none" disables a hotkey. Use the tray
#  menu's "Reload settings.json" after editing.
#
#  Extra knobs in settings.json (no UI, rarely needed):
#      followOffset  px added to the strip's position in follow mode
#                    (negative = strip rides above the pointer)
#      stepPx        how far one up/down hotkey press moves the strip
#      panelFontSize scales the whole settings panel (7-24)
#  (panelTheme / themeLightFrom / themeLightTo are set from the panel.)
#
#  Run it with "Start ReadingGuide.cmd" (same folder), or:
#    powershell -NoProfile -Sta -ExecutionPolicy Bypass -File ReadingGuide.ps1
# =====================================================================

param(
    # Exits by itself after N seconds and logs the startup result to
    # %TEMP%\ReadingGuide.smoke.log. Used only for automated testing;
    # leave at 0 for normal use.
    [int]$TestSeconds = 0
)

Set-StrictMode -Off
$ErrorActionPreference = 'Stop'

# --- Editable defaults -----------------------------------------------
$Presets = @(
    @{ name = 'Pale yellow'; hex = '#F7F3C2' },
    @{ name = 'Periwinkle';  hex = '#AFC0F2' },
    @{ name = 'Violet';      hex = '#8F7BE0' },
    @{ name = 'Soft green';  hex = '#BFE3C0' },
    @{ name = 'Graphite';    hex = '#3A3A44' }
)
$MinThick = 8;   $MaxThick = 240     # strip height, px
$MinOp    = 5;   $MaxOp    = 90      # strip opacity, %
$MinDim   = 10;  $MaxDim   = 85      # surround dim (band look), %
$ThemeChoices = @(
    @{ key = 'system'; label = 'Match Windows' },
    @{ key = 'dark';   label = 'Always dark' },
    @{ key = 'light';  label = 'Always light' },
    @{ key = 'time';   label = 'By time of day' }
)

# --- Session state ---------------------------------------------------
$script:ScriptPath   = $PSCommandPath
$script:SettingsPath = Join-Path (Split-Path -Parent $PSCommandPath) 'settings.json'
$script:PrevIconH    = [IntPtr]::Zero
$script:UiSync       = $false
$script:DialogOpen   = $false
$script:TickN        = 0
$script:Yf           = 0.0           # eased strip position (follow mode)
$script:Scr          = $null         # bounds of the monitor in use
$script:CurY         = 0
$script:PanelDark    = $null         # theme currently painted on the panel
$script:GuardFails   = 0             # consecutive checks that found the guide hidden
$script:LastGuard    = [DateTime]::UtcNow
$script:LastRebuild  = [DateTime]::MinValue
# Windows ReadingGuide never fights for the top spot: ScreenTint's veil
# and panel. (The strip sitting under the tint keeps both apps steady.)
$script:Friends      = [string[]]@('ScreenTint overlay', 'ScreenTint')

# Default settings (used where settings.json is missing or invalid)
$script:S = @{
    enabled       = $true
    look          = 'strip'          # 'strip' or 'band'
    color         = '#F7F3C2'
    opacity       = 35               # strip translucency, %
    dim           = 45               # band look: veil strength, %
    thickness     = 36               # px
    lengthPct     = 100              # % of screen width
    alignPct      = 50               # 0 = left edge, 50 = centered, 100 = right
    followMouse   = $true
    followOffset  = 0                # px; negative rides above the pointer
    stepPx        = 32               # manual move per hotkey press
    y             = 400              # remembered manual position
    autostart     = $false
    panelFontSize = 10.5
    panelTheme    = 'system'         # 'system' | 'dark' | 'light' | 'time'
    themeLightFrom = 7               # 'time': light panel from this hour...
    themeLightTo   = 19              # ...until this hour, dark otherwise
    hotkeys       = @{ toggle = 'Ctrl+Shift+F8'; follow = 'Ctrl+Shift+F10'; up = 'Ctrl+Shift+F7'; down = 'Ctrl+Shift+F6' }
}

# --- .NET / WinForms setup -------------------------------------------
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Native helpers: window styles, topmost, DPI, hotkeys.
# All plain user32 calls - the same ones every desktop app uses.
if (-not ('ReadingGuide.Native' -as [type])) {
Add-Type -ReferencedAssemblies 'System.Windows.Forms','System' -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
namespace ReadingGuide {
  public static class Native {
    [DllImport("user32.dll")] public static extern int  GetWindowLong(IntPtr hWnd, int nIndex);
    [DllImport("user32.dll")] public static extern int  SetWindowLong(IntPtr hWnd, int nIndex, int dwNewLong);
    [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int X, int Y, int cx, int cy, uint uFlags);
    [DllImport("user32.dll")] public static extern bool SetWindowDisplayAffinity(IntPtr hWnd, uint dwAffinity);
    [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr value);
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
    [DllImport("user32.dll")] public static extern bool RegisterHotKey(IntPtr hWnd, int id, uint fsModifiers, uint vk);
    [DllImport("user32.dll")] public static extern bool UnregisterHotKey(IntPtr hWnd, int id);
    [DllImport("user32.dll")] public static extern bool DestroyIcon(IntPtr hIcon);
    [DllImport("user32.dll")] public static extern bool SetLayeredWindowAttributes(IntPtr hWnd, uint crKey, byte bAlpha, uint dwFlags);
    [DllImport("dwmapi.dll")] public static extern int  DwmSetWindowAttribute(IntPtr hWnd, int attr, ref int value, int size);
  }
  // The guard: answers "can the user actually see this overlay right now?"
  // Read-only questions about window order - it never reads pixels.
  public static class Guard {
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
    [DllImport("user32.dll")] static extern IntPtr GetTopWindow(IntPtr hWnd);
    [DllImport("user32.dll")] static extern IntPtr GetWindow(IntPtr hWnd, uint uCmd);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr hWnd);
    [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr hWnd, out RECT r);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern int GetWindowText(IntPtr hWnd, System.Text.StringBuilder s, int max);
    [DllImport("user32.dll")] static extern int GetWindowLong(IntPtr hWnd, int nIndex);
    [DllImport("dwmapi.dll")] static extern int DwmGetWindowAttribute(IntPtr hWnd, int attr, out int value, int size);

    // "Cloaked" = Windows keeps the window but stops drawing it (other
    // virtual desktop, some full-screen app transitions, etc.).
    public static bool IsCloaked(IntPtr h) {
      try { int v; return DwmGetWindowAttribute(h, 14, out v, 4) == 0 && v != 0; } catch { return false; }
    }
    // 0 = fine
    // 1 = another app's window sits on top of it (or it lost always-on-top) -> raise it
    // 2 = hidden or cloaked -> re-show it
    public static int Check(IntPtr me, string[] friends) {
      if (!IsWindowVisible(me) || IsCloaked(me)) return 2;
      if ((GetWindowLong(me, -20) & 0x8) == 0) return 1;      // WS_EX_TOPMOST lost
      RECT m; if (!GetWindowRect(me, out m)) return 0;
      uint myPid; GetWindowThreadProcessId(me, out myPid);
      var sb = new System.Text.StringBuilder(64);
      // Walk down from the very top of the window pile until we reach ourselves.
      IntPtr w = GetTopWindow(IntPtr.Zero);
      for (int n = 0; w != IntPtr.Zero && w != me && n < 5000; n++, w = GetWindow(w, 2)) {
        if (!IsWindowVisible(w) || IsCloaked(w)) continue;
        RECT r; if (!GetWindowRect(w, out r)) continue;
        if (r.Right <= m.Left || r.Left >= m.Right || r.Bottom <= m.Top || r.Top >= m.Bottom) continue;
        uint pid; GetWindowThreadProcessId(w, out pid);
        if (pid == myPid) continue;                            // our own panel / dialogs
        if (friends != null && friends.Length > 0) {
          sb.Length = 0; GetWindowText(w, sb, 64);
          if (Array.IndexOf(friends, sb.ToString()) >= 0) continue;
        }
        return 1;
      }
      return 0;
    }
  }
  // Invisible message window that receives the registered hotkeys.
  public class HotkeyWindow : System.Windows.Forms.NativeWindow, IDisposable {
    public event Action<int> Pressed;
    public HotkeyWindow() { CreateHandle(new System.Windows.Forms.CreateParams()); }
    protected override void WndProc(ref System.Windows.Forms.Message m) {
      if (m.Msg == 0x0312) { var h = Pressed; if (h != null) h((int)m.WParam); }
      base.WndProc(ref m);
    }
    public void Dispose() { DestroyHandle(); }
  }
}
"@
}

# Crisp coordinates on high-DPI / mixed-DPI monitor setups.
try { $null = [ReadingGuide.Native]::SetProcessDpiAwarenessContext([IntPtr](-4)) }
catch { try { $null = [ReadingGuide.Native]::SetProcessDPIAware() } catch {} }

[System.Windows.Forms.Application]::EnableVisualStyles()

# --- Small helpers ---------------------------------------------------
function ColorFromHex([string]$hex) { [System.Drawing.ColorTranslator]::FromHtml($hex) }
function HexFromColor($c) { '#{0:X2}{1:X2}{2:X2}' -f $c.R, $c.G, $c.B }
function Clamp([int]$v, [int]$lo, [int]$hi) { [Math]::Max($lo, [Math]::Min($hi, $v)) }

function Load-Settings {
    if (-not (Test-Path $script:SettingsPath)) { return }
    try {
        $j = Get-Content -Path $script:SettingsPath -Raw | ConvertFrom-Json
        # Copy fields one by one, validating as we go - a corrupt or
        # hand-edited file can never crash the app or inject anything.
        if ($j.enabled -is [bool])     { $script:S.enabled = $j.enabled }
        if ($j.look -in @('strip','band')) { $script:S.look = $j.look }
        if ("$($j.color)" -match '^#[0-9A-Fa-f]{6}$') { $script:S.color = "$($j.color)" }
        if ($null -ne $j.opacity)   { try { $script:S.opacity   = Clamp ([int]$j.opacity)   $MinOp    $MaxOp }    catch {} }
        if ($null -ne $j.dim)       { try { $script:S.dim       = Clamp ([int]$j.dim)       $MinDim   $MaxDim }   catch {} }
        if ($null -ne $j.thickness) { try { $script:S.thickness = Clamp ([int]$j.thickness) $MinThick $MaxThick } catch {} }
        if ($null -ne $j.lengthPct) { try { $script:S.lengthPct = Clamp ([int]$j.lengthPct) 10 100 } catch {} }
        if ($null -ne $j.alignPct)  { try { $script:S.alignPct  = Clamp ([int]$j.alignPct)  0 100 }  catch {} }
        if ($j.followMouse -is [bool]) { $script:S.followMouse = $j.followMouse }
        if ($null -ne $j.followOffset) { try { $script:S.followOffset = Clamp ([int]$j.followOffset) -400 400 } catch {} }
        if ($null -ne $j.stepPx)    { try { $script:S.stepPx = Clamp ([int]$j.stepPx) 4 400 } catch {} }
        if ($null -ne $j.y)         { try { $script:S.y = [int]$j.y } catch {} }
        if ($j.autostart -is [bool]) { $script:S.autostart = $j.autostart }
        try { $f = [double]$j.panelFontSize; if ($f -ge 7 -and $f -le 24) { $script:S.panelFontSize = $f } } catch {}
        if ($j.panelTheme -in @('system','dark','light','time')) { $script:S.panelTheme = "$($j.panelTheme)" }
        if ($null -ne $j.themeLightFrom) { try { $script:S.themeLightFrom = Clamp ([int]$j.themeLightFrom) 0 23 } catch {} }
        if ($null -ne $j.themeLightTo)   { try { $script:S.themeLightTo   = Clamp ([int]$j.themeLightTo)   0 24 } catch {} }
        if ($j.hotkeys) {
            foreach ($hk in @('toggle','follow','up','down')) {
                $v = $j.hotkeys.$hk
                if ($v -is [string] -and $v.Length -le 40) { $script:S.hotkeys[$hk] = $v }
            }
        }
    } catch { }  # unreadable file -> keep defaults
}

function Save-Settings {
    try {
        $script:S | ConvertTo-Json -Depth 5 | Set-Content -Path $script:SettingsPath -Encoding UTF8
    } catch { }  # a failed save must never break the guide itself
}

# --- Hotkeys ---------------------------------------------------------
$script:NamedKeys = @{
    HOME = 0x24; END = 0x23; PGUP = 0x21; PAGEUP = 0x21; PGDN = 0x22; PAGEDOWN = 0x22
    INS = 0x2D; INSERT = 0x2D; DEL = 0x2E; DELETE = 0x2E; UP = 0x26; DOWN = 0x28
    LEFT = 0x25; RIGHT = 0x27; SPACE = 0x20; TAB = 0x09; PAUSE = 0x13; BACKSPACE = 0x08
}

function Parse-Hotkey([string]$spec) {
    # "Ctrl+Shift+F8" -> @{ mods = ..; vk = .. }, or $null if unusable
    if (-not $spec -or $spec.Trim() -match '^(?i)(none|off|0)$') { return $null }
    $mods = 0; $vk = -1
    foreach ($raw in ($spec -split '\+')) {
        $t = $raw.Trim().ToUpperInvariant()
        if     ($t -in @('CTRL','CONTROL'))  { $mods = $mods -bor 0x2 }
        elseif ($t -eq 'ALT')                { $mods = $mods -bor 0x1 }
        elseif ($t -eq 'SHIFT')              { $mods = $mods -bor 0x4 }
        elseif ($t -in @('WIN','WINDOWS'))   { $mods = $mods -bor 0x8 }
        elseif ($t -match '^F([1-9]|1[0-9]|2[0-4])$') { $vk = 0x6F + [int]$Matches[1] }
        elseif ($t -match '^[A-Z0-9]$')      { $vk = [int][char]$t }
        elseif ($script:NamedKeys.ContainsKey($t)) { $vk = $script:NamedKeys[$t] }
        else { return $null }   # unknown token -> treat whole spec as invalid
    }
    if ($vk -lt 0) { return $null }
    @{ mods = $mods; vk = $vk }
}

function Register-Hotkeys {
    if (-not $script:HK) { return }
    foreach ($id in 1..4) { $null = [ReadingGuide.Native]::UnregisterHotKey($script:HK.Handle, $id) }
    $t = Parse-Hotkey $script:S.hotkeys.toggle
    $f = Parse-Hotkey $script:S.hotkeys.follow
    $u = Parse-Hotkey $script:S.hotkeys.up
    $d = Parse-Hotkey $script:S.hotkeys.down
    # 0x4000 = no key-repeat (toggles only; up/down repeat while held)
    if ($t) { $null = [ReadingGuide.Native]::RegisterHotKey($script:HK.Handle, 1, ($t.mods -bor 0x4000), $t.vk) }
    if ($f) { $null = [ReadingGuide.Native]::RegisterHotKey($script:HK.Handle, 2, ($f.mods -bor 0x4000), $f.vk) }
    if ($u) { $null = [ReadingGuide.Native]::RegisterHotKey($script:HK.Handle, 3, $u.mods, $u.vk) }
    if ($d) { $null = [ReadingGuide.Native]::RegisterHotKey($script:HK.Handle, 4, $d.mods, $d.vk) }
}

# --- The overlay windows ---------------------------------------------
# Strip = the colored line. MaskA/MaskB = the veils above and below the
# clear band. All three exist all the time; the look decides which show.
function New-GuideForm {
    $f = New-Object System.Windows.Forms.Form
    $f.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
    $f.StartPosition   = [System.Windows.Forms.FormStartPosition]::Manual
    $f.ShowInTaskbar   = $false
    $f.Text            = 'ReadingGuide overlay'
    $f.BackColor       = [System.Drawing.Color]::Black
    $f.Opacity         = 0.01
    $f.TopMost         = $true
    $f.Bounds          = New-Object System.Drawing.Rectangle 0, 0, 10, 10
    $null = $f.Handle   # create the window handle so we can adjust its style

    # Make it click-through and invisible to Alt+Tab:
    #   0x00080000 layered | 0x20 transparent (clicks pass through)
    #   0x80 toolwindow (no Alt+Tab entry) | 0x08000000 never steals focus
    $ex = [ReadingGuide.Native]::GetWindowLong($f.Handle, -20)
    $null = [ReadingGuide.Native]::SetWindowLong($f.Handle, -20, ($ex -bor 0x00080000 -bor 0x20 -bor 0x80 -bor 0x08000000))

    # Exclude the guide from screenshots & screen sharing (Win10 2004+),
    # so captures of your screen come out clean.
    $null = [ReadingGuide.Native]::SetWindowDisplayAffinity($f.Handle, 0x11)
    return $f
}

function Move-GuideForm($f, [int]$x, [int]$y, [int]$w, [int]$h) {
    if (-not $f -or $f.IsDisposed) { return }
    if ($w -le 0 -or $h -le 0) { $f.Visible = $false; return }
    if (-not $f.Visible) { $f.Visible = $true }
    # The form was created TopMost, so it lives in the always-on-top
    # band. Moving uses NOZORDER (0x4) | NOACTIVATE (0x10): ~33 moves a
    # second must not shuffle the window pile. Staying on top is the
    # guard's job (Guard-Guide), which re-claims the top only when some
    # other app's window has actually slid over the strip - and never
    # against ScreenTint, so the two never leapfrog (that would read as
    # a slow flicker). Under the tint, the strip is simply tinted too.
    $null = [ReadingGuide.Native]::SetWindowPos($f.Handle, [IntPtr]::Zero, $x, $y, $w, $h, 0x14)
}

function Get-CurrentY {
    if ($script:S.followMouse) { [int][Math]::Round($script:Yf) } else { [int]$script:S.y }
}

function Layout-Guide([int]$y) {
    if (-not $script:S.enabled) {
        foreach ($f in @($script:Strip, $script:MaskA, $script:MaskB)) {
            if ($f -and -not $f.IsDisposed) { $f.Visible = $false }
        }
        return
    }
    if (-not $script:Scr) { $script:Scr = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds }
    $b = $script:Scr
    $h = Clamp ([int]$script:S.thickness) $MinThick $MaxThick
    $w = [Math]::Max(40, [int]($b.Width * $script:S.lengthPct / 100))
    $x = $b.X + [int](($b.Width - $w) * $script:S.alignPct / 100)
    $y = Clamp $y $b.Y ($b.Bottom - $h)
    $script:CurY = $y
    if ($script:S.look -eq 'strip') {
        if ($script:MaskA -and -not $script:MaskA.IsDisposed) { $script:MaskA.Visible = $false }
        if ($script:MaskB -and -not $script:MaskB.IsDisposed) { $script:MaskB.Visible = $false }
        Move-GuideForm $script:Strip $x $y $w $h
    } else {
        # Clear band: the veils share the strip's length and alignment,
        # so a shorter guide works over just a column of text.
        if ($script:Strip -and -not $script:Strip.IsDisposed) { $script:Strip.Visible = $false }
        Move-GuideForm $script:MaskA $x $b.Y $w ($y - $b.Y)
        Move-GuideForm $script:MaskB $x ($y + $h) $w ($b.Bottom - $y - $h)
    }
}

function Apply-Look {
    $c = ColorFromHex $script:S.color
    if ($script:Strip -and -not $script:Strip.IsDisposed) {
        $script:Strip.BackColor = $c
        $script:Strip.Opacity   = (Clamp ([int]$script:S.opacity) $MinOp $MaxOp) / 100.0
    }
    foreach ($m in @($script:MaskA, $script:MaskB)) {
        if ($m -and -not $m.IsDisposed) {
            $m.BackColor = $c
            $m.Opacity   = (Clamp ([int]$script:S.dim) $MinDim $MaxDim) / 100.0
        }
    }
}

function Apply-Guide {
    Apply-Look
    Layout-Guide (Get-CurrentY)
    Update-TrayIcon
    Sync-Ui
}

# --- Keeping the guide visible ---------------------------------------
# Windows sometimes lets another app's always-on-top window slide over
# the strip, or "cloaks" (stops drawing) the strip - e.g. around
# full-screen or virtual-desktop changes. The guard spots both and
# repairs them, so you never have to flick "Guide on" off and on.
function Get-GuideForms {
    @($script:Strip, $script:MaskA, $script:MaskB) | Where-Object { $_ -and -not $_.IsDisposed }
}

function Raise-Form($f) {
    # HWND_TOPMOST = -1; NOMOVE|NOSIZE|NOACTIVATE = 0x13
    $null = [ReadingGuide.Native]::SetWindowPos($f.Handle, [IntPtr](-1), 0, 0, 0, 0, 0x13)
}

function Reshow-Form($f) {
    # Exactly what toggling "Guide on" did by hand: hide, show again
    # (without taking focus), re-apply the see-through level, go on top.
    $f.Visible = $false
    $f.Visible = $true
    $a = [byte][Math]::Max(0, [Math]::Min(255, [int]($f.Opacity * 255)))
    $null = [ReadingGuide.Native]::SetLayeredWindowAttributes($f.Handle, 0, $a, 2)   # LWA_ALPHA
    Raise-Form $f
}

function Rebuild-GuideForms {
    # Last resort: brand-new windows, which Windows always draws on the
    # desktop you are looking at right now.
    $old = @(Get-GuideForms)
    $script:Strip = New-GuideForm
    $script:MaskA = New-GuideForm
    $script:MaskB = New-GuideForm
    Apply-Look
    Layout-Guide (Get-CurrentY)
    foreach ($f in $old) { try { $f.Close(); $f.Dispose() } catch {} }
}

function Reshow-Guide {
    # Tray menu "Bring the guide back" - the manual version of the guard.
    foreach ($f in Get-GuideForms) { if ($f.Visible) { Reshow-Form $f } }
}

function Guard-Guide {
    $now = [DateTime]::UtcNow
    # A long gap between checks means the PC slept or was locked;
    # windows can come back from that undrawn, so refresh them once.
    $woke = ($now - $script:LastGuard).TotalSeconds -gt 5
    $script:LastGuard = $now
    if (-not $script:S.enabled) { $script:GuardFails = 0; return }
    $broken = @(); $covered = $false
    foreach ($f in Get-GuideForms) {
        if (-not $f.Visible) { continue }   # hidden on purpose (look / size)
        $code = [ReadingGuide.Guard]::Check($f.Handle, $script:Friends)
        if ($woke -or $code -eq 2) { $broken += $f }
        elseif ($code -eq 1)       { $covered = $true }
    }
    if ($broken.Count -gt 0) {
        $script:GuardFails++
        if ($script:GuardFails -ge 3 -and ($now - $script:LastRebuild).TotalSeconds -gt 10) {
            # Re-showing didn't stick three times running -> fresh windows.
            $script:GuardFails = 0
            $script:LastRebuild = $now
            Rebuild-GuideForms
        } else {
            foreach ($f in $broken) { Reshow-Form $f }
        }
        return
    }
    $script:GuardFails = 0
    if ($covered) {
        foreach ($f in Get-GuideForms) { if ($f.Visible) { Raise-Form $f } }
    }
}

# --- Tray icon -------------------------------------------------------
function Update-TrayIcon {
    if (-not $script:Tray) { return }
    $bmp = New-Object System.Drawing.Bitmap 16, 16
    $g   = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    if ($script:S.enabled) {
        $br = New-Object System.Drawing.SolidBrush (ColorFromHex $script:S.color)
        $g.FillRectangle($br, 1, 6, 14, 5)
        $g.DrawRectangle([System.Drawing.Pens]::DimGray, 1, 6, 13, 4)
        $br.Dispose()
    } else {
        $pen = New-Object System.Drawing.Pen ([System.Drawing.Color]::Gray), 1
        $g.DrawRectangle($pen, 1, 6, 13, 4)
        $pen.Dispose()
    }
    $g.Dispose()
    $h = $bmp.GetHicon()
    $script:Tray.Icon = [System.Drawing.Icon]::FromHandle($h)
    if ($script:PrevIconH -ne [IntPtr]::Zero) { $null = [ReadingGuide.Native]::DestroyIcon($script:PrevIconH) }
    $script:PrevIconH = $h
    $bmp.Dispose()
    $state = if ($script:S.enabled) {
        $fol = if ($script:S.followMouse) { 'following mouse' } else { 'parked' }
        '{0}, {1}px, {2}' -f $script:S.look, $script:S.thickness, $fol
    } else { 'off' }
    $script:Tray.Text = 'ReadingGuide - ' + $state
    if ($script:MenuToggle) { $script:MenuToggle.Checked = [bool]$script:S.enabled }
    if ($script:MenuFollow) { $script:MenuFollow.Checked = [bool]$script:S.followMouse }
}

# --- Actions ---------------------------------------------------------
function Toggle-Guide {
    $script:S.enabled = -not $script:S.enabled
    Save-Settings
    Apply-Guide
}

function Toggle-Follow {
    if ($script:S.followMouse) {
        # Park the strip exactly where it is right now.
        $script:S.followMouse = $false
        $script:S.y = [int][Math]::Round($script:Yf)
    } else {
        $script:S.followMouse = $true
        $script:Yf = [double]$script:S.y
    }
    Save-Settings
    Apply-Guide
}

function Nudge-Y([int]$delta) {
    if ($script:S.followMouse) {
        # First press parks the strip; it then moves only by hotkey.
        $script:S.followMouse = $false
        $script:S.y = [int][Math]::Round($script:Yf)
    }
    $script:S.y = [int]$script:S.y + $delta
    Save-Settings
    Layout-Guide ([int]$script:S.y)
    $script:S.y = $script:CurY   # keep the clamped value
    Update-TrayIcon
    Sync-Ui
}

function Set-GuideColor([string]$hex) {
    $script:S.color = $hex
    Save-Settings
    Apply-Guide
}

function Set-Autostart([bool]$on) {
    # The app's ONLY registry write: one value under your user's Run key.
    $runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
    try {
        if ($on) {
            $cmd = '"{0}\powershell.exe" -NoProfile -Sta -ExecutionPolicy Bypass -WindowStyle Hidden -File "{1}"' -f $PSHOME, $script:ScriptPath
            Set-ItemProperty -Path $runKey -Name 'ReadingGuide' -Value $cmd
        } else {
            Remove-ItemProperty -Path $runKey -Name 'ReadingGuide' -ErrorAction SilentlyContinue
        }
    } catch { }
    $script:S.autostart = $on
    Save-Settings
}

# --- Settings panel --------------------------------------------------
# Built with auto-sizing flow layouts so it fits itself to any DPI,
# Windows text-size setting, or high-contrast theme - nothing clips.
function New-Row {
    $r = New-Object System.Windows.Forms.FlowLayoutPanel
    $r.AutoSize = $true
    $r.AutoSizeMode = [System.Windows.Forms.AutoSizeMode]::GrowAndShrink
    $r.WrapContents = $false
    $r.FlowDirection = [System.Windows.Forms.FlowDirection]::LeftToRight
    $r.Margin = New-Object System.Windows.Forms.Padding 0, 2, 0, 2
    $r
}

function New-AutoLabel([string]$text) {
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $text
    $l.AutoSize = $true
    $l.Margin = New-Object System.Windows.Forms.Padding 3, 7, 3, 3
    $l
}

function New-GuideSlider([int]$min, [int]$max, [int]$small, [int]$large, [double]$fs) {
    $t = New-Object System.Windows.Forms.TrackBar
    $t.Width = [int]($fs * 30)
    $t.Minimum = $min; $t.Maximum = $max
    $t.TickFrequency = $large; $t.SmallChange = $small; $t.LargeChange = $large
    $t
}

# --- Panel theme (light / dark) -------------------------------------
function In-HourSpan([int]$h, [int]$from, [int]$to) {
    # True when hour $h is inside [from, to). Handles spans that cross
    # midnight, e.g. 20 -> 6.
    if ($from -le $to) { ($h -ge $from) -and ($h -lt $to) }
    else               { ($h -ge $from) -or  ($h -lt $to) }
}

function Get-WantDark {
    # High contrast always wins: leave the panel in your chosen system
    # colors so nothing you rely on is overridden.
    if ([System.Windows.Forms.SystemInformation]::HighContrast) { return $false }
    switch ($script:S.panelTheme) {
        'dark'  { return $true }
        'light' { return $false }
        'time'  { return (-not (In-HourSpan (Get-Date).Hour $script:S.themeLightFrom $script:S.themeLightTo)) }
        default {
            # Windows' own "app mode" switch (Settings > Personalization >
            # Colors). Reading it changes nothing.
            try {
                $v = [Microsoft.Win32.Registry]::GetValue(
                    'HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize',
                    'AppsUseLightTheme', $null)
                return ($null -ne $v -and [int]$v -eq 0)
            } catch { return $false }
        }
    }
}

function Set-ControlTheme($c, [bool]$dark, $P) {
    if ($c.Name -eq 'swatch') { return }   # color swatches keep their color
    if ($c -is [System.Windows.Forms.Button]) {
        if ($dark) {
            $c.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
            $c.FlatAppearance.BorderColor = $P.border
            $c.BackColor = $P.button
        } else {
            $c.FlatStyle = [System.Windows.Forms.FlatStyle]::Standard
            $c.BackColor = [System.Drawing.SystemColors]::Control
            $c.UseVisualStyleBackColor = $true
        }
        $c.ForeColor = $P.fore
    } elseif ($c -is [System.Windows.Forms.ComboBox]) {
        $c.FlatStyle = if ($dark) { [System.Windows.Forms.FlatStyle]::Flat } else { [System.Windows.Forms.FlatStyle]::Standard }
        $c.BackColor = $P.input; $c.ForeColor = $P.fore
    } elseif ($c -is [System.Windows.Forms.NumericUpDown]) {
        $c.BorderStyle = if ($dark) { [System.Windows.Forms.BorderStyle]::FixedSingle } else { [System.Windows.Forms.BorderStyle]::Fixed3D }
        $c.BackColor = $P.input; $c.ForeColor = $P.fore
    } elseif ($c -is [System.Windows.Forms.TrackBar]) {
        $c.BackColor = $P.back
    } elseif ($c -is [System.Windows.Forms.Label]) {
        $c.ForeColor = if ($c.Name -eq 'dim') { $P.dim } else { $P.fore }
    } else {
        # panels, check boxes, radio buttons
        $c.BackColor = $P.back; $c.ForeColor = $P.fore
    }
    foreach ($k in $c.Controls) { Set-ControlTheme $k $dark $P }
}

function Apply-PanelTheme([bool]$dark) {
    if (-not $script:SF -or $script:SF.IsDisposed) { return }
    if ($dark) {
        # Same family of greys Windows 11 uses for its own dark windows.
        $P = @{
            back = ColorFromHex '#202020'; fore = ColorFromHex '#F0F0F0'; dim = ColorFromHex '#A8A8A8'
            button = ColorFromHex '#2F2F2F'; border = ColorFromHex '#5C5C5C'; input = ColorFromHex '#2B2B2B'
        }
    } else {
        $sc = [System.Drawing.SystemColors]
        $P = @{
            back = $sc::Control; fore = $sc::ControlText; dim = $sc::GrayText
            button = $sc::Control; border = $sc::ControlDark; input = $sc::Window
        }
    }
    $script:SF.SuspendLayout()
    try {
        $script:SF.BackColor = $P.back
        $script:SF.ForeColor = $P.fore
        foreach ($c in $script:SF.Controls) { Set-ControlTheme $c $dark $P }
    } finally { $script:SF.ResumeLayout() }
    # Dark title bar (Windows 10 20H1+ / 11): attribute 20, or 19 on
    # older builds. FRAMECHANGED makes Windows repaint it right away.
    $v = [int]$dark
    try {
        if ([ReadingGuide.Native]::DwmSetWindowAttribute($script:SF.Handle, 20, [ref]$v, 4) -ne 0) {
            $null = [ReadingGuide.Native]::DwmSetWindowAttribute($script:SF.Handle, 19, [ref]$v, 4)
        }
        $null = [ReadingGuide.Native]::SetWindowPos($script:SF.Handle, [IntPtr]::Zero, 0, 0, 0, 0, 0x37)
    } catch {}
    $script:SF.Invalidate($true)
    $script:PanelDark = $dark
}

function Update-PanelTheme {
    # Cheap: repaints only when the wanted theme actually changed.
    $want = Get-WantDark
    if ($want -ne $script:PanelDark) { Apply-PanelTheme $want }
}

function Build-SettingsForm {
    $fs = [double]$script:S.panelFontSize
    $SF = New-Object System.Windows.Forms.Form
    $SF.Text            = 'ReadingGuide'
    $SF.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedToolWindow
    $SF.StartPosition   = [System.Windows.Forms.FormStartPosition]::CenterScreen
    $SF.AutoSize        = $true
    $SF.AutoSizeMode    = [System.Windows.Forms.AutoSizeMode]::GrowAndShrink
    $SF.TopMost         = $true
    $SF.MaximizeBox     = $false
    $SF.Font            = New-Object System.Drawing.Font 'Segoe UI', ([single]$fs)

    $stack = New-Object System.Windows.Forms.FlowLayoutPanel
    $stack.FlowDirection = [System.Windows.Forms.FlowDirection]::TopDown
    $stack.WrapContents  = $false
    $stack.AutoSize      = $true
    $stack.AutoSizeMode  = [System.Windows.Forms.AutoSizeMode]::GrowAndShrink
    $stack.Padding       = New-Object System.Windows.Forms.Padding 12
    $SF.Controls.Add($stack)

    $tips = New-Object System.Windows.Forms.ToolTip

    # Row: on/off + follow ---------------------------------------------
    $row = New-Row
    $script:ChkOn = New-Object System.Windows.Forms.CheckBox
    $script:ChkOn.Text = 'Guide on'; $script:ChkOn.AutoSize = $true
    $script:ChkOn.add_CheckedChanged({
        if ($script:UiSync) { return }
        $script:S.enabled = $script:ChkOn.Checked
        Save-Settings
        Apply-Guide
    })
    $row.Controls.Add($script:ChkOn)
    $script:ChkFollow = New-Object System.Windows.Forms.CheckBox
    $script:ChkFollow.Text = 'Follow the mouse'; $script:ChkFollow.AutoSize = $true
    $tips.SetToolTip($script:ChkFollow, 'Off = the strip stays put; move it with the up/down hotkeys')
    $script:ChkFollow.add_CheckedChanged({
        if ($script:UiSync) { return }
        Toggle-Follow
    })
    $row.Controls.Add($script:ChkFollow)
    $stack.Controls.Add($row)

    # Row: look --------------------------------------------------------
    $row = New-Row
    $row.Controls.Add((New-AutoLabel 'Look:'))
    $script:RadStrip = New-Object System.Windows.Forms.RadioButton
    $script:RadStrip.Text = 'Colored strip'; $script:RadStrip.AutoSize = $true
    $tips.SetToolTip($script:RadStrip, 'A translucent highlight over the line you are reading')
    $row.Controls.Add($script:RadStrip)
    $script:RadBand = New-Object System.Windows.Forms.RadioButton
    $script:RadBand.Text = 'Clear band'; $script:RadBand.AutoSize = $true
    $tips.SetToolTip($script:RadBand, 'The line stays clear; everything above and below is veiled')
    $row.Controls.Add($script:RadBand)
    $stack.Controls.Add($row)

    $lookHandler = {
        if ($script:UiSync) { return }
        $script:S.look = if ($script:RadBand.Checked) { 'band' } else { 'strip' }
        Save-Settings
        Apply-Guide
    }
    $script:RadStrip.add_CheckedChanged($lookHandler)
    $script:RadBand.add_CheckedChanged($lookHandler)

    # Row: color swatches ----------------------------------------------
    $row = New-Row
    $sw = [int][Math]::Max(34, $fs * 3.6)
    foreach ($pr in $Presets) {
        $b = New-Object System.Windows.Forms.Button
        $b.Size = New-Object System.Drawing.Size $sw, $sw
        $b.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
        $b.FlatAppearance.BorderColor = [System.Drawing.Color]::DimGray
        $b.BackColor = ColorFromHex $pr.hex
        $tips.SetToolTip($b, $pr.name)
        $b.Tag = $pr.hex
        $b.Name = 'swatch'
        $b.add_Click({ param($s, $e) Set-GuideColor ([string]$s.Tag) })
        $row.Controls.Add($b)
    }
    $bCustom = New-Object System.Windows.Forms.Button
    $bCustom.AutoSize = $true; $bCustom.Text = 'More...'
    $tips.SetToolTip($bCustom, 'Pick any color')
    $bCustom.add_Click({
        $dlg = New-Object System.Windows.Forms.ColorDialog
        $dlg.FullOpen = $true
        $dlg.Color = ColorFromHex $script:S.color
        $script:DialogOpen = $true
        try {
            if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
                Set-GuideColor (HexFromColor $dlg.Color)
            }
        } finally {
            $script:DialogOpen = $false
            $dlg.Dispose()
        }
    })
    $row.Controls.Add($bCustom)
    $stack.Controls.Add($row)

    # Rows: thickness slider -------------------------------------------
    $row = New-Row
    $row.Controls.Add((New-AutoLabel 'Thickness'))
    $script:LblThick = New-AutoLabel ''
    $script:LblThick.Name = 'dim'
    $row.Controls.Add($script:LblThick)
    $stack.Controls.Add($row)
    $script:ThickSlider = New-GuideSlider $MinThick $MaxThick 2 10 $fs
    $script:ThickSlider.add_ValueChanged({
        if ($script:UiSync) { return }
        $script:S.thickness = $script:ThickSlider.Value
        Save-Settings
        Apply-Guide
    })
    $stack.Controls.Add($script:ThickSlider)

    # Rows: length slider ----------------------------------------------
    $row = New-Row
    $row.Controls.Add((New-AutoLabel 'Length'))
    $script:LblLen = New-AutoLabel ''
    $script:LblLen.Name = 'dim'
    $row.Controls.Add($script:LblLen)
    $stack.Controls.Add($row)
    $script:LenSlider = New-GuideSlider 10 100 1 10 $fs
    $script:LenSlider.add_ValueChanged({
        if ($script:UiSync) { return }
        $script:S.lengthPct = $script:LenSlider.Value
        Save-Settings
        Apply-Guide
    })
    $stack.Controls.Add($script:LenSlider)

    # Rows: horizontal position slider ---------------------------------
    $row = New-Row
    $row.Controls.Add((New-AutoLabel 'Left <-> right'))
    $script:LblPos = New-AutoLabel ''
    $script:LblPos.Name = 'dim'
    $row.Controls.Add($script:LblPos)
    $stack.Controls.Add($row)
    $script:PosSlider = New-GuideSlider 0 100 1 10 $fs
    $script:PosSlider.add_ValueChanged({
        if ($script:UiSync) { return }
        $script:S.alignPct = $script:PosSlider.Value
        Save-Settings
        Apply-Guide
    })
    $stack.Controls.Add($script:PosSlider)

    # Rows: strip opacity slider ---------------------------------------
    $row = New-Row
    $row.Controls.Add((New-AutoLabel 'Strip opacity'))
    $script:LblOp = New-AutoLabel ''
    $script:LblOp.Name = 'dim'
    $row.Controls.Add($script:LblOp)
    $stack.Controls.Add($row)
    $script:OpSlider = New-GuideSlider $MinOp $MaxOp 1 5 $fs
    $script:OpSlider.add_ValueChanged({
        if ($script:UiSync) { return }
        $script:S.opacity = $script:OpSlider.Value
        Save-Settings
        Apply-Guide
    })
    $stack.Controls.Add($script:OpSlider)

    # Rows: surround dim slider ----------------------------------------
    $row = New-Row
    $row.Controls.Add((New-AutoLabel 'Surround dim (clear band)'))
    $script:LblDim = New-AutoLabel ''
    $script:LblDim.Name = 'dim'
    $row.Controls.Add($script:LblDim)
    $stack.Controls.Add($row)
    $script:DimSlider = New-GuideSlider $MinDim $MaxDim 1 5 $fs
    $script:DimSlider.add_ValueChanged({
        if ($script:UiSync) { return }
        $script:S.dim = $script:DimSlider.Value
        Save-Settings
        Apply-Guide
    })
    $stack.Controls.Add($script:DimSlider)

    # Row: panel theme -------------------------------------------------
    $row = New-Row
    $row.Controls.Add((New-AutoLabel 'Panel theme:'))
    $script:CmbTheme = New-Object System.Windows.Forms.ComboBox
    $script:CmbTheme.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
    $script:CmbTheme.Width = [int]($fs * 13)
    foreach ($t in $ThemeChoices) { $null = $script:CmbTheme.Items.Add($t.label) }
    $tips.SetToolTip($script:CmbTheme, 'Match Windows follows your light/dark app mode; By time of day is light during the hours shown')
    $script:CmbTheme.add_SelectedIndexChanged({
        if ($script:UiSync -or $script:CmbTheme.SelectedIndex -lt 0) { return }
        $script:S.panelTheme = $ThemeChoices[$script:CmbTheme.SelectedIndex].key
        Save-Settings
        Sync-Ui
        Update-PanelTheme
    })
    $row.Controls.Add($script:CmbTheme)
    # Hours, shown only for "By time of day"
    $script:LblThemeFrom = New-AutoLabel 'light from'
    $row.Controls.Add($script:LblThemeFrom)
    $script:NumThemeFrom = New-Object System.Windows.Forms.NumericUpDown
    $script:NumThemeFrom.Width = [int]($fs * 5); $script:NumThemeFrom.Minimum = 0; $script:NumThemeFrom.Maximum = 23
    $script:NumThemeFrom.add_ValueChanged({
        if ($script:UiSync) { return }
        $script:S.themeLightFrom = [int]$script:NumThemeFrom.Value
        Save-Settings
        Update-PanelTheme
    })
    $row.Controls.Add($script:NumThemeFrom)
    $script:LblThemeTo = New-AutoLabel 'to'
    $row.Controls.Add($script:LblThemeTo)
    $script:NumThemeTo = New-Object System.Windows.Forms.NumericUpDown
    $script:NumThemeTo.Width = [int]($fs * 5); $script:NumThemeTo.Minimum = 0; $script:NumThemeTo.Maximum = 24
    $script:NumThemeTo.add_ValueChanged({
        if ($script:UiSync) { return }
        $script:S.themeLightTo = [int]$script:NumThemeTo.Value
        Save-Settings
        Update-PanelTheme
    })
    $row.Controls.Add($script:NumThemeTo)
    $byTime = ($script:S.panelTheme -eq 'time')
    foreach ($c in @($script:LblThemeFrom, $script:NumThemeFrom, $script:LblThemeTo, $script:NumThemeTo)) { $c.Visible = $byTime }
    $stack.Controls.Add($row)

    # Row: autostart ---------------------------------------------------
    $script:ChkAuto = New-Object System.Windows.Forms.CheckBox
    $script:ChkAuto.Text = 'Start with Windows'; $script:ChkAuto.AutoSize = $true
    $script:ChkAuto.add_CheckedChanged({
        if ($script:UiSync) { return }
        Set-Autostart $script:ChkAuto.Checked
    })
    $stack.Controls.Add($script:ChkAuto)

    # Rows: hints ------------------------------------------------------
    $script:LblKeys = New-AutoLabel ''
    $script:LblKeys.Name = 'dim'
    $stack.Controls.Add($script:LblKeys)

    $lblNote = New-AutoLabel 'Panel size, hotkeys, step size: edit settings.json, then tray > Reload.'
    $lblNote.Name = 'dim'
    $stack.Controls.Add($lblNote)

    # Closing the panel hides it; the app lives in the tray.
    $SF.add_FormClosing({
        param($s, $e)
        if ($e.CloseReason -eq [System.Windows.Forms.CloseReason]::UserClosing) {
            $e.Cancel = $true
            $s.Hide()
        }
    })

    return $SF
}

function Sync-Ui {
    if (-not $script:SF -or -not $script:SF.Visible) { return }
    $script:UiSync = $true
    try {
        $script:ChkOn.Checked     = [bool]$script:S.enabled
        $script:ChkFollow.Checked = [bool]$script:S.followMouse
        if ($script:S.look -eq 'band') { $script:RadBand.Checked = $true } else { $script:RadStrip.Checked = $true }
        $script:ThickSlider.Value = Clamp ([int]$script:S.thickness) $MinThick $MaxThick
        $script:LenSlider.Value   = Clamp ([int]$script:S.lengthPct) 10 100
        $script:PosSlider.Value   = Clamp ([int]$script:S.alignPct)  0 100
        $script:OpSlider.Value    = Clamp ([int]$script:S.opacity)   $MinOp  $MaxOp
        $script:DimSlider.Value   = Clamp ([int]$script:S.dim)       $MinDim $MaxDim
        $script:LblThick.Text = '{0} px' -f $script:ThickSlider.Value
        $script:LblLen.Text   = '{0}% of screen width' -f $script:LenSlider.Value
        $script:LblPos.Text   = '{0}%' -f $script:PosSlider.Value
        $script:LblOp.Text    = '{0}%' -f $script:OpSlider.Value
        $script:LblDim.Text   = '{0}%' -f $script:DimSlider.Value
        $script:ChkAuto.Checked = [bool]$script:S.autostart
        $ti = 0
        for ($i = 0; $i -lt $ThemeChoices.Count; $i++) { if ($ThemeChoices[$i].key -eq $script:S.panelTheme) { $ti = $i } }
        $script:CmbTheme.SelectedIndex = $ti
        $script:NumThemeFrom.Value = Clamp ([int]$script:S.themeLightFrom) 0 23
        $script:NumThemeTo.Value   = Clamp ([int]$script:S.themeLightTo)   0 24
        $byTime = ($script:S.panelTheme -eq 'time')
        foreach ($c in @($script:LblThemeFrom, $script:NumThemeFrom, $script:LblThemeTo, $script:NumThemeTo)) { $c.Visible = $byTime }
        $script:LblKeys.Text = ('Hotkeys:  {0} = on/off    {1} = follow    {2} / {3} = move' -f `
            $script:S.hotkeys.toggle, $script:S.hotkeys.follow, $script:S.hotkeys.up, $script:S.hotkeys.down)
    } finally {
        $script:UiSync = $false
    }
}

function Show-Settings {
    Update-PanelTheme           # paint the right theme before it appears
    $script:SF.Show()
    Sync-Ui
    $script:SF.Activate()
}

function Reload-Everything {
    Load-Settings
    Register-Hotkeys
    $script:Yf = [double]$script:S.y
    $wasVisible = $script:SF -and $script:SF.Visible
    try { $script:SF.Dispose() } catch {}
    $script:SF = Build-SettingsForm
    $script:PanelDark = $null   # new panel: theme not painted yet
    Apply-Guide
    if ($wasVisible) { Show-Settings }
}

# --- Shutdown --------------------------------------------------------
function Stop-App {
    try { foreach ($id in 1..4) { $null = [ReadingGuide.Native]::UnregisterHotKey($script:HK.Handle, $id) } } catch {}
    try { $script:HK.Dispose() } catch {}
    try { $script:Timer.Stop() } catch {}
    try { $script:Tray.Visible = $false; $script:Tray.Dispose() } catch {}
    foreach ($f in @($script:Strip, $script:MaskA, $script:MaskB)) { try { $f.Close(); $f.Dispose() } catch {} }
    Save-Settings
    [System.Windows.Forms.Application]::Exit()
}

# =====================================================================
#  Main
# =====================================================================
try {
    # Only one copy at a time.
    $script:Mutex = New-Object System.Threading.Mutex($false, 'Local\ReadingGuideSingleInstance')
    $haveLock = $false
    try { $haveLock = $script:Mutex.WaitOne(0, $false) } catch { $haveLock = $true }
    if (-not $haveLock) {
        if ($TestSeconds -gt 0) {
            Set-Content -Path (Join-Path $env:TEMP 'ReadingGuide.smoke.log') -Value 'ALREADY RUNNING' -Encoding UTF8
        } else {
            $null = [System.Windows.Forms.MessageBox]::Show('ReadingGuide is already running - look for its strip icon in the system tray.', 'ReadingGuide')
        }
        exit
    }

    Load-Settings
    $script:Yf  = [double]$script:S.y
    $script:Scr = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds

    # Tray icon + menu
    $script:Tray = New-Object System.Windows.Forms.NotifyIcon
    $menu = New-Object System.Windows.Forms.ContextMenuStrip
    $miOpen = $menu.Items.Add('Open settings')
    $miOpen.add_Click({ Show-Settings })
    $script:MenuToggle = $menu.Items.Add('Guide on')
    $script:MenuToggle.add_Click({ Toggle-Guide })
    $script:MenuFollow = $menu.Items.Add('Follow the mouse')
    $script:MenuFollow.add_Click({ Toggle-Follow })
    $miReshow = $menu.Items.Add('Bring the guide back')
    $miReshow.add_Click({ Reshow-Guide })
    $miReload = $menu.Items.Add('Reload settings.json')
    $miReload.add_Click({ Reload-Everything })
    $null = $menu.Items.Add('-')
    $miExit = $menu.Items.Add('Exit ReadingGuide')
    $miExit.add_Click({ Stop-App })
    $script:Tray.ContextMenuStrip = $menu
    $script:Tray.add_MouseUp({
        param($s, $e)
        if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left) { Show-Settings }
    })
    $script:Tray.Visible = $true

    # Settings panel (hidden until asked for)
    $script:SF = Build-SettingsForm

    # The guide itself
    $script:Strip = New-GuideForm
    $script:MaskA = New-GuideForm
    $script:MaskB = New-GuideForm
    Apply-Guide

    # Hotkeys (configurable in settings.json)
    $script:HK = New-Object ReadingGuide.HotkeyWindow
    Register-Hotkeys
    $script:HK.add_Pressed([System.Action[int]]{
        param($id)
        switch ($id) {
            1 { Toggle-Guide }
            2 { Toggle-Follow }
            3 { Nudge-Y (-[int]$script:S.stepPx) }
            4 { Nudge-Y ([int]$script:S.stepPx) }
        }
    })

    # Heartbeat: in follow mode, ease the strip toward the pointer
    # (about 33 gentle steps per second - never a hard jump); in
    # parked mode, just refresh the position and clamping once a second.
    $script:Timer = New-Object System.Windows.Forms.Timer
    $script:Timer.Interval = 30
    $script:Timer.add_Tick({
        try {
            $script:TickN++
            # ~every 0.45 s: make sure the guide is really on screen.
            if (($script:TickN % 15) -eq 0) { Guard-Guide }
            # ~every 2 s while the panel is open: follow theme changes
            # (Windows light/dark switch, or the hour ticking over).
            if (($script:TickN % 66) -eq 0 -and $script:SF -and $script:SF.Visible) { Update-PanelTheme }
            if (-not $script:S.enabled) { return }
            if ($script:S.followMouse) {
                $pos  = [System.Windows.Forms.Cursor]::Position
                $scrB = [System.Windows.Forms.Screen]::FromPoint($pos).Bounds
                if ($scrB -ne $script:Scr) { $script:Scr = $scrB }
                $h = Clamp ([int]$script:S.thickness) $MinThick $MaxThick
                $t = [double]($pos.Y) - ($h / 2.0) + [int]$script:S.followOffset
                $t = [Math]::Max([double]$scrB.Y, [Math]::Min([double]($scrB.Bottom - $h), $t))
                $d = $t - $script:Yf
                if ([Math]::Abs($d) -gt 0.4) {
                    # Calm easing: cover 25% of the remaining distance
                    # per tick - quick to arrive, soft on the eyes.
                    $script:Yf += $d * 0.25
                    Layout-Guide ([int][Math]::Round($script:Yf))
                } elseif (($script:TickN % 33) -eq 0) {
                    Layout-Guide ([int][Math]::Round($script:Yf))
                }
            } elseif (($script:TickN % 33) -eq 0) {
                Layout-Guide ([int]$script:S.y)
            }
        } catch { }
    })
    $script:LastGuard = [DateTime]::UtcNow
    $script:Timer.Start()

    # Keep the autostart entry in sync (also heals the path after the
    # folder holding this script is moved or renamed).
    if ($script:S.autostart) { Set-Autostart $true }

    if ($TestSeconds -gt 0) {
        Set-Content -Path (Join-Path $env:TEMP 'ReadingGuide.smoke.log') -Value 'STARTED OK' -Encoding UTF8
        $script:TestTimer = New-Object System.Windows.Forms.Timer
        $script:TestTimer.Interval = $TestSeconds * 1000
        $script:TestTimer.add_Tick({ $script:TestTimer.Stop(); Stop-App })
        $script:TestTimer.Start()
    }

    # Hand control to the Windows message loop until Exit is chosen.
    $ctx = New-Object System.Windows.Forms.ApplicationContext
    [System.Windows.Forms.Application]::Run($ctx)
}
catch {
    $msg = "ReadingGuide hit an unexpected error and will close:`r`n`r`n" + $_.Exception.Message
    if ($TestSeconds -gt 0) {
        try { Set-Content -Path (Join-Path $env:TEMP 'ReadingGuide.smoke.log') -Value ('ERROR: ' + $_.Exception.Message) -Encoding UTF8 } catch {}
    } else {
        try { $null = [System.Windows.Forms.MessageBox]::Show($msg, 'ReadingGuide') } catch { Write-Host $msg }
    }
}
