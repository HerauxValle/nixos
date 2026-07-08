pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import "../../config"

Item {
    id: root
    implicitWidth: lbl.implicitWidth + 2; implicitHeight: 22
    property real cpu: 0

    Text {
        id: lbl
        anchors.centerIn: parent
        text: "CPU " + Math.round(root.cpu) + "%"
        color: root.cpu > 80 ? Colors.error : Colors.colOnSurfaceVariant
        font.pixelSize: BarConfig.sp(11)
        Behavior on color { ColorAnimation { duration: 200 } }
    }

    Process {
        id: cpuProc
        command: ["mybar-cpumonitor"]
        running: true

        stdout: SplitParser {
            splitMarker: "\n"
            onRead: (line) => {
                // format: "cpu <float>"
                if (!line.startsWith("cpu ")) return
                const val = parseFloat(line.substring(4))
                if (!isNaN(val)) root.cpu = val
            }
        }
    }
}
