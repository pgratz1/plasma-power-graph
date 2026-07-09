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
    // True once the first status sample has arrived; power samples are
    // dropped until then so the first points can't be mis-signed.
    property bool statusKnown: false

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
            if (isNaN(watts)) return
            if (!root.statusKnown) return

            // Sign convention: discharge positive, charge negative. The
            // magnitude comes from sysfs (abs() because current_now is
            // signed on some drivers); the sign comes solely from the
            // status file.
            var signed = (root.isCharging ? -1 : 1) * Math.abs(watts)
            root.currentPower = signed
            var h = root.history.slice()
            h.push(signed)
            if (h.length > root.maxHistory) {
                h = h.slice(h.length - root.maxHistory)
            }
            root.history = h

            // Reassign (not push in place) so fullHistoryChanged fires for
            // the history window's bindings.
            var fh = root.fullHistory.slice()
            fh.push({ t: Date.now(), w: signed })
            if (fh.length > root.fullHistoryMax) {
                fh = fh.slice(fh.length - root.fullHistoryMax)
            }
            root.fullHistory = fh

            canvas.requestPaint()
        }
    }

    // Always connected (not gated by showChargingStatus): the sign of every
    // sample depends on the charging state; the config only gates the ⚡ suffix.
    PlasmaSupport.DataSource {
        id: statusRunner
        engine: "executable"
        connectedSources: [root.statusCmd]
        interval: Plasmoid.configuration.updateInterval * 1000

        onNewData: (sourceName, data) => {
            root.isCharging = (data["stdout"].trim() === "Charging")
            root.statusKnown = true
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

            // Discharge plots positive, charge negative: the Y range spans
            // [min(0, trough), max(10, peak)] with headroom, zero line between.
            var maxVal = 10.0
            var minVal = 0.0
            for (var i = 0; i < h.length; i++) {
                if (h[i] > maxVal) maxVal = h[i]
                if (h[i] < minVal) minVal = h[i]
            }
            maxVal = maxVal * 1.15
            minVal = minVal * 1.15

            var ht = height
            var n = h.length
            var step = width / (root.maxHistory - 1)
            function yOf(v) { return ht * (maxVal - v) / (maxVal - minVal) }
            var zeroY = yOf(0)

            var hc = Kirigami.Theme.highlightColor

            // zero line, only when charging (negative) data is on screen
            if (minVal < 0) {
                var tc = Kirigami.Theme.textColor
                ctx.strokeStyle = Qt.rgba(tc.r, tc.g, tc.b, 0.25)
                ctx.lineWidth = 1
                ctx.beginPath()
                ctx.moveTo(0, zeroY)
                ctx.lineTo(width, zeroY)
                ctx.stroke()
            }

            // filled area between the line and the zero baseline; a single
            // closed path is correct across zero crossings (nonzero winding)
            ctx.beginPath()
            ctx.moveTo(0, zeroY)
            for (var j = 0; j < n; j++) {
                var x = (root.maxHistory - n + j) * step
                ctx.lineTo(x, yOf(h[j]))
            }
            ctx.lineTo((root.maxHistory - 1) * step, zeroY)
            ctx.closePath()
            // fade toward the zero line from both extremes; collapses to the
            // original two-stop gradient when there is no negative data
            var zf = zeroY / ht
            var grad = ctx.createLinearGradient(0, 0, 0, ht)
            grad.addColorStop(0, Qt.rgba(hc.r, hc.g, hc.b, 0.55))
            grad.addColorStop(zf, Qt.rgba(hc.r, hc.g, hc.b, 0.05))
            if (zf < 1) {
                grad.addColorStop(1, Qt.rgba(hc.r, hc.g, hc.b, 0.55))
            }
            ctx.fillStyle = grad
            ctx.fill()

            // line
            ctx.beginPath()
            for (var k = 0; k < n; k++) {
                var lx = (root.maxHistory - n + k) * step
                var ly = yOf(h[k])
                if (k === 0) ctx.moveTo(lx, ly)
                else ctx.lineTo(lx, ly)
            }
            ctx.strokeStyle = hc
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
