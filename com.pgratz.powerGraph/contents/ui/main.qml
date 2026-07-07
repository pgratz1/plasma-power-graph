import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.plasma5support as PlasmaSupport
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root

    width: 160
    height: 40
    Layout.preferredWidth: 160
    Layout.preferredHeight: 40

    property var history: []
    property int maxHistory: Plasmoid.configuration.historyLength
    property double currentPower: 0.0
    property bool isCharging: false

    // Longer buffer backing the history window; entries are {t: epoch-ms, w: watts}.
    property var fullHistory: []
    readonly property int fullHistoryMax: 3600

    // HistoryWindow.qml lives outside the plasmoid item tree and cannot use the
    // Plasmoid attached property, so the config it needs is re-exposed here.
    readonly property bool showStatsBar: Plasmoid.configuration.showStatsTable
    readonly property int savedWindowWidth: Plasmoid.configuration.windowWidth
    readonly property int savedWindowHeight: Plasmoid.configuration.windowHeight

    function saveWindowSize(w, h) {
        Plasmoid.configuration.windowWidth = w
        Plasmoid.configuration.windowHeight = h
    }

    // Keep the source permanently connected; the DataSource's own interval
    // property re-runs the command automatically — no disconnect/reconnect needed.
    readonly property string powerCmd: "bash -c 'f=/sys/class/power_supply/BAT0/power_now; " +
        "if [ -r \"$f\" ] && [ -s \"$f\" ]; then " +
        "  awk \"{printf \\\"%.1f\\\", \\$1/1000000}\" \"$f\"; " +
        "else " +
        "  awk \"BEGIN{printf \\\"%.1f\\\", (" +
        "$(cat /sys/class/power_supply/BAT0/current_now) * " +
        "$(cat /sys/class/power_supply/BAT0/voltage_now)" +
        ") / 1000000000000}\"; " +
        "fi'"

    readonly property string statusCmd: "cat /sys/class/power_supply/BAT0/status"

    PlasmaSupport.DataSource {
        id: powerRunner
        engine: "executable"
        connectedSources: [root.powerCmd]
        interval: Plasmoid.configuration.updateInterval * 1000

        onNewData: (sourceName, data) => {
            var watts = parseFloat(data["stdout"].trim())
            if (!isNaN(watts) && watts >= 0) {
                root.currentPower = watts
                var h = root.history.slice()
                h.push(watts)
                if (h.length > root.maxHistory) {
                    h = h.slice(h.length - root.maxHistory)
                }
                root.history = h

                // Reassign (not push in place) so fullHistoryChanged fires for
                // the history window's bindings.
                var fh = root.fullHistory.slice()
                fh.push({ t: Date.now(), w: watts })
                if (fh.length > root.fullHistoryMax) {
                    fh = fh.slice(fh.length - root.fullHistoryMax)
                }
                root.fullHistory = fh

                canvas.requestPaint()
            }
        }
    }

    PlasmaSupport.DataSource {
        id: statusRunner
        engine: "executable"
        connectedSources: Plasmoid.configuration.showChargingStatus ? [root.statusCmd] : []
        interval: Plasmoid.configuration.updateInterval * 1000

        onNewData: (sourceName, data) => {
            root.isCharging = (data["stdout"].trim() === "Charging")
        }
    }

    Canvas {
        id: canvas
        anchors.fill: parent

        onPaint: {
            var ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)

            var h = root.history
            if (h.length < 2) return

            var maxVal = 10.0
            for (var i = 0; i < h.length; i++) {
                if (h[i] > maxVal) maxVal = h[i]
            }
            maxVal = maxVal * 1.15

            var ht = height
            var n = h.length
            var step = width / (root.maxHistory - 1)

            // filled area under the line
            ctx.beginPath()
            ctx.moveTo(0, ht)
            for (var j = 0; j < n; j++) {
                var x = (root.maxHistory - n + j) * step
                var y = ht - (h[j] / maxVal) * ht
                ctx.lineTo(x, y)
            }
            ctx.lineTo((root.maxHistory - 1) * step, ht)
            ctx.closePath()
            var grad = ctx.createLinearGradient(0, 0, 0, ht)
            grad.addColorStop(0, Qt.rgba(Kirigami.Theme.highlightColor.r,
                                         Kirigami.Theme.highlightColor.g,
                                         Kirigami.Theme.highlightColor.b, 0.55))
            grad.addColorStop(1, Qt.rgba(Kirigami.Theme.highlightColor.r,
                                         Kirigami.Theme.highlightColor.g,
                                         Kirigami.Theme.highlightColor.b, 0.05))
            ctx.fillStyle = grad
            ctx.fill()

            // line
            ctx.beginPath()
            for (var k = 0; k < n; k++) {
                var lx = (root.maxHistory - n + k) * step
                var ly = ht - (h[k] / maxVal) * ht
                if (k === 0) ctx.moveTo(lx, ly)
                else ctx.lineTo(lx, ly)
            }
            ctx.strokeStyle = Kirigami.Theme.highlightColor
            ctx.lineWidth = 1.5
            ctx.stroke()
        }
    }

    // Label overlaid on the graph, anchored bottom-right.
    // Width is clamped to the widget so the charging suffix can't overflow;
    // the text shrinks to fit instead.
    Item {
        id: labelContainer
        anchors {
            right: parent.right
            bottom: parent.bottom
            rightMargin: 4
            bottomMargin: 2
        }
        width: Math.min(labelText.implicitWidth + 8, parent.width - anchors.rightMargin - 4)
        height: labelText.implicitHeight + 4

        Rectangle {
            anchors.fill: parent
            color: Qt.rgba(Kirigami.Theme.backgroundColor.r,
                           Kirigami.Theme.backgroundColor.g,
                           Kirigami.Theme.backgroundColor.b, 0.6)
            radius: 3
        }

        Text {
            id: labelText
            anchors.fill: parent
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            fontSizeMode: Text.Fit
            minimumPointSize: 6
            text: {
                var t = root.currentPower.toFixed(1) + " W"
                if (Plasmoid.configuration.showChargingStatus && root.isCharging) {
                    t += " ⚡"
                }
                return t
            }
            font.pointSize: Kirigami.Theme.defaultFont.pointSize
            font.bold: Plasmoid.configuration.makeFontBold
            color: Kirigami.Theme.textColor
        }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            if (windowLoader.active) {
                windowLoader.item.show()
                windowLoader.item.raise()
                windowLoader.item.requestActivate()
            } else {
                windowLoader.active = true
            }
        }
    }

    // The history window is created on first click and then kept alive;
    // closing it only hides it, so its state survives reopen.
    Loader {
        id: windowLoader
        active: false
        source: "HistoryWindow.qml"
        onLoaded: {
            item.widgetRoot = root
            item.show()
            item.raise()
            item.requestActivate()
        }
    }
}
