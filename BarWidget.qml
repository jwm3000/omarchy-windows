import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "io.github.jwm.floating-mode"

  property bool floatingMode: false
  property bool busy: false
  property string lastError: ""
  readonly property string windowGlyph: String.fromCodePoint(0xF05B2)
  readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME") !== ""
    ? Quickshell.env("XDG_CONFIG_HOME") : Quickshell.env("HOME") + "/.config"
  readonly property string helper: configHome
    + "/omarchy/plugins/io.github.jwm.floating-mode/bin/floating-mode"

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function refresh() {
    if (!statusProc.running) statusProc.running = true
  }

  function toggleMode() {
    if (actionProc.running) return
    busy = true
    lastError = ""
    // Toggle against the helper's atomically checked runtime marker. Basing the
    // command on floatingMode can send the wrong action when a status poll is
    // still reporting the previous state.
    actionProc.command = [root.helper, "toggle"]
    actionProc.running = true
  }

  Process {
    id: statusProc
    command: [root.helper, "status"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.floatingMode = String(text || "").trim() === "on"
    }
  }

  Process {
    id: actionProc
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.lastError = String(text || "").trim()
    }
    onExited: function(code) {
      root.busy = false
      if (code !== 0 && root.lastError === "") root.lastError = "Could not change window mode"
      // Discard any poll that started before the action and force a new read.
      if (statusProc.running) statusProc.running = false
      Qt.callLater(root.refresh)
    }
  }

  Timer {
    interval: 1200
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.windowGlyph
    active: root.floatingMode
    activeColor: Color.accent
    dimmed: root.busy
    tooltipText: root.lastError !== ""
      ? root.lastError
      : (root.floatingMode ? "Floating mode ON — click to tile" : "Floating mode OFF — click to float")
    onPressed: function(buttonCode) { root.toggleMode() }
  }
}
