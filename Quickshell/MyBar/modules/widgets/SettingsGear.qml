import QtQuick
import "../../config"

Item {
    property string barScreenName: ""
    implicitWidth: 22; implicitHeight: 22

    // This glyph's own ink doesn't fill the font's line-height box symmetrically
    // (common across icon fonts patched together from different source sets),
    // so neither anchors.centerIn (centers the Text item's implicit
    // ascent+descent box) nor fill+AlignVCenter (centers by line metrics) land
    // on the actual drawn shape. FontMetrics.ascent + TextMetrics.tightBoundingRect
    // give this exact glyph's real ink position so the offset is derived from
    // real font metrics at runtime, not a guessed pixel constant:
    // tightBoundingRect is relative to the baseline (negative y = above it),
    // while a Text item's own y=0 sits `ascent` pixels above the baseline --
    // so the ink's top, in the Text item's parent's coordinate space, is
    // itemY + ascent + tightBoundingRect.y. Solving for the itemY that puts
    // the ink's vertical center at parent.height/2 gives the y below.
    FontMetrics {
        id: gearFontMetrics
        font.family: "Symbols Nerd Font Mono"
        font.pixelSize: BarConfig.sp(13)
    }
    TextMetrics {
        id: gearMetrics
        font: gearFontMetrics.font
        text: "\uF013"
    }

    Text {
        id: gearGlyph
        x: (parent.width - width) / 2
        y: parent.height / 2 - gearFontMetrics.ascent - gearMetrics.tightBoundingRect.y - gearMetrics.tightBoundingRect.height / 2
        text: "\uF013"
        font: gearFontMetrics.font
        color: BarConfig.currentPopup !== "" && BarConfig.currentPopupScreen === barScreenName ? Colors.primary : Colors.colOnSurfaceVariant
        rotation: BarConfig.currentPopup !== "" && BarConfig.currentPopupScreen === barScreenName ? 30 : 0
        Behavior on rotation { NumberAnimation { duration: 200; easing.bezierCurve: Colors.spring } }
        Behavior on color    { ColorAnimation  { duration: 120 } }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: BarConfig.togglePopup("controlcenter", barScreenName)
    }
}
