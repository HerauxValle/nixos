pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import "."

// Audio service: reactive Pipewire binding with instant wpctl fallback.
// Optimistic updates give zero-latency feedback when scrolling/muting.
Singleton {
    id: root

    // ── Pipewire reactive chain ──────────────────────────────────────────
    // Properties are explicit to ensure QML tracks the dependency chain.
    property var  pwSink:  null
    property bool pwReady: pwSink !== null
                           && (pwSink.ready ?? false)
                           && pwSink.audio !== null

    Component.onCompleted: pwSink = Pipewire.defaultAudioSink

    Connections {
        target: Pipewire
        function onDefaultAudioSinkChanged() { root.pwSink = Pipewire.defaultAudioSink }
    }

    // ── Public state ─────────────────────────────────────────────────────
    readonly property real   volume:   pwReady ? pwSink.audio.volume : _wpVol
    readonly property bool   muted:    pwReady ? pwSink.audio.muted  : _wpMuted
    readonly property string sinkName: pwReady
        ? (pwSink.description || pwSink.name || "Default") : "Default"

    // ── wpctl fallback values ─────────────────────────────────────────────
    property real _wpVol:   0.0
    property bool _wpMuted: false

    // ── All sinks / sources / streams ────────────────────────────────────
    property var allSinks:   []
    property var allSources: []
    property var streams:    []

    Connections {
        target: Pipewire.nodes
        function onValuesChanged() {
            const sinks = [], sources = [], strs = []
            for (const n of Pipewire.nodes.values) {
                if (!n.audio) continue
                if (n.isStream && n.audio)  strs.push(n)
                else if (n.isSink)  sinks.push(n)
                else                sources.push(n)
            }
            root.allSinks   = sinks
            root.allSources = sources
            root.streams    = strs
        }
    }

    function setDefaultSink(sink) {
        Pipewire.preferredDefaultAudioSink = sink
    }
    function setDefaultSource(src) {
        Pipewire.preferredDefaultAudioSource = src
    }

    // ── Input (microphone) ────────────────────────────────────────────────
    readonly property var   pwSource:  Pipewire.defaultAudioSource
    readonly property bool  srcReady:  pwSource !== null && (pwSource.ready ?? false) && pwSource.audio !== null
    readonly property real  inputVol:  srcReady ? pwSource.audio.volume : 0.0
    readonly property bool  inputMuted: srcReady ? pwSource.audio.muted : false

    function setInputVolume(v) {
        if (srcReady) pwSource.audio.volume = Math.max(0, Math.min(1.5, v))
    }
    function toggleInputMute() {
        if (srcReady) pwSource.audio.muted = !pwSource.audio.muted
    }

    // ── Actions ───────────────────────────────────────────────────────────
    function setVolume(v) {
        const c = Math.max(0, Math.min(1.5, v))
        if (pwReady) {
            pwSink.audio.volume = c
        } else {
            _wpVol = c                             // optimistic
            _setProc.command = ["wpctl", "set-volume",
                                "@DEFAULT_AUDIO_SINK@", Math.round(c * 100) + "%"]
            _setProc.running = true
        }
        OsdState.showVolume(c, muted)
    }

    function changeVolume(delta) { setVolume(volume + delta) }

    function toggleMute() {
        if (pwReady) {
            pwSink.audio.muted = !pwSink.audio.muted
        } else {
            _wpMuted = !_wpMuted                   // optimistic
            _muteProc.running = true
        }
        OsdState.showVolume(volume, !muted)
    }

    // ── Processes ─────────────────────────────────────────────────────────
    Process {
        id: _getProc
        command: ["wpctl", "get-volume", "@DEFAULT_AUDIO_SINK@"]
        stdout: StdioCollector {
            onStreamFinished: {
                const m = text.trim().match(/Volume:\s*([\d.]+)(\s*\[MUTED\])?/)
                if (m) { root._wpVol = parseFloat(m[1]); root._wpMuted = !!m[2] }
            }
        }
    }
    Process { id: _setProc;  onExited: _getProc.running = true }
    Process {
        id: _muteProc
        command: ["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "toggle"]
        onExited: _getProc.running = true
    }

    // Poll wpctl quickly until Pipewire connects, then slow down
    Timer {
        interval:  root.pwReady ? 5000 : 800
        running:   !root.pwReady
        repeat:    true
        triggeredOnStart: true
        onTriggered: _getProc.running = true
    }
    // Keep volume fresh when Pipewire is live (in case another app changes it)
    Timer {
        interval: 5000
        running:  root.pwReady
        repeat:   true
        onTriggered: _getProc.running = true
    }
}
