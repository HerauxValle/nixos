pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import "../../config"
import "../../services"

Rectangle {
    id: root
    property string barScreenName: ""
    implicitWidth: BarConfig.sp(380)
    height: parent?.height ?? 480
    radius: BarConfig.sp(14)
    color: Qt.rgba(Colors.surface.r, Colors.surface.g, Colors.surface.b, BarConfig.barOpacity)
    border.color: Colors.popupBorder
    border.width: 1
    clip: true

    MouseArea { anchors.fill: parent; onClicked: {} }

    // ── State ─────────────────────────────────────────────────────────────
    property var    networks:      []   // [{ssid, signal, security, active, saved}]
    property var    savedNames:    []   // list of saved connection SSIDs
    property bool   scanning:      false
    property int    scanDots:      0
    property string pendingSsid:   ""
    property string passInput:     ""
    property bool   showPassDialog: false
    property bool   connecting:    false
    property string connectStatus: ""  // "" | "ok" | "fail"
    property string wifiInterface: ""

    // Detail info for current connection
    property string detailMac: ""; property string detailIpv4: ""
    property string detailIpv6: ""; property string detailGateway: ""
    property string detailDns:  ""

    // ── Derived lists ─────────────────────────────────────────────────────
    readonly property var knownNetworks: root.networks.filter(n => n.saved && !n.active)
    readonly property var newNetworks:   root.networks.filter(n => !n.saved && !n.active)
    readonly property var activeNetwork: root.networks.find(n => n.active) ?? null

    // ── Detect adapter ────────────────────────────────────────────────────
    Process {
        id: ifaceProc
        command: ["bash", "-c", "ls /sys/class/net | grep -E '^wl' | head -1"]
        running: true
        stdout: StdioCollector { onStreamFinished: { const i = text.trim(); if (i) root.wifiInterface = i } }
    }

    // ── Network details (when connected) ──────────────────────────────────
    Process { id: macProc;     command: ["bash", "-c", "ip link show " + root.wifiInterface + " 2>/dev/null | awk '/ether/{print $2}' | head -1"]; stdout: StdioCollector { onStreamFinished: root.detailMac     = text.trim() } }
    Process { id: ipv4Proc;    command: ["bash", "-c", "ip -4 addr show " + root.wifiInterface + " 2>/dev/null | awk '/inet /{print $2}' | head -1"]; stdout: StdioCollector { onStreamFinished: root.detailIpv4    = text.trim() } }
    Process { id: ipv6Proc;    command: ["bash", "-c", "ip -6 addr show " + root.wifiInterface + " 2>/dev/null | grep 'inet6 ' | grep -v fe80 | awk '{print $2}' | head -1"]; stdout: StdioCollector { onStreamFinished: root.detailIpv6    = text.trim() } }
    Process { id: gatewayProc; command: ["bash", "-c", "ip route show default 2>/dev/null | awk '/default/{print $3}' | head -1"]; stdout: StdioCollector { onStreamFinished: root.detailGateway = text.trim() } }
    Process { id: dnsProc;     command: ["bash", "-c", "grep nameserver /etc/resolv.conf 2>/dev/null | awk '{print $2}' | tr '\\n' ' ' | sed 's/ $//'"]; stdout: StdioCollector { onStreamFinished: root.detailDns     = text.trim() } }

    function refreshDetails() {
        if (root.wifiInterface === "") return
        macProc.running = true; ipv4Proc.running = true; ipv6Proc.running = true
        gatewayProc.running = true; dnsProc.running = true
    }
    onWifiInterfaceChanged: refreshDetails()
    Connections {
        target: Network
        function onWifiOnChanged()   { root.refreshDetails(); root.loadAll() }
        function onWifiSSIDChanged() { root.refreshDetails() }
    }

    // ── Scan + list ───────────────────────────────────────────────────────
    // Use python3 to split on unescaped colons safely (handles SSIDs with colons)
    Process {
        id: rescanProc
        command: ["bash", "-c", (root.wifiInterface !== ""
            ? "nmcli device wifi rescan ifname " + root.wifiInterface + " 2>/dev/null"
            : "nmcli device wifi rescan 2>/dev/null") + "; true"]
        onExited: { listProc.running = true; rescanDelay.start() }
    }
    Timer { id: rescanDelay; interval: 2500; onTriggered: { if (!listProc.running) listProc.running = true } }
    Timer { id: scanDotTimer; interval: 500; repeat: true; onTriggered: root.scanDots++ }

    Process {
        id: listProc
        command: ["bash", "-c",
            "nmcli -t -e yes -f SSID,SIGNAL,SECURITY,IN-USE device wifi list" +
            (root.wifiInterface !== "" ? " ifname " + root.wifiInterface : "") +
            " 2>/dev/null | python3 -c \"\nimport sys\nlines = sys.stdin.read().splitlines()\nfor line in lines:\n    # rsplit from right to handle colons in SSID\n    p = line.rsplit(':', 3)\n    if len(p) == 4:\n        ssid = p[0].replace('\\\\\\\\:', ':')\n        print(ssid + '\\\\t' + p[1] + '\\\\t' + p[2] + '\\\\t' + p[3])\n\""]
        stdout: StdioCollector {
            onStreamFinished: {
                root.scanning = false
                scanDotTimer.stop()
                const lines = text.trim().split("\n").filter(l => l.length > 0)
                const seen  = {}
                const parsed = []
                const savedSet = new Set(root.savedNames)
                for (const line of lines) {
                    const p = line.split("\t")
                    if (p.length < 4) continue
                    const ssid     = p[0]
                    const signal   = parseInt(p[1]) || 0
                    const security = (p[2] === "--" || p[2] === "") ? "" : p[2]
                    const active   = p[3].trim() === "*"
                    if (!ssid || seen[ssid]) continue
                    seen[ssid] = true
                    parsed.push({ ssid, signal, security, active, saved: savedSet.has(ssid) })
                }
                parsed.sort((a, b) => b.signal - a.signal)
                root.networks = parsed
            }
        }
    }

    Process {
        id: savedProc
        command: ["bash", "-c", "nmcli -t -f NAME,TYPE connection show 2>/dev/null | grep ':802-11-wireless$' | sed 's/:802-11-wireless$//'"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.savedNames = text.trim().split("\n").filter(n => n.length > 0)
            }
        }
    }

    function loadAll() { savedProc.running = true; listProc.running = true }
    function startScan() {
        root.scanning = true; root.scanDots = 0
        scanDotTimer.restart(); rescanProc.running = true
    }

    // ── Connect ───────────────────────────────────────────────────────────
    Process {
        id: connectProc
        property string ssid: ""; property string password: ""
        command: password !== ""
            ? ["nmcli", "device", "wifi", "connect", ssid, "password", password]
            : ["nmcli", "device", "wifi", "connect", ssid]
        onExited: (code) => {
            root.connecting = false
            root.connectStatus = code === 0 ? "ok" : "fail"
            statusTimer.restart()
            if (code === 0) { root.refreshDetails(); root.loadAll() }
        }
    }
    Process {
        id: connectKnownProc
        property string ssid: ""
        command: ["nmcli", "connection", "up", ssid]
        onExited: (code) => {
            root.connecting = false
            root.connectStatus = code === 0 ? "ok" : "fail"
            statusTimer.restart()
            if (code === 0) { root.refreshDetails(); root.loadAll() }
        }
    }
    Timer { id: statusTimer; interval: 3000; onTriggered: root.connectStatus = "" }

    // ── Disconnect / Forget ───────────────────────────────────────────────
    Process {
        id: disconnectProc
        command: ["nmcli", "device", "disconnect", root.wifiInterface]
        onExited: (code) => { if (code === 0) root.loadAll() }
    }
    Process {
        id: forgetProc
        property string ssid: ""
        command: ["nmcli", "connection", "delete", ssid]
        onExited: (code) => { if (code === 0) { root.loadAll(); root.startScan() } }
    }

    // ── Signal bars ───────────────────────────────────────────────────────
    component SignalBars: Item {
        id: bars; required property int signal
        implicitWidth: BarConfig.sp(20); implicitHeight: BarConfig.sp(14)
        Repeater {
            model: 4
            Rectangle {
                required property int index
                width: BarConfig.sp(3); height: 3 + index * 3; radius: 1
                x: index * 5; y: 14 - height
                color: bars.signal > index * 25 ? Colors.primary : Colors.outlineVariant
            }
        }
    }

    // ── WifiNetworkItem ───────────────────────────────────────────────────
    component WifiNetworkItem: Rectangle {
        id: wni
        required property var    wifiNet
        property string itemMode: "new"   // "active"|"known"|"new"
        signal connectRequested()
        signal forgetRequested()
        signal disconnectRequested()

        width: parent?.width ?? 320; height: BarConfig.sp(48); radius: BarConfig.sp(10)
        color: wni.itemMode === "active"
               ? Qt.rgba(Colors.primary.r, Colors.primary.g, Colors.primary.b, 0.13)
               : Colors.surfaceContainerHigh
        border.color: wni.itemMode === "active" ? Colors.primary : "transparent"
        border.width: wni.itemMode === "active" ? 1 : 0

        Item {
            anchors { fill: parent; leftMargin: BarConfig.sp(12); rightMargin: BarConfig.sp(10) }

            SignalBars {
                id: wBars; signal: wni.wifiNet?.signal ?? 0
                anchors { left: parent.left; verticalCenter: parent.verticalCenter }
            }

            Column {
                anchors { left: wBars.right; leftMargin: BarConfig.sp(8); right: btnRow.left; rightMargin: BarConfig.sp(6); verticalCenter: parent.verticalCenter }
                spacing: 1
                Text {
                    text: wni.wifiNet?.ssid ?? ""
                    color: Colors.colOnSurface; font.pixelSize: BarConfig.fsMd; font.weight: Font.Medium
                    elide: Text.ElideRight; width: parent.width
                }
                Text {
                    text: wni.wifiNet?.security || "Open"
                    color: Colors.colOnSurfaceVariant; font.pixelSize: BarConfig.fsSm; opacity: 0.7
                }
            }

            Row {
                id: btnRow
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                spacing: BarConfig.sp(6)

                // Forget button (active + known)
                Rectangle {
                    visible: wni.itemMode === "active" || wni.itemMode === "known"
                    width: BarConfig.sp(46); height: BarConfig.sp(24); radius: BarConfig.sp(12)
                    color: Qt.rgba(1, 0.3, 0.3, 0.10)
                    border.color: Qt.rgba(1, 0.3, 0.3, 0.4); border.width: 1
                    Text { anchors.centerIn: parent; text: "Forget"; color: "#FF6B6B"; font.pixelSize: BarConfig.fsSm }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: wni.forgetRequested() }
                }

                // Disconnect (active) / Connect (known) / Tap to connect hint (new)
                Rectangle {
                    width: wni.itemMode === "active" ? 74 : (wni.itemMode === "known" ? 58 : 0)
                    visible: width > 0; height: BarConfig.sp(24); radius: BarConfig.sp(12)
                    color: wni.itemMode === "active"
                           ? Colors.surfaceContainerHigh
                           : Qt.rgba(Colors.primary.r, Colors.primary.g, Colors.primary.b, 0.2)
                    border.color: wni.itemMode === "active" ? Colors.outline : Colors.primary; border.width: 1
                    Text {
                        anchors.centerIn: parent
                        text: wni.itemMode === "active" ? "Disconnect" : "Connect"
                        color: wni.itemMode === "active" ? Colors.colOnSurfaceVariant : Colors.primary
                        font.pixelSize: BarConfig.fsSm
                    }
                    MouseArea {
                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                        onClicked: wni.itemMode === "active" ? wni.disconnectRequested() : wni.connectRequested()
                    }
                }

                // Connected checkmark
                Text {
                    visible: wni.itemMode === "active"
                    text: "✓"; color: Colors.primary; font.pixelSize: BarConfig.fsMd; font.weight: Font.Bold
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }

        // Tap anywhere on new networks to connect
        MouseArea {
            anchors.fill: parent
            visible: wni.itemMode === "new"
            cursorShape: Qt.PointingHandCursor
            onClicked: wni.connectRequested()
        }
    }

    // ── Header ────────────────────────────────────────────────────────────
    Item {
        id: hdr; width: parent.width; height: BarConfig.sp(46); z: 2
        Item {
            anchors { fill: parent; leftMargin: BarConfig.sp(16); rightMargin: BarConfig.sp(16) }
            Row {
                anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                spacing: BarConfig.sp(8)
                Text { text: "←"; color: Colors.colOnSurfaceVariant; font.pixelSize: BarConfig.fsLg; anchors.verticalCenter: parent.verticalCenter
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: BarConfig.togglePopup("controlcenter", root.barScreenName) } }
                Text { text: "Network"; color: Colors.colOnSurface; font.pixelSize: BarConfig.fsMd; font.weight: Font.Medium; anchors.verticalCenter: parent.verticalCenter }
            }
            Text { anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                text: "✕"; color: Colors.colOnSurfaceVariant; font.pixelSize: BarConfig.fs
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: BarConfig.closePopup() } }
        }
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Colors.popupBorder; opacity: 0.8 }
    }

    // ── Scrollable body ───────────────────────────────────────────────────
    Flickable {
        id: flick
        anchors { top: hdr.bottom; left: parent.left; right: parent.right; bottom: parent.bottom }
        contentWidth: width; contentHeight: body.implicitHeight + 20; clip: true

        Column {
            id: body; width: flick.width - 28; x: 14; y: 10; spacing: BarConfig.sp(10)

            component DR: Row {
                id: dr; required property string k; required property string v
                width: parent.width; spacing: BarConfig.sp(6)
                Text { text: dr.k; color: Colors.colOnSurfaceVariant; font.pixelSize: BarConfig.fsSm; opacity: 0.65; width: 60 }
                Text { text: dr.v || "—"; color: Colors.colOnSurface; font.pixelSize: BarConfig.fsSm; font.family: "monospace"; elide: Text.ElideRight; width: parent.width - 66 }
            }

            // ── Current connection card ────────────────────────────────
            Rectangle {
                width: parent.width; height: curCol.implicitHeight + 20; radius: BarConfig.sp(12)
                color: Network.wifiOn
                       ? Qt.rgba(Colors.primary.r, Colors.primary.g, Colors.primary.b, 0.12)
                       : Colors.surfaceContainerHigh
                border.color: Network.wifiOn ? Colors.primary : Colors.popupBorder; border.width: 1
                Column {
                    id: curCol
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: BarConfig.sp(12) }
                    spacing: BarConfig.sp(5)
                    Row {
                        spacing: BarConfig.sp(8)
                        Text { font.pixelSize: BarConfig.fsLg; font.family: "Symbols Nerd Font Mono"; color: Network.wifiOn ? Colors.primary : Colors.outline; text: "" }
                        Column {
                            anchors.verticalCenter: parent.verticalCenter; spacing: BarConfig.sp(2)
                            Text { text: Network.wifiOn ? Network.wifiSSID : (!Network.wifiRadioOn ? "Wi-Fi Off" : "Not Connected"); color: Colors.colOnSurface; font.pixelSize: BarConfig.fs; font.weight: Font.Medium }
                            Text { visible: Network.wifiOn; text: "Signal: " + Network.wifiSignal + "%"; color: Colors.colOnSurfaceVariant; font.pixelSize: BarConfig.fsSm; opacity: 0.7 }
                            Text { visible: !Network.wifiOn && root.wifiInterface !== ""; text: root.wifiInterface; color: Colors.colOnSurfaceVariant; font.pixelSize: BarConfig.fsSm; opacity: 0.6 }
                        }
                    }
                    Column {
                        visible: Network.wifiOn; width: parent.width; spacing: BarConfig.sp(3)
                        DR { k: "IPv4";    v: root.detailIpv4 }
                        DR { k: "Gateway"; v: root.detailGateway }
                        DR { k: "DNS";     v: root.detailDns }
                    }
                    DR { visible: root.detailMac !== ""; k: "MAC"; v: root.detailMac }
                }
            }

            // ── WiFi radio toggle ──────────────────────────────────────
            Item {
                width: parent.width; height: BarConfig.sp(32)
                Text { anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                    text: "Wi-Fi"; color: Colors.colOnSurface; font.pixelSize: BarConfig.fs }
                Rectangle {
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                    width: BarConfig.sp(38); height: BarConfig.sp(22); radius: BarConfig.sp(11)
                    color: Network.wifiRadioOn ? Colors.primary : Colors.surfaceContainerHigh
                    border.color: Network.wifiRadioOn ? Colors.primary : Colors.outline; border.width: 1
                    Behavior on color { ColorAnimation { duration: 150 } }
                    Rectangle {
                        width: BarConfig.sp(16); height: BarConfig.sp(16); radius: BarConfig.sp(8); anchors.verticalCenter: parent.verticalCenter
                        color: Network.wifiRadioOn ? Colors.colOnPrimary : Colors.outline
                        x: Network.wifiRadioOn ? parent.width - width - 3 : 3
                        Behavior on x     { NumberAnimation { duration: 180; easing.bezierCurve: Colors.spring } }
                        Behavior on color { ColorAnimation { duration: 150 } }
                    }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: Network.toggleWifi() }
                }
            }

            // ── Ethernet ───────────────────────────────────────────────
            Rectangle {
                width: parent.width; height: ethCol.implicitHeight + 20; radius: BarConfig.sp(12)
                color: Network.lanConnected ? Qt.rgba(Colors.primary.r, Colors.primary.g, Colors.primary.b, 0.10) : Colors.surfaceContainerHigh
                border.color: Network.lanConnected ? Colors.primary : Colors.popupBorder; border.width: 1
                Column {
                    id: ethCol
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: BarConfig.sp(12) }
                    spacing: BarConfig.sp(4)
                    Row {
                        spacing: BarConfig.sp(8)
                        Text { font.pixelSize: BarConfig.fsLg; font.family: "Symbols Nerd Font Mono"; color: Network.lanConnected ? Colors.primary : Colors.outline; text: ""; anchors.verticalCenter: parent.verticalCenter }
                        Text { text: Network.lanConnected ? (Network.lanInterface || "Ethernet") : "No Ethernet"; color: Colors.colOnSurface; font.pixelSize: BarConfig.fs; font.weight: Font.Medium; anchors.verticalCenter: parent.verticalCenter }
                    }
                    component LR: Row {
                        id: lr; required property string k; required property string v; visible: !!v; width: parent.width; spacing: BarConfig.sp(6)
                        Text { text: lr.k; color: Colors.colOnSurfaceVariant; font.pixelSize: BarConfig.fsSm; opacity: 0.65; width: 60 }
                        Text { text: lr.v; color: Colors.colOnSurface; font.pixelSize: BarConfig.fsSm; font.family: "monospace"; elide: Text.ElideRight; width: parent.width - 66 }
                    }
                    Column { visible: Network.lanConnected; width: parent.width; spacing: BarConfig.sp(3)
                        LR { k: "IPv4";  v: Network.lanIP }
                        LR { k: "MAC";   v: Network.lanMAC }
                        LR { k: "Speed"; v: Network.lanSpeed }
                    }
                }
            }

            // ── Scan header ────────────────────────────────────────────
            Item {
                width: parent.width; height: BarConfig.sp(20)
                Text {
                    anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                    text: root.scanning ? "SCANNING" + [".", "..", "..."][root.scanDots % 3] : "WIRELESS NETWORKS"
                    color: Colors.primary; font.pixelSize: BarConfig.fsSm; font.weight: Font.Medium; font.letterSpacing: 1; opacity: 0.8
                }
                Rectangle {
                    visible: !root.scanning && Network.wifiRadioOn
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                    width: BarConfig.sp(56); height: BarConfig.sp(18); radius: BarConfig.sp(9)
                    color: Qt.rgba(Colors.primary.r, Colors.primary.g, Colors.primary.b, 0.15)
                    border.color: Colors.primary; border.width: 1
                    Text { anchors.centerIn: parent; text: "Rescan"; color: Colors.primary; font.pixelSize: BarConfig.fsXs; font.weight: Font.Medium }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.startScan() }
                }
            }

            // WiFi off notice
            Rectangle {
                visible: !Network.wifiRadioOn; width: parent.width; height: BarConfig.sp(50); radius: BarConfig.sp(10)
                color: Colors.surfaceContainerHigh; border.color: Colors.popupBorder; border.width: 1
                Text { anchors.centerIn: parent; text: "Wi-Fi is off"; color: Colors.colOnSurfaceVariant; font.pixelSize: BarConfig.fs }
            }

            // Connect status feedback
            Rectangle {
                visible: root.connectStatus !== ""
                width: parent.width; height: BarConfig.sp(36); radius: BarConfig.sp(10)
                color: root.connectStatus === "ok"
                       ? Qt.rgba(0.2, 0.8, 0.4, 0.15)
                       : Qt.rgba(1, 0.3, 0.3, 0.15)
                border.color: root.connectStatus === "ok" ? "#34D399" : "#FF6B6B"; border.width: 1
                Text {
                    anchors.centerIn: parent
                    text: root.connectStatus === "ok" ? "✓  Connected" : "✗  Failed to connect"
                    color: root.connectStatus === "ok" ? "#34D399" : "#FF6B6B"
                    font.pixelSize: BarConfig.fsMd; font.weight: Font.Medium
                }
            }

            // Connecting spinner
            Rectangle {
                visible: root.connecting; width: parent.width; height: BarConfig.sp(36); radius: BarConfig.sp(10)
                color: Colors.surfaceContainerHigh; border.color: Colors.popupBorder; border.width: 1
                Text { anchors.centerIn: parent; text: "Connecting…"; color: Colors.primary; font.pixelSize: BarConfig.fsMd }
            }

            // ── ACTIVE network ─────────────────────────────────────────
            Column {
                visible: root.activeNetwork !== null; width: parent.width; spacing: BarConfig.sp(4)
                WifiNetworkItem {
                    wifiNet: root.activeNetwork ?? { ssid: "", signal: 0, security: "", active: true, saved: true }
                    itemMode: "active"
                    onDisconnectRequested: disconnectProc.running = true
                    onForgetRequested: { forgetProc.ssid = wifiNet.ssid; forgetProc.running = true }
                    onConnectRequested: {}
                }
            }

            // ── KNOWN NETWORKS ─────────────────────────────────────────
            Column {
                visible: root.knownNetworks.length > 0 && Network.wifiRadioOn
                width: parent.width; spacing: BarConfig.sp(4)

                Text {
                    text: "KNOWN"; color: Colors.primary; font.pixelSize: BarConfig.fsSm
                    font.weight: Font.Medium; font.letterSpacing: 1; opacity: 0.75
                }

                Column {
                    width: parent.width; spacing: BarConfig.sp(4)
                    Repeater {
                        model: root.knownNetworks
                        WifiNetworkItem {
                            required property var modelData
                            required property int index
                            wifiNet: modelData
                            itemMode: "known"
                            onConnectRequested: {
                                root.connecting = true
                                connectKnownProc.ssid = wifiNet.ssid
                                connectKnownProc.running = true
                            }
                            onForgetRequested: {
                                forgetProc.ssid = wifiNet.ssid
                                forgetProc.running = true
                            }
                            onDisconnectRequested: {}
                        }
                    }
                }
            }

            // ── NEW NETWORKS ───────────────────────────────────────────
            Column {
                visible: root.newNetworks.length > 0 && Network.wifiRadioOn
                width: parent.width; spacing: BarConfig.sp(4)

                Text {
                    text: "NEW"; color: Colors.primary; font.pixelSize: BarConfig.fsSm
                    font.weight: Font.Medium; font.letterSpacing: 1; opacity: 0.75
                }

                Column {
                    width: parent.width; spacing: BarConfig.sp(4)
                    Repeater {
                        model: root.newNetworks
                        WifiNetworkItem {
                            required property var modelData
                            required property int index
                            wifiNet: modelData
                            itemMode: "new"
                            onConnectRequested: {
                                const isOpen = !wifiNet.security || wifiNet.security === ""
                                if (isOpen) {
                                    root.connecting = true
                                    connectProc.ssid = wifiNet.ssid
                                    connectProc.password = ""
                                    connectProc.running = true
                                } else {
                                    root.pendingSsid = wifiNet.ssid
                                    root.passInput = ""
                                    root.showPassDialog = true
                                }
                            }
                            onForgetRequested: {}
                            onDisconnectRequested: {}
                        }
                    }
                }
            }

            // No networks found
            Rectangle {
                visible: root.networks.length === 0 && !root.scanning && Network.wifiRadioOn
                width: parent.width; height: BarConfig.sp(44); radius: BarConfig.sp(10)
                color: Colors.surfaceContainerHigh; border.color: Colors.popupBorder; border.width: 1
                Text { anchors.centerIn: parent; text: "No networks found"; color: Colors.colOnSurfaceVariant; font.pixelSize: BarConfig.fs }
            }

            Item { height: BarConfig.sp(8) }
        }
    }

    // ── Password dialog ───────────────────────────────────────────────────
    Rectangle {
        id: passDialog
        visible: root.showPassDialog
        anchors.fill: parent; radius: BarConfig.sp(14); color: Colors.popupBg; z: 10
        MouseArea { anchors.fill: parent; onClicked: {} }

        Column {
            anchors.centerIn: parent; width: parent.width - 48; spacing: BarConfig.sp(16)

            Column {
                anchors.horizontalCenter: parent.horizontalCenter; spacing: BarConfig.sp(4)
                Text { anchors.horizontalCenter: parent.horizontalCenter; text: "Connect to"; color: Colors.colOnSurfaceVariant; font.pixelSize: BarConfig.fsMd }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter; text: root.pendingSsid
                    color: Colors.colOnSurface; font.pixelSize: BarConfig.fsLg; font.weight: Font.Medium
                    elide: Text.ElideRight; width: parent.width; horizontalAlignment: Text.AlignHCenter
                }
            }

            Rectangle {
                width: parent.width; height: BarConfig.sp(42); radius: BarConfig.sp(8)
                color: Colors.surfaceContainerHigh
                border.color: passField.activeFocus ? Colors.primary : Colors.outline; border.width: 1
                TapHandler { onTapped: passField.forceActiveFocus() }
                TextInput {
                    id: passField
                    anchors { fill: parent; leftMargin: BarConfig.sp(12); rightMargin: BarConfig.sp(36); topMargin: BarConfig.sp(2); bottomMargin: BarConfig.sp(2) }
                    verticalAlignment: TextInput.AlignVCenter
                    color: Colors.colOnSurface; font.pixelSize: BarConfig.fsMd
                    echoMode: showPw.checked ? TextInput.Normal : TextInput.Password
                    selectByMouse: true; focus: root.showPassDialog
                    onTextChanged: root.passInput = text
                    Keys.onReturnPressed: doConnect()
                    Keys.onEscapePressed: { root.showPassDialog = false; passField.text = "" }
                    Text { anchors.fill: parent; text: "Password"; color: Colors.colOnSurfaceVariant; font.pixelSize: BarConfig.fsMd; verticalAlignment: Text.AlignVCenter; visible: passField.text.length === 0; opacity: 0.5 }
                }
                // Show/hide password toggle
                Rectangle {
                    id: showPw
                    property bool checked: false
                    anchors { right: parent.right; rightMargin: BarConfig.sp(8); verticalCenter: parent.verticalCenter }
                    width: BarConfig.sp(22); height: BarConfig.sp(22); radius: BarConfig.sp(4); color: checked ? Qt.rgba(Colors.primary.r, Colors.primary.g, Colors.primary.b, 0.2) : "transparent"
                    Text { anchors.centerIn: parent; text: "👁"; font.pixelSize: BarConfig.fs }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: showPw.checked = !showPw.checked }
                }
            }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter; spacing: BarConfig.sp(10)
                Rectangle {
                    width: 90; height: 34; radius: 10; color: Colors.surfaceContainerHigh; border.color: Colors.popupBorder; border.width: 1
                    Text { anchors.centerIn: parent; text: "Cancel"; color: Colors.colOnSurface; font.pixelSize: BarConfig.fs }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { root.showPassDialog = false; passField.text = "" } }
                }
                Rectangle {
                    width: BarConfig.sp(90); height: BarConfig.sp(34); radius: BarConfig.sp(10)
                    color: Qt.rgba(Colors.primary.r, Colors.primary.g, Colors.primary.b, 0.18)
                    border.color: Colors.primary; border.width: 1
                    Text { anchors.centerIn: parent; text: "Connect"; color: Colors.primary; font.pixelSize: BarConfig.fs; font.weight: Font.Medium }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: doConnect() }
                }
            }
        }

        function doConnect() {
            root.showPassDialog = false
            passField.text = ""
            if (root.passInput.length > 0) {
                root.connecting = true
                connectProc.ssid = root.pendingSsid
                connectProc.password = root.passInput
                connectProc.running = true
            }
        }
    }

    // ── Init ──────────────────────────────────────────────────────────────
    Component.onCompleted: {
        root.refreshDetails()
        root.loadAll()
        root.startScan()
    }
    Component.onDestruction: {
        rescanProc.running = false
        listProc.running   = false
    }

    Rectangle {
        visible: flick.contentHeight > flick.height
        anchors.right: parent.right; anchors.rightMargin: BarConfig.sp(4)
        readonly property real _r: BarConfig.sp(14)
        readonly property real _thumbH: flick.visibleArea.heightRatio * flick.height
        y: Math.max(flick.y, Math.min(flick.y + flick.height - _thumbH - _r,
                    flick.y + flick.visibleArea.yPosition * flick.height))
        width: BarConfig.sp(3); height: _thumbH
        radius: BarConfig.sp(2); color: Colors.outline; opacity: 0.5; z: 5
    }
}
