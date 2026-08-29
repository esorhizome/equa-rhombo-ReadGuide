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

## Plays well with overlays

ReadingGuide holds a steady spot in the always-on-top band instead of
fighting other overlay apps for the very top, so it coexists calmly with
screen tinting tools like [ScreenTint](https://github.com/esorhizome), Night
Light, f.lux, and friends — the strip simply gets tinted along with the rest
of the screen.

## License

[CC BY 4.0](LICENSE) — (c) 2026 esorhizome OU. Use it, share it, adapt it;
just credit the source.
