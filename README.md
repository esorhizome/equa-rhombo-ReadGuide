# ReadingGuide

The digital version of laying a thin cut of paper against the line you are
reading, so your eyes never lose their place.

A single-file PowerShell tray app for Windows. No install, no dependencies,
no admin rights — just a borderless, click-through, always-on-top strip of
color that marks the line you are reading.

Made with dyslexic readers in mind, and pleasant for anyone who reads long
things on a screen.

## What it does

- **Two looks**
  - *Colored strip* — a translucent highlight lying over the current line.
  - *Clear band* — the reverse: the line stays untouched and everything
    above and below it is gently veiled, like two sheets of paper around it.
- **Follows your mouse** with soft easing (no jitter, no hard jumps), or
  parks in place and moves line by line with hotkeys.
- **Everything is adjustable** from the tray icon's settings panel:
  color presets + custom color, thickness (8–240 px), length (10–100% of
  screen width), horizontal placement, strip opacity, and surround dim.
- **Stays out of your way**: clicks pass straight through it, it never
  steals focus, it doesn't appear in Alt+Tab, and it is excluded from
  screenshots and screen sharing.
- **Stays visible on its own.** About twice a second a small guard checks
  that the strip is really on screen — that no other app's window has slid
  over it, and that Windows hasn't quietly stopped drawing it — and fixes
  either. No more turning *Guide on* off and on again.
- **Light or dark settings panel** — your choice (see below).
- Remembers your choices in `settings.json` next to the script.

## What it deliberately does NOT do

- It never reads your screen. It only draws over it.
- It never touches the network. There is no networking code in the file —
  verify with Ctrl+F.
- It never logs keys. The only keyboard code is `RegisterHotKey`, which
  asks Windows to deliver your four chosen shortcuts and nothing else.
- It needs no administrator rights. Its only registry write is one
  autostart entry for your own user account, created only if you tick
  "Start with Windows" (removed when you untick).

## Running it

Double-click `Start ReadingGuide.cmd`, or:

```
powershell -NoProfile -Sta -ExecutionPolicy Bypass -File ReadingGuide.ps1
```

A strip-shaped icon appears in the system tray. Left-click it for the
settings panel; right-click for the menu.

## Hotkeys

| Shortcut         | Action                        |
| ---------------- | ----------------------------- |
| `Ctrl+Shift+F8`  | strip on/off                  |
| `Ctrl+Shift+F10` | follow-the-mouse on/off       |
| `Ctrl+Shift+F7`  | move the strip up one step    |
| `Ctrl+Shift+F6`  | move the strip down one step  |

Pressing up/down while "follow" is on parks the strip where it is and
switches to manual moving; press the follow hotkey to resume.

All four are rebindable in `settings.json` (`hotkeys` section), along with
a few extra knobs — step size, follow offset, panel font size. Use the tray
menu's *Reload settings.json* after editing. The full format is documented
in the header of `ReadingGuide.ps1`.

## Panel theme

The *Panel theme* menu in the settings panel works like a navigation app's
day/night setting:

| Choice           | What the panel does                                        |
| ---------------- | ---------------------------------------------------------- |
| Match Windows    | follows Windows' light/dark app mode (the default)         |
| Always dark      | dark, whatever Windows is set to                           |
| Always light     | light, whatever Windows is set to                          |
| By time of day   | light between the two hours you pick, dark the rest of the time |

It changes live (within a couple of seconds) while the panel is open. With a
Windows high-contrast theme on, the panel always uses your high-contrast
colors instead.

## Staying on screen

Windows keeps one pile of "always on top" windows, and the last one to claim
the top sits highest — so another app can occasionally slide over the strip,
and around full-screen or virtual-desktop changes Windows may stop drawing it
("cloaking"). ReadingGuide's guard watches for both about twice a second:

1. another app's window covering the strip → it re-claims the top;
2. the strip hidden or cloaked → it re-shows it (the automatic version of
   toggling *Guide on*);
3. still hidden after three tries → it rebuilds the strip as brand-new
   windows, which Windows always draws on the desktop you are looking at;
4. after sleep or lock → it refreshes the strip once.

If you ever still lose it, tray → **Bring the guide back** does step 2 on
demand.

## Plays well with overlays

The guard never fights [ScreenTint](https://github.com/esorhizome/ScreenTint)
for the top spot, so the two settle into one steady order (strip under the
tint — it simply gets tinted along with the rest of the screen) instead of
leapfrogging, which would look like a flicker.

## License

[CC BY 4.0](LICENSE) — (c) 2026 esorhizome OU. Use it, share it, adapt it;
just credit the source.
