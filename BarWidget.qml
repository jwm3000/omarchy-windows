import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "io.github.jwm.floating-mode"

  property bool floatingMode: false
  property bool focusBorderEnabled: true
  property bool busy: false
  property bool focusBorderBusy: false
  property bool settingsOpen: false
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
    if (!focusBorderStatusProc.running) focusBorderStatusProc.running = true
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

  function close() {
    settingsOpen = false
  }

  function toggleFocusBorder() {
    if (focusBorderActionProc.running) return
    focusBorderBusy = true
    lastError = ""
    focusBorderActionProc.command = [
      root.helper,
      root.focusBorderEnabled ? "focus-border-off" : "focus-border-on"
    ]
    focusBorderActionProc.running = true
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
    id: focusBorderStatusProc
    command: [root.helper, "focus-border-status"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.focusBorderEnabled = String(text || "").trim() === "on"
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

  Process {
    id: focusBorderActionProc
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.lastError = String(text || "").trim()
    }
    onExited: function(code) {
      root.focusBorderBusy = false
      if (code !== 0 && root.lastError === "") root.lastError = "Could not change focus border"
      if (focusBorderStatusProc.running) focusBorderStatusProc.running = false
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
      : (root.floatingMode
          ? "Floating mode ON — click to tile · right-click for settings"
          : "Floating mode OFF — click to float · right-click for settings")
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) root.settingsOpen = !root.settingsOpen
      else if (buttonCode === Qt.LeftButton) root.toggleMode()
    }
  }

  PopupCard {
    id: settingsPopup
    anchorItem: root
    bar: root.bar
    owner: root
    open: root.settingsOpen
    contentWidth: settingsPopup.fittedContentWidth(Style.space(280))
    contentHeight: settingsPopup.fittedContentHeight(settingsColumn.implicitHeight)

    Column {
      id: settingsColumn
      anchors.fill: parent
      spacing: Style.space(8)

      Text {
        text: "Floating Mode"
        color: root.bar.foreground
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.subtitle
        font.bold: true
      }

      Toggle {
        width: parent.width
        label: "Fokusrahmen"
        description: root.focusBorderEnabled
          ? "Aktives Fenster behält seine Fokusfarbe"
          : "Aktives Fenster nutzt die inaktive Rahmenfarbe"
        checked: root.focusBorderEnabled
        foreground: root.bar.foreground
        accent: Color.accent
        fontFamily: root.bar.fontFamily
        enabled: !root.focusBorderBusy
        opacity: enabled ? 1.0 : 0.55
        onClicked: root.toggleFocusBorder()
      }
    }
  }
}
