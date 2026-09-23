import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "Model.js" as Model

Column {
  id: editor
  required property var service
  property string cursorRow: ""
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  readonly property bool inputFocused: profileName.activeFocus
  readonly property bool popupOpen: savedProfiles.popupOpen
  readonly property real scale: service.eqSpec ? Math.pow(10, service.eqSpec.fractionDigits) : 1
  property var draftBands: service.eqBands.slice()
  property int draggingBand: -1
  property int activeBand: cursorRow.indexOf("eqband:") === 0 ? Number(cursorRow.substring(7)) : -1
  signal focusRowRequested(string name)
  signal releaseFocus()
  signal revealItem(var item)
  spacing: Style.space(8)

  function closeEditors() { savedProfiles.close(); profileName.focus = false }
  function activate(row) {
    if (row === "customsaved") savedProfiles.toggle()
    else if (row === "customname") profileName.forceActiveFocus()
    else if (row === "customsave") save()
    else if (row === "customflat") service.setCustomEqBands(service.eqBands.map(function () { return 0 }))
  }
  function save() {
    if (!service.busy && service.saveCustomEqProfile(profileName.text)) releaseFocus()
  }
  function adjust(index, direction) {
    if (service.busy || index < 0 || index >= draftBands.length) return
    var next = draftBands.slice()
    next[index] = Math.max(service.eqSpec.min, Math.min(service.eqSpec.max, next[index] + direction * scale))
    draftBands = next
    service.setCustomEqBands(next)
  }
  onCursorRowChanged: {
    if (activeBand >= 0) revealItem(eqGraph)
    else if (cursorRow === "customname") revealItem(profileName)
    else if (cursorRow === "customsave") revealItem(saveButton)
    else if (cursorRow === "customsaved") revealItem(savedProfiles)
    else if (cursorRow === "customflat") revealItem(flatButton)
  }
  Connections {
    target: editor.service
    function onEqBandsChanged() {
      if (editor.draggingBand < 0) editor.draftBands = editor.service.eqBands.slice()
    }
  }

  PanelSectionHeader { text: "CUSTOM EQ"; foreground: editor.foreground; fontFamily: editor.fontFamily }
  Dropdown {
    id: savedProfiles
    visible: editor.service.customEqOptions.length > 0
    width: parent.width
    showLabel: false
    options: editor.service.customEqOptions
    foreground: editor.foreground
    fontFamily: editor.fontFamily
    hasCursor: editor.cursorRow === "customsaved"
    enabled: !editor.service.busy
    onChanged: function (v) { editor.service.loadCustomEqProfile(v) }
    onHovered: function (h) { if (h) editor.focusRowRequested("customsaved") }
    Binding { target: savedProfiles; property: "value"; value: editor.service.customEqProfile || "Unsaved EQ" }
  }
  Item {
    id: eqGraph
    width: editor.width
    implicitHeight: Style.space(188)

    readonly property real plotLeft: Style.space(54)
    readonly property real plotRight: width - Style.space(8)
    readonly property real plotTop: Style.space(12)
    readonly property real plotBottom: height - Style.space(32)
    readonly property real plotWidth: plotRight - plotLeft
    readonly property real plotHeight: plotBottom - plotTop
    readonly property real minDb: editor.service.eqSpec ? editor.service.eqSpec.min / editor.scale : -12
    readonly property real maxDb: editor.service.eqSpec ? editor.service.eqSpec.max / editor.scale : 12

    function bandX(index) {
      var bands = editor.service.eqSpec ? editor.service.eqSpec.bandHz : []
      if (!bands.length) return plotLeft
      var minHz = Math.log(bands[0])
      var maxHz = Math.log(bands[bands.length - 1])
      return plotLeft + (Math.log(bands[index]) - minHz) / Math.max(0.0001, maxHz - minHz) * plotWidth
    }
    function bandY(value) {
      return plotBottom - ((value / editor.scale - minDb) / (maxDb - minDb)) * plotHeight
    }
    function valueAt(y) {
      var db = minDb + (plotBottom - Math.max(plotTop, Math.min(plotBottom, y))) / plotHeight * (maxDb - minDb)
      return Math.max(editor.service.eqSpec.min, Math.min(editor.service.eqSpec.max, Math.round(db * editor.scale)))
    }
    function nearestBand(x) {
      var bands = editor.service.eqSpec ? editor.service.eqSpec.bandHz : []
      if (!bands.length) return -1
      var nearest = 0
      for (var i = 1; i < bands.length; i++)
        if (Math.abs(bandX(i) - x) < Math.abs(bandX(nearest) - x)) nearest = i
      return nearest
    }
    function setDraft(index, y) {
      if (index < 0 || index >= editor.draftBands.length) return
      var next = editor.draftBands.slice()
      next[index] = valueAt(y)
      editor.draftBands = next
    }

    Canvas {
      id: graphCanvas
      anchors.fill: parent
      property color ink: editor.foreground
      onInkChanged: requestPaint()
      onWidthChanged: requestPaint()
      onHeightChanged: requestPaint()
      Connections {
        target: editor.service
        function onEqBandsChanged() { graphCanvas.requestPaint() }
      }
      Connections {
        target: editor
        function onDraftBandsChanged() { graphCanvas.requestPaint() }
        function onActiveBandChanged() { graphCanvas.requestPaint() }
      }
      onPaint: {
        var ctx = getContext("2d")
        ctx.clearRect(0, 0, width, height)
        var bands = editor.service.eqSpec ? editor.service.eqSpec.bandHz : []
        if (!bands.length || !editor.service.eqSpec) return
        var x0 = eqGraph.plotLeft, x1 = eqGraph.plotRight
        var y0 = eqGraph.plotTop, y1 = eqGraph.plotBottom
        var zero = eqGraph.bandY(0)

        ctx.font = Math.max(9, Style.font.caption) + "px " + editor.fontFamily
        ctx.textBaseline = "middle"
        ctx.textAlign = "right"
        ctx.fillStyle = Qt.alpha(editor.foreground, 0.58)
        var labels = [eqGraph.minDb, 0, eqGraph.maxDb]
        for (var g = 0; g < labels.length; g++) {
          var gy = eqGraph.bandY(labels[g] * editor.scale)
          ctx.strokeStyle = Qt.alpha(editor.foreground, g === 1 ? 0.38 : 0.15)
          ctx.lineWidth = 1
          ctx.beginPath(); ctx.moveTo(x0, gy); ctx.lineTo(x1, gy); ctx.stroke()
          ctx.fillText((labels[g] > 0 ? "+" : "") + Number(labels[g]).toFixed(editor.service.eqSpec.fractionDigits) + " dB", x0 - Style.space(4), gy)
        }

        ctx.strokeStyle = ink
        ctx.lineWidth = Style.space(2)
        ctx.lineJoin = "round"
        ctx.lineCap = "round"
        ctx.beginPath()
        for (var i = 0; i < bands.length; i++) {
          var px = eqGraph.bandX(i)
          var py = eqGraph.bandY(editor.draftBands[i] || 0)
          if (i === 0) ctx.moveTo(px, py)
          else {
            var prevX = eqGraph.bandX(i - 1)
            var prevY = eqGraph.bandY(editor.draftBands[i - 1] || 0)
            var midX = (prevX + px) / 2
            var midY = (prevY + py) / 2
            ctx.quadraticCurveTo(prevX, prevY, midX, midY)
            if (i === bands.length - 1) ctx.quadraticCurveTo(px, py, px, py)
          }
        }
        ctx.stroke()

        ctx.textAlign = "center"
        ctx.textBaseline = "top"
        for (var j = 0; j < bands.length; j++) {
          var bx = eqGraph.bandX(j)
          var by = eqGraph.bandY(editor.draftBands[j] || 0)
          var focused = editor.activeBand === j || editor.draggingBand === j
          ctx.beginPath()
          ctx.arc(bx, by, focused ? Style.space(5) : Style.space(4), 0, Math.PI * 2)
          ctx.fillStyle = focused ? ink : Qt.lighter(ink, 1.15)
          ctx.fill()
          ctx.lineWidth = Style.space(2)
          ctx.strokeStyle = "#17211e"
          ctx.stroke()
          ctx.fillStyle = Qt.alpha(ink, 0.82)
          ctx.fillText(Model.frequencyLabel(bands[j]), bx, y1 + Style.space(8))
        }
      }
    }

    MouseArea {
      anchors.fill: parent
      enabled: !editor.service.busy
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onPressed: function (mouse) {
        if (mouse.y < eqGraph.plotTop || mouse.y > eqGraph.plotBottom) return
        var index = eqGraph.nearestBand(mouse.x)
        if (index < 0) return
        editor.draggingBand = index
        editor.focusRowRequested("eqband:" + index)
        eqGraph.setDraft(index, mouse.y)
      }
      onPositionChanged: function (mouse) {
        if (editor.draggingBand >= 0) eqGraph.setDraft(editor.draggingBand, mouse.y)
      }
      onReleased: function () {
        var index = editor.draggingBand
        editor.draggingBand = -1
        if (index >= 0) editor.service.setCustomEqBands(editor.draftBands)
      }
      onCanceled: editor.draggingBand = -1
    }
  }

  RowLayout {
    width: parent.width
    spacing: Style.space(8)
    Text {
      text: editor.activeBand >= 0 && editor.activeBand < editor.draftBands.length
        ? Model.frequencyLabel(editor.service.eqSpec.bandHz[editor.activeBand]) : "Band"
      color: editor.foreground
      font.family: editor.fontFamily
      font.pixelSize: Style.font.bodySmall
      Layout.preferredWidth: Style.space(46)
    }
    Item { Layout.fillWidth: true }
    Text {
      text: editor.activeBand >= 0 && editor.activeBand < editor.draftBands.length
        ? Model.frequencyLabel(editor.service.eqSpec.bandHz[editor.activeBand]) + " · "
          + (editor.draftBands[editor.activeBand] > 0 ? "+" : "")
          + (editor.draftBands[editor.activeBand] / editor.scale).toFixed(editor.service.eqSpec.fractionDigits) + " dB"
        : "Select a band point"
      color: editor.foreground
      font.family: editor.fontFamily
      font.pixelSize: Style.font.bodySmall
    }
  }

  Button {
    id: flatButton
    text: "Reset to flat"
    foreground: editor.foreground
    fontFamily: editor.fontFamily
    hasCursor: editor.cursorRow === "customflat"
    enabled: !editor.service.busy
    onClicked: editor.activate("customflat")
    onHovered: function (h) { if (h) editor.focusRowRequested("customflat") }
  }
  TextField {
    id: profileName
    visible: editor.service.customEqProfilesSupported
    width: parent.width
    placeholderText: "Preset name"
    maximumLength: 64
    foreground: editor.foreground
    font.family: editor.fontFamily
    hasCursor: editor.cursorRow === "customname"
    onHoveredChanged: if (hovered) editor.focusRowRequested("customname")
    onActiveFocusChanged: if (activeFocus) editor.revealItem(profileName)
    onAccepted: editor.save()
    Keys.onEscapePressed: function (event) { editor.releaseFocus(); event.accepted = true }
    Keys.onTabPressed: function (event) { editor.releaseFocus(); editor.focusRowRequested("customsave"); event.accepted = true }
  }
  Button {
    id: saveButton
    visible: editor.service.customEqProfilesSupported
    text: editor.service.customEqOptions.some(function (o) { return o.value === profileName.text.trim() }) ? "Update preset" : "Save preset"
    foreground: editor.foreground
    fontFamily: editor.fontFamily
    bordered: true
    hasCursor: editor.cursorRow === "customsave"
    enabled: !editor.service.busy && profileName.text.trim().length > 0
    onClicked: editor.save()
    onHovered: function (h) { if (h) editor.focusRowRequested("customsave") }
  }
}
