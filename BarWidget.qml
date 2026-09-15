import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "io.github.rawritude.floating-mode"

  property string setupStatus: "checking"
  property bool floatingMode: false
  property bool modeRunning: false
  property bool focusBorderEnabled: true
  property bool transparencyEnabled: true
  property bool titlebarTransparencyEnabled: true
  property bool mouseResizeEnabled: true
  property bool allWorkspaces: true
  property string leftSnapMode: "quarter"
  property string rightSnapMode: "quarter"
  property bool snapGapsEnabled: true
  property bool busy: false
  property bool focusBorderBusy: false
  property bool transparencyBusy: false
  property bool titlebarTransparencyBusy: false
  property bool mouseResizeBusy: false
  property bool scopeBusy: false
  property bool snapBusy: false
  property bool settingsOpen: false
  property string lastError: ""
  property string modeActionError: ""
  readonly property string windowGlyph: String.fromCodePoint(0xF05B2)
  readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME") !== ""
    ? Quickshell.env("XDG_CONFIG_HOME") : Quickshell.env("HOME") + "/.config"
  readonly property string helper: configHome
    + "/omarchy/plugins/io.github.rawritude.floating-mode/bin/floating-mode"
  readonly property string supervisor: configHome
    + "/omarchy/plugins/io.github.rawritude.floating-mode/bin/floating-mode-run"
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
    if (!uiStatusProc.running) uiStatusProc.running = true
  }

  function localized(de, en) {
    return german ? de : en
  }

  function supervisedHelper(action) {
    return [root.supervisor, "10", "1048576", "65536", "--", root.helper, action]
  }

  function retrySetup() {
    if (setupRetryProc.running || setupStatus === "running") return
    setupStatus = "running"
    setupRetryProc.running = true
  }

  function toggleMode() {
    if (setupStatus !== "ready") { root.settingsOpen = true; return }

    if (actionProc.running) return
    busy = true
    lastError = ""
    modeActionError = ""
    // Toggle against the helper's atomically checked runtime marker. Basing the
    // command on floatingMode can send the wrong action when a status poll is
    // still reporting the previous state.
    actionProc.command = root.supervisedHelper("toggle")
    actionProc.running = true
  }

  function close() {
    settingsOpen = false
  }

  function toggleFocusBorder() {
    if (focusBorderActionProc.running) return
    focusBorderBusy = true
    lastError = ""
    focusBorderActionProc.command = root.supervisedHelper(
      root.focusBorderEnabled ? "focus-border-off" : "focus-border-on")
    focusBorderActionProc.running = true
  }

  function toggleTransparency() {
    if (transparencyActionProc.running) return
    transparencyBusy = true
    lastError = ""
    transparencyActionProc.command = root.supervisedHelper(
      root.transparencyEnabled ? "transparency-off" : "transparency-on")
    transparencyActionProc.running = true
  }

  function toggleTitlebarTransparency() {
    if (titlebarTransparencyActionProc.running) return
    titlebarTransparencyBusy = true
    lastError = ""
    titlebarTransparencyActionProc.command = root.supervisedHelper(
      root.titlebarTransparencyEnabled ? "titlebar-transparency-off" : "titlebar-transparency-on")
    titlebarTransparencyActionProc.running = true
  }

  function toggleMouseResize() {
    if (mouseResizeActionProc.running || floatingMode) return
    mouseResizeBusy = true
    lastError = ""
    mouseResizeActionProc.command = root.supervisedHelper(
      root.mouseResizeEnabled ? "mouse-resize-off" : "mouse-resize-on")
    mouseResizeActionProc.running = true
  }

  function toggleScope() {
    if (scopeActionProc.running) return
    scopeBusy = true
    lastError = ""
    scopeActionProc.command = root.supervisedHelper(root.allWorkspaces ? "scope-current" : "scope-all")
    scopeActionProc.running = true
  }

  function setSnapMode(side, mode) {
    if (snapActionProc.running) return
    snapBusy = true
    lastError = ""
    snapActionProc.command = root.supervisedHelper("snap-" + side + "-" + mode)
    snapActionProc.running = true
  }

  function toggleSnapGaps() {
    if (snapActionProc.running) return
    snapBusy = true
    lastError = ""
    snapActionProc.command = root.supervisedHelper(
      root.snapGapsEnabled ? "snap-gaps-off" : "snap-gaps-on")
    snapActionProc.running = true
  }

  Process {
    id: setupStatusProc
    onExited: function(code) { if (code !== 0) root.setupStatus = "unavailable" }
    command: [root.configHome + "/omarchy/plugins/io.github.rawritude.floating-mode/bin/floating-mode-setup", "status"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.setupStatus = String(text || "unavailable").trim() || "unavailable"
    }
  }

  Process {
    id: setupRetryProc
    command: [root.configHome + "/omarchy/plugins/io.github.rawritude.floating-mode/bin/floating-mode-setup", "retry"]
    onExited: { if (!setupStatusProc.running) setupStatusProc.running = true }
  }

  Timer {
    interval: 5000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: { if (!setupStatusProc.running) setupStatusProc.running = true }
  }

  Process {
    id: uiStatusProc
    command: root.supervisedHelper("ui-status")
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var state = JSON.parse(String(text || "{}"))
          root.floatingMode = state.floating === true
          root.modeRunning = state.running === true
          root.focusBorderEnabled = state.focus !== false
          root.transparencyEnabled = state.transparency !== false
          root.titlebarTransparencyEnabled = state.titlebar !== false
          root.mouseResizeEnabled = state.mouseResize !== false
          root.allWorkspaces = state.allWorkspaces !== false
          root.leftSnapMode = state.leftSnap === "half" ? "half" : "quarter"
          root.rightSnapMode = state.rightSnap === "half" ? "half" : "quarter"
          root.snapGapsEnabled = state.snapGaps !== false
        } catch (error) {
          root.lastError = root.localized("Status konnte nicht gelesen werden", "Could not read status")
        }
      }
    }
  }

  Process {
    id: actionProc
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.modeActionError = String(text || "").trim()
    }
    onExited: function(code) {
      root.busy = false
      Qt.callLater(function() {
        if (code !== 0)
          root.lastError = root.modeActionError || root.localized(
            "Fenstermodus konnte nicht geändert werden (Exitcode " + code + ")",
            "Could not change window mode (exit code " + code + ")")
      })
      // Discard any poll that started before the action and force a new read.
      if (uiStatusProc.running) uiStatusProc.running = false
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
      if (uiStatusProc.running) uiStatusProc.running = false
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
      if (uiStatusProc.running) uiStatusProc.running = false
      Qt.callLater(root.refresh)
    }
  }

  Process {
    id: titlebarTransparencyActionProc
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.lastError = String(text || "").trim()
    }
    onExited: function(code) {
      root.titlebarTransparencyBusy = false
      if (code !== 0 && root.lastError === "")
        root.lastError = root.localized("Titelleisten-Transparenz konnte nicht geändert werden", "Could not change titlebar transparency")
      if (uiStatusProc.running) uiStatusProc.running = false
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
      if (uiStatusProc.running) uiStatusProc.running = false
      Qt.callLater(root.refresh)
    }
  }


  Process {
    id: mouseResizeActionProc
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.lastError = String(text || "").trim()
    }
    onExited: function(code) {
      root.mouseResizeBusy = false
      if (code !== 0 && root.lastError === "")
        root.lastError = root.localized("Ändern der Fenstergröße konnte nicht umgeschaltet werden", "Could not toggle mouse window resizing")
      if (uiStatusProc.running) uiStatusProc.running = false
      Qt.callLater(root.refresh)
    }
  }

  Process {
    id: scopeActionProc
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.lastError = String(text || "").trim()
    }
    onExited: function(code) {
      root.scopeBusy = false
      if (code !== 0 && root.lastError === "")
        root.lastError = root.localized("Geltungsbereich konnte nicht geändert werden", "Could not change mode scope")
      if (uiStatusProc.running) uiStatusProc.running = false
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

      Text {
        width: parent.width
        visible: root.setupStatus !== "ready"
        wrapMode: Text.WordWrap
        color: root.bar.foreground
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.body
        text: root.setupStatus === "running"
          ? root.localized("Einrichtung läuft im Terminal. Bitte dort abschließen.", "Setup is running in the terminal. Please finish it there.")
          : root.setupStatus === "restart-required"
            ? root.localized("Hyprland wurde aktualisiert. Bitte ab- und wieder anmelden.", "Hyprland was updated. Please log out and back in.")
            : root.setupStatus === "unavailable" || root.setupStatus === "checking"
              ? root.localized("Einrichtung wird geprüft. Hyprland muss erreichbar sein.", "Checking setup. Hyprland must be available.")
              : root.localized("Die Einrichtung fehlt oder wurde nicht abgeschlossen.", "Setup is missing or did not complete.")
      }

      Rectangle {
        width: parent.width
        height: Style.space(34)
        visible: root.setupStatus === "required" || root.setupStatus === "failed"
        color: Color.accent
        radius: Style.space(4)
        Text {
          anchors.centerIn: parent
          text: root.localized("Setup starten / wiederholen", "Start / retry setup")
          color: Color.background
          font.family: root.bar.fontFamily
        }
        MouseArea { anchors.fill: parent; onClicked: root.retrySetup() }
      }

      Toggle {
        width: parent.width
        label: root.localized("Alle Arbeitsflächen", "All workspaces")
        description: root.allWorkspaces
          ? root.localized("Umschalten gilt für alle Arbeitsflächen", "Switching applies to all workspaces")
          : root.localized("Umschalten gilt nur für die aktuelle Arbeitsfläche", "Switching applies only to the current workspace")
        checked: root.allWorkspaces
        foreground: root.bar.foreground
        accent: Color.accent
        fontFamily: root.bar.fontFamily
        enabled: !root.scopeBusy
        opacity: enabled ? 1.0 : 0.55
        onClicked: root.toggleScope()
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
        enabled: root.floatingMode && !root.focusBorderBusy
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
        enabled: root.floatingMode && !root.transparencyBusy
        opacity: enabled ? 1.0 : 0.55
        onClicked: root.toggleTransparency()
      }

      Toggle {
        width: parent.width
        label: root.localized("Titelleisten-Transparenz", "Titlebar transparency")
        description: root.titlebarTransparencyEnabled
          ? root.localized("Titelleiste ist leicht transparent", "Titlebar is slightly transparent")
          : root.localized("Titelleiste ist vollständig deckend", "Titlebar is fully opaque")
        checked: root.titlebarTransparencyEnabled
        foreground: root.bar.foreground
        accent: Color.accent
        fontFamily: root.bar.fontFamily
        enabled: root.floatingMode && !root.titlebarTransparencyBusy
        opacity: enabled ? 1.0 : 0.55
        onClicked: root.toggleTitlebarTransparency()
      }

      Toggle {
        width: parent.width
        label: root.localized("Fenstergröße mit Maus ändern", "Resize windows with mouse")
        description: root.floatingMode
          ? root.localized("Im Floating Mode immer aktiv", "Always active in Floating Mode")
          : (root.mouseResizeEnabled
              ? root.localized("Am Fensterrand ziehen, um die Größe zu ändern", "Drag a window border to resize")
              : root.localized("Ändern am Fensterrand ist ausgeschaltet", "Border resizing is disabled"))
        checked: root.floatingMode || root.mouseResizeEnabled
        foreground: root.bar.foreground
        accent: Color.accent
        fontFamily: root.bar.fontFamily
        enabled: !root.floatingMode && !root.mouseResizeBusy
        opacity: enabled ? 1.0 : 0.55
        onClicked: root.toggleMouseResize()
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
