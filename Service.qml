import QtQuick
import Quickshell
import Quickshell.Io

// Headless service: keeps newly opened windows floating while the navbar
// switch is on. Native titlebars are rendered by Hyprland's official
// hyprbars plugin, never by a separate Quickshell surface.
Item {
  id: service
  property var shell: null
  readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME") !== ""
    ? Quickshell.env("XDG_CONFIG_HOME") : Quickshell.env("HOME") + "/.config"
  readonly property string helper: configHome
    + "/omarchy/plugins/io.github.rawritude.floating-mode/bin/floating-mode"
  readonly property string supervisor: configHome
    + "/omarchy/plugins/io.github.rawritude.floating-mode/bin/floating-mode-run"

  Process {
    id: syncProc
    command: [service.supervisor, "8", "65536", "65536", "--", service.helper, "sync"]
  }

  Timer {
    // Creation-time Hyprland rules handle normal window opens immediately.
    // This slower pass is only a repair loop for unusual mapping races.
    interval: 3000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: if (!syncProc.running) syncProc.running = true
  }
}
