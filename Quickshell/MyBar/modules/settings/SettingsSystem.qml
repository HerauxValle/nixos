pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Io
import "../../config"

Item {
    id: root
    clip: true

    property string hostname:    "..."
    property string kernelVer:   "..."
    property string uptime:      "..."
    property string cpuModel:    "..."
    property string cpuCores:    "..."
    property string memTotal:    "..."
    property string memUsed:     "..."
    property string diskUsage:   "..."
    property string osRelease:   "..."

    Component.onCompleted: {
        hostnameProc.running  = true
        kernelProc.running    = true
        uptimeProc.running    = true
        cpuProc.running       = true
        memProc.running       = true
        diskProc.running      = true
        osProc.running        = true
    }

    Timer { interval: 10000; repeat: true; running: true
            onTriggered: { uptimeProc.running = true; memProc.running = true; diskProc.running = true } }

    Process { id: hostnameProc; command: ["hostname"]
        stdout: StdioCollector { onStreamFinished: root.hostname = text.trim() } }
    Process { id: kernelProc; command: ["uname", "-r"]
        stdout: StdioCollector { onStreamFinished: root.kernelVer = text.trim() } }
    Process { id: uptimeProc; command: ["bash", "-c", "uptime -p 2>/dev/null || uptime"]
        stdout: StdioCollector { onStreamFinished: root.uptime = text.trim().replace(/^up /, "") } }
    Process { id: cpuProc;
        command: ["bash", "-c", "model=$(grep 'model name' /proc/cpuinfo | head -1 | cut -d: -f2 | sed 's/^[ \t]*//'); cores=$(nproc 2>/dev/null || grep -c processor /proc/cpuinfo); echo "$model|$cores""]
        stdout: StdioCollector {
            onStreamFinished: {
                const parts = text.trim().split("|")
                root.cpuModel = parts[0] || "Unknown"
                root.cpuCores = (parts[1] || "?") + " cores"
            }
        }
    }
    Process { id: memProc;
        command: ["bash", "-c", "free -h 2>/dev/null | awk '/^Mem:/{print $2 "|" $3}'"]
        stdout: StdioCollector {
            onStreamFinished: {
                const parts = text.trim().split("|")
                root.memTotal = parts[0] || "?"
                root.memUsed  = parts[1] || "?"
            }
        }
    }
    Process { id: diskProc;
        command: ["bash", "-c", "df -h / 2>/dev/null | awk 'NR==2{print $3 "|" $2 "|" $5}'"]
        stdout: StdioCollector {
            onStreamFinished: {
                const parts = text.trim().split("|")
                root.diskUsage = (parts[0] || "?") + " / " + (parts[1] || "?") + " (" + (parts[2] || "?") + ")"
            }
        }
    }
    Process { id: osProc;
        command: ["bash", "-c", "grep PRETTY_NAME /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '\"'"]
        stdout: StdioCollector { onStreamFinished: root.osRelease = text.trim() } }

    component SLabel: Text {
        color: Colors.primary; font.pixelSize: 9; font.weight: Font.Medium; font.letterSpacing: 1; opacity: 0.8
    }
    component HR: Rectangle { width: parent?.width ?? 400; height: 1; color: Colors.outlineVariant; opacity: 0.5 }
    component InfoRow: Item {
        id: ir; required property string label; required property string value
        width: parent?.width ?? 400; height: 32
        Text { anchors { left: parent.left; verticalCenter: parent.verticalCenter }
               text: ir.label; color: Colors.colOnSurfaceVariant; font.pixelSize: 12; width: 120 }
        Text { anchors { right: parent.right; verticalCenter: parent.verticalCenter }
               text: ir.value; color: Colors.colOnSurface; font.pixelSize: 12; elide: Text.ElideRight; width: 250; horizontalAlignment: Text.AlignRight }
    }

    Flickable {
        anchors.fill: parent; contentWidth: width; contentHeight: col.implicitHeight + 32; clip: true
        Column {
            id: col; width: parent.width - 48; x: 24; y: 20; spacing: 10

            SLabel { text: "SYSTEM" }
            InfoRow { label: "Hostname";  value: root.hostname }
            InfoRow { label: "OS";        value: root.osRelease }
            InfoRow { label: "Kernel";    value: root.kernelVer }
            InfoRow { label: "Uptime";    value: root.uptime }

            HR {}
            SLabel { text: "HARDWARE" }
            InfoRow { label: "CPU";       value: root.cpuModel }
            InfoRow { label: "Cores";     value: root.cpuCores }
            InfoRow { label: "RAM Total"; value: root.memTotal }
            InfoRow { label: "RAM Used";  value: root.memUsed }
            InfoRow { label: "Disk (/)";  value: root.diskUsage }

            Item { height: 8 }
        }
    }
}
