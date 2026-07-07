# Agents.md - Key Documentation

This file contains essential information for automating tasks in the Power Graph Plasma widget project.

## Project Structure
- `com.pgratz.powerGraph/` - Main plasma widget directory
  - `contents/ui/main.qml` - Primary QML file with graph rendering and data sources
  - `contents/ui/HistoryWindow.qml` - Resizable history window opened by clicking the widget
  - `contents/config/main.xml` - Configuration schema (KCFG format)
  - `contents/ui/ConfigGeneral.qml` - Configuration UI
  - `metadata.json` - Plugin metadata

## Key Files
1. **main.qml** (`com.pgratz.powerGraph/contents/ui/main.qml`): Main widget implementation with:
   - Two DataSource objects for power reading and charging status
   - Canvas-based graph rendering
   - Overlaid text label showing current watts (clamped + Text.Fit so the ⚡ suffix can't overflow)
   - `fullHistory` buffer of `{t, w}` samples (cap: `fullHistoryMax`) feeding the history window
   - MouseArea + lazy Loader that opens HistoryWindow.qml on click

2. **HistoryWindow.qml** (`com.pgratz.powerGraph/contents/ui/HistoryWindow.qml`): Plain QtQuick Window with:
   - Stats bar (current/average/min/max watts, toggled by showStatsTable)
   - Horizontally scrollable graph with watt gridlines and time-axis labels
   - Auto-follows newest data unless the user scrolled back
   - Persists its size to windowWidth/windowHeight config keys on close

3. **ConfigGeneral.qml** (`com.pgratz.powerGraph/contents/ui/ConfigGeneral.qml`): Configuration UI with settings for:
   - Update interval (stored as 10x value due to integer-only SpinBox)
   - History length
   - Bold text toggle
   - Charging status indicator
   - Stats bar toggle for the history window

4. **main.xml** (`com.pgratz.powerGraph/contents/config/main.xml`): Configuration schema defining:
   - updateInterval (Double, default: 2.0)
   - historyLength (Int, default: 60)
   - makeFontBold (Bool, default: false)
   - showChargingStatus (Bool, default: true)
   - windowWidth / windowHeight (Int, defaults: 800/400) - history window size
   - showStatsTable (Bool, default: true) - stats bar in history window

## Installation and Development Commands
- Install widget:
  ```bash
  cp -r com.pgratz.powerGraph ~/.local/share/plasma/plasmoids/
  ```
- Restart plasmashell to pick up changes:
  ```bash
  kquitapp6 plasmashell && kstart plasmashell
  ```
- Preview widget for quick testing/iteration:
  ```bash
  plasmoidviewer -a com.pgratz.powerGraph
  ```

## Important Patterns and Conventions
- **QML imports are unversioned**: Use `import org.kde.plasma.plasmoid` (not versioned)
- **Theming uses Kirigami**: Access colors via `Kirigami.Theme.*`
- **Configuration access**: Use `Plasmoid.configuration.*` (uppercase, not lowercase)
- **DataSource polling**: Set `connectedSources` and `interval` properties for automatic polling
- **No manual XHR**: Uses executable DataSource to read sysfs files asynchronously
- **Root element is PlasmoidItem**: A plain Item renders nothing silently

## Development Notes
- Plasma does not hot-reload widgets - always restart plasmashell after QML changes
- `plasmoidviewer` outputs QML errors and console messages directly to terminal
- DataSource engines cache by source name - changing the script requires a new source name