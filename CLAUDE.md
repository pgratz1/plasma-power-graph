# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A KDE Plasma 6 panel widget (`com.pgratz.powerGraph`) that displays a live scrolling graph of battery power in watts, with the current wattage overlaid as text. Discharging draw is plotted positive; charging power is plotted negative below a zero baseline (the label and stats are signed too).

Plugin ID: `com.pgratz.powerGraph`

This widget targets **Plasma 6 / Qt 6**. `metadata.json` declares `"KPackageStructure": "Plasma/Applet"` and `"X-Plasma-API-Minimum-Version": "6"` (the old Plasma 5 `ServiceTypes` / `X-Plasma-API` / `X-Plasma-MainScript` keys are gone).

## Install / reload

```bash
# Install or overwrite the installed copy
cp -r com.pgratz.powerGraph ~/.local/share/plasma/plasmoids/

# Restart plasmashell to pick up changes (briefly blanks the screen)
# Plasma 6 binaries — NOT kquitapp5/kstart5
kquitapp6 plasmashell && kstart plasmashell

# Preview without adding to a panel (useful for quick iteration).
# Prints QML errors and console output straight to the terminal — this is the
# fastest way to diagnose a widget that loads but renders nothing or misbehaves.
plasmoidviewer -a com.pgratz.powerGraph
```

After editing QML files you must either restart plasmashell or remove/re-add the widget — Plasma does not hot-reload.

## Power reading approach

**Do not read sysfs files with `XMLHttpRequest`.** Two reasons: (1) the `org.kde.powerMonitor` widget (installed at `~/.local/share/plasma/plasmoids/org.kde.powerMonitor`) used synchronous XHR and caused desktop instability by blocking the QML engine; (2) on Qt 6, `file://` XHR reads are disabled by default (`QML_XHR_ALLOW_FILE_READ` defaults off), so they silently return an empty string — the widget reads a constant 0 W with no error.

Instead, use the executable `DataSource` with `engine: "executable"` and a `connectedSources` + `interval` for async polling. The power calculation mirrors `~/save/powerscript.sh`:

```
watts = (current_now × voltage_now) / 10^12
```

With a fallback to `power_now / 1,000,000` when that sysfs file exists. Both files are under `/sys/class/power_supply/BAT0/`.

**Sign convention: discharge positive, charge negative.** The sysfs reading supplies only the magnitude (`Math.abs()` at ingestion — `current_now` is signed on some drivers and unsigned on others); the sign comes solely from `/sys/class/power_supply/BAT0/status` (`Charging` → negative, everything else → positive). Because the sign depends on it, the status DataSource is always connected — the `showChargingStatus` config gates only the ⚡ label suffix. Power samples are dropped until the first status sample arrives (`statusKnown`) so the first plotted points can't be mis-signed.

## Architecture

Panel widget logic lives in `contents/ui/main.qml`; the click-to-open history window is `contents/ui/HistoryWindow.qml`.

- **Root element is `PlasmoidItem`** (from `import org.kde.plasma.plasmoid`). A plain `Item` root loads but silently renders nothing on Plasma 6 — no error message.
- **Two `PlasmaSupport.DataSource`** objects (power + charging status) from `import org.kde.plasma.plasma5support as PlasmaSupport` — each keeps its source permanently connected; the DataSource `interval` property drives polling. Never use the connect/disconnect-on-timer pattern with the same command string; the executable engine caches by source name and won't re-run it. The `onNewData` handler uses Qt 6 arrow-function signal syntax: `onNewData: (sourceName, data) => { … }`.
- **`Canvas`** — draws the scrolling area/line graph on every `requestPaint()` call triggered by new data. History is a plain JS array of signed watts capped at `maxHistory` points. The Y-axis spans `[min(0, trough) × 1.15, max(10, peak) × 1.15]` with a zero baseline between: the area fill and its gradient anchor at the zero line (not the bottom edge), a faint zero line is drawn only when negative (charging) data is on screen, and with no negative data the rendering is identical to a plain positive-only graph.
- **Text label** — wrapped in a sizing `Item` + `Rectangle` backdrop; uses `Kirigami.Theme.defaultFont.pointSize` so it matches other panel items without manual sizing. Container width is clamped to the widget and the text uses `fontSizeMode: Text.Fit`, so the charging " ⚡" suffix shrinks the text instead of overflowing.
- **History window** (`HistoryWindow.qml`) — a plain `QtQuick.Window` (there is no `PlasmaComponents.Window`), opened by a `MouseArea` on the widget via a lazy `Loader`; closing only hides it so state survives reopen. It reads a second, longer buffer in main.qml (`fullHistory`, `{t, w}` entries, capped at `fullHistoryMax`), which is reassigned — never pushed in place — so change signals fire. Size persists to the `windowWidth`/`windowHeight` config keys on close. Because the window sits outside the plasmoid item tree, it cannot use the `Plasmoid` attached property; main.qml re-exposes the config values it needs as plain properties on `root` and hands itself over as `widgetRoot`. The scrollable graph keeps the `Canvas` viewport-sized and redraws the visible slice on `contentX` changes (a full-history-wide canvas could exceed GPU texture limits); an empty `Flickable` on top provides scrolling.

### Plasma 6 / Qt 6 conventions used here

- QML imports are **unversioned** (`import QtQuick`, `import org.kde.plasma.plasma5support as PlasmaSupport`). Adding a version like `0.1` to `plasma5support` fails with "module … version 0.1 is not installed" even though the module is present.
- Theming is `Kirigami.Theme.*` (`import org.kde.kirigami as Kirigami`), **not** the old global `theme.*` / `PlasmaCore.Theme`.
- Use the capitalized `Plasmoid.configuration.*` attached property; the lowercase `plasmoid.*` global was removed.
- `units.devicePixelRatio` is gone — Qt 6 lays out in logical pixels, so no manual DPR scaling.
- Config UI uses QtQuick Controls 2 (`import QtQuick.Controls as QQC2`); Controls 1.x was removed. QQC2 `SpinBox` is integer-only — fractional values (e.g. the update interval) are stored as scaled integers with `textFromValue`/`valueFromText` overrides.

Configuration schema is in `contents/config/main.xml` (KCFG format); UI for settings is in `contents/ui/ConfigGeneral.qml`.
