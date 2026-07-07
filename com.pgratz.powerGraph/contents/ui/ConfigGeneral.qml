import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts

Item {
    property real cfg_updateInterval: 2.0
    property int cfg_historyLength: 60
    property alias cfg_makeFontBold: makeFontBold.checked
    property alias cfg_showChargingStatus: showChargingStatus.checked
    property alias cfg_showStatsTable: showStatsTable.checked
    // No UI; persisted by the history window itself
    property int cfg_windowWidth: 800
    property int cfg_windowHeight: 400

    ColumnLayout {
        RowLayout {
            QQC2.Label {
                text: i18n("Update interval:")
            }
            // QQC2 SpinBox only handles integers; work in tenths of a second
            QQC2.SpinBox {
                id: updateInterval
                from: 5
                to: 600
                stepSize: 5
                value: Math.round(cfg_updateInterval * 10)
                textFromValue: function(val, locale) { return (val / 10).toFixed(1) + " s" }
                valueFromText: function(text, locale) { return Math.round(parseFloat(text) * 10) }
                onValueModified: cfg_updateInterval = value / 10
            }
        }

        RowLayout {
            QQC2.Label {
                text: i18n("History length:")
            }
            QQC2.SpinBox {
                id: historyLength
                from: 10
                to: 300
                value: cfg_historyLength
                textFromValue: function(val, locale) { return val + " pts" }
                valueFromText: function(text, locale) { return parseInt(text) }
                onValueModified: cfg_historyLength = value
            }
        }

        QQC2.CheckBox {
            id: makeFontBold
            text: i18n("Bold text")
        }

        QQC2.CheckBox {
            id: showChargingStatus
            text: i18n("Show charging indicator")
        }

        QQC2.CheckBox {
            id: showStatsTable
            text: i18n("Show stats bar in history window")
        }
    }
}
