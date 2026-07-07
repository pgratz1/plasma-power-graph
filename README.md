# Power Graph

A KDE Plasma 6 panel widget that displays a live scrolling graph of battery
power consumption in watts, with the current draw overlaid as text.

Clicking the widget opens a resizable history window with a horizontally
scrollable graph (watt gridlines, time axis) and a stats bar showing
current / average / min / max power over the retained history
(~2 hours at the default 2 s polling interval).

## Requirements

- KDE Plasma 6 / Qt 6
- A battery exposing `/sys/class/power_supply/BAT0/` (`power_now`, or
  `current_now` + `voltage_now`)

## Install

```bash
cp -r com.pgratz.powerGraph ~/.local/share/plasma/plasmoids/
kquitapp6 plasmashell && kstart plasmashell
```

Then add the **Power Graph** widget to a panel.

## Configuration

Right-click the widget → *Configure…* to set the update interval, panel
history length, bold text, the charging ⚡ indicator, and the history
window's stats bar.

## Development

Quick iteration without restarting plasmashell (prints QML errors to the
terminal):

```bash
plasmoidviewer -a com.pgratz.powerGraph
```

See `CLAUDE.md` and `AGENTS.md` for architecture notes and Plasma 6 / Qt 6
conventions used in this codebase.
