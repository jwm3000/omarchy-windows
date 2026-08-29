import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "io.github.rawritude.floating-mode"

  property bool floatingMode: false
  property bool focusBorderEnabled: true
  property bool transparencyEnabled: true
  property string leftSnapMode: "quarter"
  property string rightSnapMode: "quarter"
  property bool snapGapsEnabled: true
  property bool busy: false
  property bool focusBorderBusy: false
  property bool transparencyBusy: false
  property bool snapBusy: false
  property bool settingsOpen: false
  property string lastError: ""
  readonly property string windowGlyph: String.fromCodePoint(0xF05B2)
  readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME") !== ""
    ? Quickshell.env("XDG_CONFIG_HOME") : Quickshell.env("HOME") + "/.config"
  readonly property string helper: configHome
    + "/omarchy/plugins/io.github.rawritude.floating-mode/bin/floating-mode"
  readonly property string sessionLocale: {
    var locale = Quickshell.env("LANGUAGE")
    if (locale === "") locale = Quickshell.env("LC_ALL")
    if (locale === "") locale = Quickshell.env("LC_MESSAGES")
    if (locale === "") locale = Quickshell.env("LANG")
    return String(locale || "en").toLowerCase()
  }
  readonly property bool german: sessionLocale.indexOf("de") === 0

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function refresh() {
    if (!statusProc.running) statusProc.running = true
    if (!focusBorderStatusProc.running) focusBorderStatusProc.running = true
    if (!transparencyStatusProc.running) transparencyStatusProc.running = true
    if (!leftSnapStatusProc.running) leftSnapStatusProc.running = true
    if (!rightSnapStatusProc.running) rightSnapStatusProc.running = true
    if (!snapGapsStatusProc.running) snapGapsStatusProc.running = true
  }

  function localized(de, en) {
    return german ? de : en
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

  function toggleTransparency() {
    if (transparencyActionProc.running) return
    transparencyBusy = true
    lastError = ""
    transparencyActionProc.command = [
      root.helper,
      root.transparencyEnabled ? "transparency-off" : "transparency-on"
    ]
    transparencyActionProc.running = true
  }

  function setSnapMode(side, mode) {
    if (snapActionProc.running) return
    snapBusy = true
    lastError = ""
    snapActionProc.command = [root.helper, "snap-" + side + "-" + mode]
    snapActionProc.running = true
  }

  function toggleSnapGaps() {
    if (snapActionProc.running) return
    snapBusy = true
    lastError = ""
    snapActionProc.command = [
      root.helper,
      root.snapGapsEnabled ? "snap-gaps-off" : "snap-gaps-on"
    ]
    snapActionProc.running = true
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
    id: transparencyStatusProc
    command: [root.helper, "transparency-status"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.transparencyEnabled = String(text || "").trim() === "on"
    }
  }

  Process {
    id: leftSnapStatusProc
    command: [root.helper, "snap-left-status"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.leftSnapMode = String(text || "").trim() === "half" ? "half" : "quarter"
    }
  }

  Process {
    id: rightSnapStatusProc
    command: [root.helper, "snap-right-status"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.rightSnapMode = String(text || "").trim() === "half" ? "half" : "quarter"
    }
  }

  Process {
    id: snapGapsStatusProc
    command: [root.helper, "snap-gaps-status"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.snapGapsEnabled = String(text || "").trim() === "on"
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
      if (code !== 0 && root.lastError === "")
        root.lastError = root.localized("Fenstermodus konnte nicht geändert werden", "Could not change window mode")
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
      if (code !== 0 && root.lastError === "")
        root.lastError = root.localized("Fokusrahmen konnte nicht geändert werden", "Could not change focus border")
      if (focusBorderStatusProc.running) focusBorderStatusProc.running = false
      Qt.callLater(root.refresh)
    }
  }

  Process {
    id: transparencyActionProc
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.lastError = String(text || "").trim()
    }
    onExited: function(code) {
      root.transparencyBusy = false
      if (code !== 0 && root.lastError === "")
        root.lastError = root.localized("Transparenz konnte nicht geändert werden", "Could not change transparency")
      if (transparencyStatusProc.running) transparencyStatusProc.running = false
      Qt.callLater(root.refresh)
    }
  }

  Process {
    id: snapActionProc
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.lastError = String(text || "").trim()
    }
    onExited: function(code) {
      root.snapBusy = false
      if (code !== 0 && root.lastError === "")
        root.lastError = root.localized("Snap-Einstellung konnte nicht geändert werden", "Could not change snap setting")
      if (leftSnapStatusProc.running) leftSnapStatusProc.running = false
      if (rightSnapStatusProc.running) rightSnapStatusProc.running = false
      if (snapGapsStatusProc.running) snapGapsStatusProc.running = false
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
          ? root.localized("Floating Mode AN — Klick für Kacheln · Rechtsklick für Einstellungen", "Floating Mode ON — click to tile · right-click for settings")
          : root.localized("Floating Mode AUS — Klick für freie Fenster · Rechtsklick für Einstellungen", "Floating Mode OFF — click to float · right-click for settings"))
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
    contentWidth: settingsPopup.fittedContentWidth(Style.space(340))
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
        label: root.localized("Fokusrahmen", "Focus border")
        description: root.focusBorderEnabled
          ? root.localized("Aktives Fenster behält seine Fokusfarbe", "Active window keeps its focus color")
          : root.localized("Aktives Fenster nutzt die inaktive Rahmenfarbe", "Active window uses the inactive border color")
        checked: root.focusBorderEnabled
        foreground: root.bar.foreground
        accent: Color.accent
        fontFamily: root.bar.fontFamily
        enabled: !root.focusBorderBusy
        opacity: enabled ? 1.0 : 0.55
        onClicked: root.toggleFocusBorder()
      }

      Toggle {
        width: parent.width
        label: root.localized("Transparenz", "Transparency")
        description: root.transparencyEnabled
          ? root.localized("Wie im normalen Kachelmodus", "Same as normal tiling mode")
          : root.localized("Alle Fenster vollständig deckend", "All windows fully opaque")
        checked: root.transparencyEnabled
        foreground: root.bar.foreground
        accent: Color.accent
        fontFamily: root.bar.fontFamily
        enabled: !root.transparencyBusy
        opacity: enabled ? 1.0 : 0.55
        onClicked: root.toggleTransparency()
      }

      PanelSeparator {
        foreground: root.bar.foreground
      }

      Text {
        text: root.localized("Fenster-Snap", "Window snap")
        color: root.bar.foreground
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.subtitle
        font.bold: true
      }

      Toggle {
        width: parent.width
        label: root.localized("Abstände", "Gaps")
        description: root.snapGapsEnabled
          ? root.localized("Abstände zwischen eingerasteten Fenstern", "Spacing between snapped windows")
          : root.localized("Eingerastete Fenster nutzen den ganzen Platz", "Snapped windows use all available space")
        checked: root.snapGapsEnabled
        foreground: root.bar.foreground
        accent: Color.accent
        fontFamily: root.bar.fontFamily
        enabled: !root.snapBusy
        opacity: enabled ? 1.0 : 0.55
        onClicked: root.toggleSnapGaps()
      }

      Text {
        text: root.localized("Linker Bildschirmrand", "Left screen edge")
        color: root.bar.foreground
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.caption
      }

      ButtonGroup {
        options: [
          { value: "quarter", label: root.localized("Viertel", "Quarters") },
          { value: "half", label: root.localized("Hälfte", "Half") }
        ]
        value: root.leftSnapMode
        foreground: root.bar.foreground
        background: Color.background
        accent: Color.accent
        fontFamily: root.bar.fontFamily
        focusable: !root.snapBusy
        enabled: !root.snapBusy
        opacity: root.snapBusy ? 0.55 : 1.0
        onChanged: function(value) { root.setSnapMode("left", value) }
      }

      Text {
        text: root.localized("Rechter Bildschirmrand", "Right screen edge")
        color: root.bar.foreground
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.caption
      }

      ButtonGroup {
        options: [
          { value: "quarter", label: root.localized("Viertel", "Quarters") },
          { value: "half", label: root.localized("Hälfte", "Half") }
        ]
        value: root.rightSnapMode
        foreground: root.bar.foreground
        background: Color.background
        accent: Color.accent
        fontFamily: root.bar.fontFamily
        focusable: !root.snapBusy
        enabled: !root.snapBusy
        opacity: root.snapBusy ? 0.55 : 1.0
        onChanged: function(value) { root.setSnapMode("right", value) }
      }
    }
  }
}
