pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import "../../config"

Item {
    id: root
    implicitWidth: lbl.implicitWidth + 2; implicitHeight: 22
    property string memText: "RAM"

    Text {
        id: lbl
        anchors.centerIn: parent
        text: root.memText
        color: Colors.colOnSurfaceVariant; font.pixelSize: BarConfig.sp(11)
    }

    Process {
        id: memProc
        command: ["mybar-memmonitor"]
        running: true

        stdout: SplitParser {
            splitMarker: "\n"
            onRead: (line) => {
                // format: "mem <used>/<total>"
                if (!line.startsWith("mem ")) return
                root.memText = "RAM " + line.substring(4) + "G"
            }
        }
    }
}
