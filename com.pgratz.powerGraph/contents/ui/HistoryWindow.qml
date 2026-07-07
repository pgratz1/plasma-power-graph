import QtQuick
import QtQuick.Window
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

Window {
    id: win

    // Set by the Loader in main.qml; all bindings below guard against null.
    property var widgetRoot: null

    readonly property var hist: widgetRoot ? widgetRoot.fullHistory : []
    readonly property real pxPerSample: 4
    // Height reserved under the plot for the time-axis labels
    readonly property int xLabelSpace: 20

    readonly property real peakW: {
        var h = hist
        var m = 0
        for (var i = 0; i < h.length; i++) {
            if (h[i].w > m) m = h[i].w
        }
        return m
    }
    // Same auto-scale rule as the panel graph: peak + 15% headroom, 10 W floor
    readonly property real maxVal: Math.max(10, peakW) * 1.15
    readonly property real gridStep: niceStep(maxVal / 4)

    readonly property real avgW: {
        var h = hist
        if (h.length === 0) return 0
        var s = 0
        for (var i = 0; i < h.length; i++) s += h[i].w
        return s / h.length
    }
    readonly property real minW: {
        var h = hist
        if (h.length === 0) return 0
        var m = h[0].w
        for (var i = 1; i < h.length; i++) {
            if (h[i].w < m) m = h[i].w
        }
        return m
    }

    function niceStep(raw) {
        var mag = Math.pow(10, Math.floor(Math.log(raw) / Math.LN10))
        var norm = raw / mag
        var n = norm <= 1 ? 1 : norm <= 2 ? 2 : norm <= 5 ? 5 : 10
        return n * mag
    }

    function fmtWatts(v) {
        return i18n("%1 W", v.toFixed(1))
    }

    title: i18n("Power Consumption History")
    width: 800
    height: 400
    minimumWidth: 400
    minimumHeight: 250
    color: Kirigami.Theme.backgroundColor
    // Independent top-level window, not a transient of the panel (which would
    // make some window managers place it centered on the panel strip)
    transientParent: null

    onWidgetRootChanged: {
        if (widgetRoot) {
            width = widgetRoot.savedWindowWidth
            height = widgetRoot.savedWindowHeight
        }
    }

    onHistChanged: {
        if (flick.follow) {
            flick.contentX = Math.max(0, flick.contentWidth - flick.width)
        }
        dataCanvas.requestPaint()
        yAxisCanvas.requestPaint()
    }

    // Default close is not prevented: the window just hides, and the Loader in
    // main.qml keeps the object alive for the next click.
    onClosing: (close) => {
        if (widgetRoot) {
            widgetRoot.saveWindowSize(width, height)
        }
    }

    Shortcut {
        sequences: [StandardKey.Cancel]
        onActivated: win.close()
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Kirigami.Units.largeSpacing
        spacing: Kirigami.Units.smallSpacing

        RowLayout {
            visible: win.widgetRoot ? win.widgetRoot.showStatsBar : true
            spacing: Kirigami.Units.gridUnit

            QQC2.Label {
                font.bold: true
                text: i18n("Current: %1", win.fmtWatts(win.widgetRoot ? win.widgetRoot.currentPower : 0))
                      + (win.widgetRoot && win.widgetRoot.isCharging ? " ⚡" : "")
            }
            QQC2.Label { text: i18n("Average: %1", win.fmtWatts(win.avgW)) }
            QQC2.Label { text: i18n("Min: %1", win.fmtWatts(win.minW)) }
            QQC2.Label { text: i18n("Max: %1", win.fmtWatts(win.peakW)) }
            Item { Layout.fillWidth: true }
            QQC2.Label {
                opacity: 0.6
                text: i18n("%1 samples", win.hist.length)
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

            // Fixed watt-axis gutter; label positions match the gridlines
            // drawn by dataCanvas
            Canvas {
                id: yAxisCanvas
                Layout.preferredWidth: 46
                Layout.fillHeight: true

                onPaint: {
                    var ctx = getContext("2d")
                    ctx.clearRect(0, 0, width, height)
                    var plotH = height - win.xLabelSpace
                    var tc = Kirigami.Theme.textColor
                    ctx.fillStyle = Qt.rgba(tc.r, tc.g, tc.b, 0.8)
                    ctx.font = "10px " + Kirigami.Theme.defaultFont.family
                    ctx.textAlign = "right"
                    ctx.textBaseline = "middle"
                    for (var v = 0; v < win.maxVal; v += win.gridStep) {
                        var y = plotH - (v / win.maxVal) * plotH
                        var label = (win.gridStep >= 1 ? v.toFixed(0) : v.toFixed(1)) + " W"
                        ctx.fillText(label, width - 6, Math.max(y, 6))
                    }
                }
            }

            // The plot viewport. The Canvas stays viewport-sized and redraws
            // the visible slice on scroll — a Canvas as wide as the whole
            // history could exceed the GPU texture size limit. The Flickable
            // on top is empty and only provides scrolling + the scrollbar.
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true

                Canvas {
                    id: dataCanvas
                    anchors.fill: parent

                    onWidthChanged: requestPaint()
                    onHeightChanged: requestPaint()

                    onPaint: {
                        var ctx = getContext("2d")
                        ctx.clearRect(0, 0, width, height)

                        var plotH = height - win.xLabelSpace
                        var tc = Kirigami.Theme.textColor
                        var hc = Kirigami.Theme.highlightColor

                        // horizontal gridlines (position-independent, so they
                        // can be drawn in viewport coordinates)
                        ctx.strokeStyle = Qt.rgba(tc.r, tc.g, tc.b, 0.15)
                        ctx.lineWidth = 1
                        for (var v = 0; v < win.maxVal; v += win.gridStep) {
                            var gy = plotH - (v / win.maxVal) * plotH
                            ctx.beginPath()
                            ctx.moveTo(0, gy)
                            ctx.lineTo(width, gy)
                            ctx.stroke()
                        }

                        var h = win.hist
                        if (h.length < 2) return

                        var px = win.pxPerSample
                        var offset = flick.contentX
                        var first = Math.max(0, Math.floor(offset / px) - 1)
                        var last = Math.min(h.length - 1, Math.ceil((offset + width) / px) + 1)

                        // filled area under the line
                        ctx.beginPath()
                        ctx.moveTo(first * px - offset, plotH)
                        for (var i = first; i <= last; i++) {
                            ctx.lineTo(i * px - offset, plotH - (h[i].w / win.maxVal) * plotH)
                        }
                        ctx.lineTo(last * px - offset, plotH)
                        ctx.closePath()
                        var grad = ctx.createLinearGradient(0, 0, 0, plotH)
                        grad.addColorStop(0, Qt.rgba(hc.r, hc.g, hc.b, 0.55))
                        grad.addColorStop(1, Qt.rgba(hc.r, hc.g, hc.b, 0.05))
                        ctx.fillStyle = grad
                        ctx.fill()

                        // line
                        ctx.beginPath()
                        for (var k = first; k <= last; k++) {
                            var lx = k * px - offset
                            var ly = plotH - (h[k].w / win.maxVal) * plotH
                            if (k === first) ctx.moveTo(lx, ly)
                            else ctx.lineTo(lx, ly)
                        }
                        ctx.strokeStyle = hc
                        ctx.lineWidth = 1.5
                        ctx.stroke()

                        // time labels from the sample timestamps
                        var stride = Math.max(1, Math.round(120 / px))
                        var spanMs = h[h.length - 1].t - h[0].t
                        var fmt = spanMs < 10 * 60 * 1000 ? "hh:mm:ss" : "hh:mm"
                        ctx.fillStyle = Qt.rgba(tc.r, tc.g, tc.b, 0.7)
                        ctx.font = "10px " + Kirigami.Theme.defaultFont.family
                        ctx.textAlign = "center"
                        ctx.textBaseline = "alphabetic"
                        for (var m = Math.ceil(first / stride) * stride; m <= last; m += stride) {
                            ctx.fillText(Qt.formatTime(new Date(h[m].t), fmt),
                                         m * px - offset, height - 5)
                        }
                    }
                }

                Flickable {
                    id: flick
                    anchors.fill: parent
                    contentWidth: Math.max(win.hist.length * win.pxPerSample, width)
                    contentHeight: height
                    boundsBehavior: Flickable.StopAtBounds

                    // Stay pinned to the newest data unless the user has
                    // scrolled back in time; scrolling to the right edge
                    // re-enables following.
                    property bool follow: true
                    onContentXChanged: {
                        follow = contentX >= contentWidth - width - 2
                        dataCanvas.requestPaint()
                    }

                    QQC2.ScrollBar.horizontal: QQC2.ScrollBar { }
                }
            }
        }
    }
}
