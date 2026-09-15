import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

// Headless service: keeps newly opened windows floating while the navbar
// switch is on. Native titlebars are rendered by Hyprland's official
// hyprbars plugin, never by a separate Quickshell surface.
Item {
  id: service
  property var shell: null
  property bool syncPending: false
  readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME") !== ""
    ? Quickshell.env("XDG_CONFIG_HOME") : Quickshell.env("HOME") + "/.config"
  readonly property string helper: configHome
    + "/omarchy/plugins/io.github.rawritude.floating-mode/bin/floating-mode"
  readonly property string supervisor: configHome
    + "/omarchy/plugins/io.github.rawritude.floating-mode/bin/floating-mode-run"

  Process {
    id: setupProc
    command: [service.configHome + "/omarchy/plugins/io.github.rawritude.floating-mode/bin/floating-mode-setup", "auto"]
    running: true
    onExited: function(code) {
      if (code === 75) setupRetryTimer.start()
    }
  }

  Timer {
    id: setupRetryTimer
    interval: 30000
    onTriggered: { if (!setupProc.running) setupProc.running = true }
  }

  Process {
    id: syncProc
    command: [service.supervisor, "8", "65536", "65536", "--", service.helper, "sync"]
    onExited: {
      if (service.syncPending) {
        service.syncPending = false
        syncProc.running = true
      }
    }
  }

  function requestSync() {
    if (syncProc.running) service.syncPending = true
    else syncProc.running = true
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      var name = String(event && event.name ? event.name : "")
      if (name === "workspace" || name === "workspacev2" || name === "focusedmon")
        service.requestSync()
    }
  }

  Timer {
    // Creation-time Hyprland rules handle normal window opens immediately.
    // This slower pass is only a repair loop for unusual mapping races.
    interval: 3000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: service.requestSync()
  }
}
