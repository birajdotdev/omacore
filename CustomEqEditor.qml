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
    if (!service.busy) service.setCustomEqBand(index, service.eqBands[index] + direction * scale)
  }
  onCursorRowChanged: {
    if (cursorRow.indexOf("eqband:") === 0) revealItem(bandRows.itemAt(Number(cursorRow.substring(7))))
    else if (cursorRow === "customname") revealItem(profileName)
    else if (cursorRow === "customsave") revealItem(saveButton)
    else if (cursorRow === "customsaved") revealItem(savedProfiles)
    else if (cursorRow === "customflat") revealItem(flatButton)
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
  Repeater {
    id: bandRows
    model: editor.service.eqSpec ? editor.service.eqSpec.bandHz : []
    CursorSurface {
      id: bandRow
      required property int index
      required property real modelData
      width: editor.width
      implicitHeight: Style.space(24)
      foreground: editor.foreground
      hasCursor: editor.cursorRow === "eqband:" + index
      RowLayout {
        anchors.fill: parent
        spacing: Style.space(8)
        Text {
          text: Model.frequencyLabel(bandRow.modelData)
          Layout.preferredWidth: Style.space(38)
          color: editor.foreground
          font.family: editor.fontFamily
          font.pixelSize: Style.font.bodySmall
        }
        PanelSlider {
          id: bandSlider
          Layout.fillWidth: true
          minimum: editor.service.eqSpec ? editor.service.eqSpec.min : 0
          maximum: editor.service.eqSpec ? editor.service.eqSpec.max : 1
          value: editor.service.eqBands[bandRow.index] || 0
          step: editor.scale
          integer: true
          fillColor: editor.foreground
          knobColor: editor.foreground
          enabled: !editor.service.busy
          onMoved: editor.focusRowRequested("eqband:" + bandRow.index)
          onReleased: function (v) { editor.service.setCustomEqBand(bandRow.index, v) }
        }
        Text {
          Layout.preferredWidth: Style.space(57)
          horizontalAlignment: Text.AlignRight
          text: (bandSlider.liveValue / editor.scale).toFixed(editor.service.eqSpec ? editor.service.eqSpec.fractionDigits : 0) + " dB"
          color: editor.foreground
          font.family: editor.fontFamily
          font.pixelSize: Style.font.bodySmall
        }
      }
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
