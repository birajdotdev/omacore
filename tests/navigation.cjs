// Exercise the panel's navigation and keyboard targets without device writes.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const source = fs.readFileSync('Panel.qml', 'utf8');
const model = vm.createContext({});
vm.runInContext(fs.readFileSync('Model.js', 'utf8'), model);
const state = {
  homeModes: [model.MODE_NOISE_CANCELING, model.MODE_NORMAL, model.MODE_TRANSPARENCY],
  Model: model, pageScroll: {}, effectsView: false, dualView: false,
  settingsView: false, settingsDetail: '', buttonsView: false, selectedGesture: '',
  resetButtonsArmed: false, importEqArmed: false, manageHistory: false,
  deviceDropdown: {close(){}}, ncModeDropdown: {close(){}}, eqPresetDropdown: {close(){}},
  customEditor: {closeEditors(){}}, keyCatcher: {forceActiveFocus(){}},
  panelFlick: {contentY: 0, contentHeight: 1000, height: 400},
  Qt: {callLater(fn){fn();}}, pods: {
    hasEarbuds: true, buttonOptions: {leftSinglePress: [{value: 'PlayPause'}]},
    limitHighVolumeSupported: true, limitDbOptions: [], limitRateOptions: [],
    autoPowerOffSupported: true, autoPowerOffOptions: [{value: '30m'}],
    noiseCancelingModeSupported: true, windNoiseSuppressionSupported: true,
    ldacSupported: true, hostCodec: 'ldac', dualConnectionsSupported: true,
    hasButtonControls: true, eqTransferSupported: true, customEqOptions: [{value:'Test'}],
    noiseCancelingMode: model.NC_MODE_MANUAL, manualNoiseCancelingSupported: true,
    touchToneSupported: true, lowBatteryPromptSupported: true,
  },
  deviceInfoRows: [{label:'Model', value:'test'}], devicePickerVisible: false,
  ncSectionVisible: true, transparencySectionVisible: false, hasSoundEffects: true,
};
Object.defineProperty(state, 'pageKey', {get() {
  return this.effectsView ? 'effects' : this.dualView ? 'dual' : this.buttonsView
    ? 'buttons/' + this.selectedGesture : this.settingsView ? 'settings/' + this.settingsDetail : 'main';
}});
const ctx = vm.createContext(state);
for (const name of ['navigate','showEffects','showDual','showSettings','showDetail','showHighVolume','showDeviceInfo','showButtons','showGesture','goBack']) {
  const match = source.match(new RegExp('^  function ' + name + '\\([^\\n]*\\{[^\\n]*\\}\\s*$|^  function ' + name + '\\([^\\n]*\\{[\\s\\S]*?^  \\}', 'm'));
  assert.ok(match, name);
  vm.runInContext(match[0], ctx);
}
const rowBody = source.match(/readonly property var cursorRows: \{([\s\S]*?)\n  \}/)[1];
vm.runInContext('function rows() {' + rowBody + '\n}', ctx);
assert.ok(ctx.rows().includes('ncmode'));
assert.ok(ctx.rows().includes('manuallevel'));
assert.ok(ctx.rows().includes('windnoise'));
state.ncSectionVisible = false;
assert.ok(!ctx.rows().includes('ncmode'));
assert.ok(!ctx.rows().includes('windnoise'));
state.ncSectionVisible = true;
assert.ok(!ctx.rows().includes('ldac'));
ctx.showSettings(true);
assert.ok(ctx.rows().includes('detail:audio'));
assert.ok(!ctx.rows().includes('detail:noise'));
assert.ok(!ctx.rows().includes('ncmode'));
assert.ok(ctx.rows().includes('buttons'));
state.panelFlick.contentY = 120;
ctx.showDetail('preferences');
state.panelFlick.contentY = 45;
ctx.showDetail('power');
assert.deepEqual(Array.from(ctx.rows()), ['back','power:30m']);
ctx.goBack();
assert.equal(state.pageKey, 'settings/preferences');
assert.equal(state.panelFlick.contentY, 45);
ctx.goBack();
assert.equal(state.pageKey, 'settings/');
assert.equal(state.panelFlick.contentY, 120);
ctx.showButtons(true);
ctx.showGesture('leftSinglePress');
ctx.goBack();
assert.equal(state.pageKey, 'buttons/');
ctx.goBack();
assert.equal(state.pageKey, 'settings/');
ctx.showDual(true); ctx.goBack();
assert.equal(state.pageKey, 'settings/');
ctx.showDetail('info');
assert.deepEqual(Array.from(ctx.rows()), ['back']);
ctx.showDetail('transfer');
assert.deepEqual(Array.from(ctx.rows()), ['back','eqexport','eqimport']);
ctx.showDetail('audio');
assert.deepEqual(Array.from(ctx.rows()), ['back','ldac']);
ctx.showDetail('volume'); ctx.goBack();
assert.equal(state.pageKey, 'settings/preferences');
ctx.showEffects(true); ctx.goBack();
assert.equal(state.pageKey, 'main');
console.log('Navigation checks passed: parent pages, scroll restoration, keyboard targets and feature placement.');

// Hidden sections must never capture a cursor target with the same name.
vm.runInContext(source.match(/^  function findCursorItem\(parentItem, name\) \{[\s\S]*?^  \}/m)[0], ctx);
const target = {visible:true, rowName:'eqimport', children:[]};
assert.equal(ctx.findCursorItem({visible:true,children:[{visible:false,children:[{visible:true,rowName:'eqimport',children:[]}]},target]}, 'eqimport'), target);
for (const row of ['eqimport','eqexport','dualmanage','ncmode','eqpreset','device']) {
  assert.ok(source.includes('property string rowName: "' + row + '"'), 'scroll target missing: ' + row);
}
