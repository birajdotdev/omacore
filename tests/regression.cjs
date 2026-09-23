const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const model = vm.createContext({});
vm.runInContext(fs.readFileSync('Model.js', 'utf8'), model);
assert.equal(model.levelFromFraction('2/10'), 20);
assert.equal(model.levelFromFraction('invalid'), -1);
assert.equal(model.parseStatus('broken JSON').readError, true);
assert.equal(model.parseStatus('{}').readError, true);
assert.equal(model.statusFromMap({manualNoiseCanceling: 3}).manualNoiseCancelingLevel, 3);
const schema = [{settings:[{settingId:'presetEqualizerProfile',setting:{options:['Flat','Rock'],localizedOptions:['Flat EQ','Rock EQ']}}]}];
assert.equal(model.selectOptions(schema, model.SETTING_EQ_PRESET)[1].label, 'Rock EQ');
assert.equal(model.selectOptions([], model.SETTING_EQ_PRESET).length, 0);

const timer = () => ({stop(){}, restart(){}});
const ctx = vm.createContext({Model:model, connected:true, discoveredMac:'test-mac', setScript:'set',
  spatialAudioSupported:true, spatialAudioModeSupported:true, eqOptions:[{value:'Flat'}],
  _actionQueue:[], queuedActions:0, _pendingWrites:{}, _pendingMode:'', _windNoisePending:false,
  statusProcess:{running:false}, actionProcess:{running:false},
  settleTimer:timer(), windNoiseSettleTimer:timer(), pendingSettleTimer:timer(),
  actionStatusTimer:timer(), actionWatchdog:timer(), actionStatus:'',
  lastError:'', statusStale:false, leftLowNotified:false, rightLowNotified:false, caseLowNotified:false});
ctx.root=ctx;
const service = fs.readFileSync('Service.qml','utf8');
vm.runInContext(service.match(/^  function [\s\S]*?^  }/gm).join('\n'), ctx);
ctx._notify=()=>{};
ctx.setSoundEffect('Off');
assert.equal(ctx.actionProcess.command[2], 'spatialAudio=false');
ctx.setSoundEffect('Music');
ctx.setSoundEffect('Movie');
ctx.setEqPreset('Flat');
assert.equal(ctx.queuedActions,3, 'rapid clicks must not be lost');
for (const expected of ['spatialAudioMode=Music','spatialAudioMode=Movie','presetEqualizerProfile=Flat']) {
  ctx.actionProcess.running=false;
  ctx._pumpActions();
  assert.ok(ctx.actionProcess.command.includes(expected));
  if (expected === 'presetEqualizerProfile=Flat') {
    assert.ok(ctx.actionProcess.command.includes('spatialAudio=false'), 'Default EQ disables spatial audio in the same queued command');
    assert.equal(ctx.spatialAudio, false);
  }
}
ctx.setEqPreset('unsupported');
assert.equal(ctx.queuedActions,0);
ctx.actionProcess.running=false;
ctx.statusProcess.running=true;
ctx.setSoundEffect('Off');
assert.equal(ctx.actionProcess.running,false, 'writes wait for reads');
ctx.statusProcess.running=false;
ctx._pumpActions();
assert.equal(ctx.actionProcess.running,true);
ctx._noteReadError('Read failed.');
assert.equal(ctx.connected,true, 'read failure preserves connection state');
assert.equal(ctx.statusStale,true);
ctx._noteDisconnected('Disconnected');
assert.equal(ctx.connected,false);
assert.equal(ctx.queuedActions,0);

// Exercise discovery and errors with fake executables; no Bluetooth writes.
const dir=fs.mkdtempSync(path.join(os.tmpdir(),'omacore-tests-'));
try {
  fs.writeFileSync(path.join(dir,'bluetoothctl'),'#!/bin/sh\nprintf "Device AA:BB:CC:DD:EE:FF soundcore test\\n"\n',{mode:0o755});
  fs.writeFileSync(path.join(dir,'openscq30'),`#!/bin/sh
case "$*" in
  'paired-devices list --json') echo '[{"macAddress":"AA:BB:CC:DD:EE:FF","model":"Test"}]' ;;
  *list-settings*)
    [ "$TEST_CASE" = schema_failure ] && exit 1
    echo '[{"categoryId":"soundModes","settings":[{"settingId":"manualNoiseCanceling","type":"i32Range"}]}]' ;;
  *setting*)
    [ "$TEST_CASE" = read_failure ] && exit 1
    [ "$TEST_CASE" = malformed ] && { echo '{}'; exit 0; }
    case "$*" in *'--get manualNoiseCanceling'*) echo '[{"settingId":"manualNoiseCanceling","value":{"value":3}}]' ;; *) exit 2 ;; esac ;;
esac
`,{mode:0o755});
  for (const scenario of ['ok','schema_failure','read_failure','malformed']) {
    const result=spawnSync('bash',['omacore-status'],{encoding:'utf8',env:{...process.env,PATH:dir+':'+process.env.PATH,TEST_CASE:scenario}});
    assert.equal(result.status,0,result.stderr);
    const status=JSON.parse(result.stdout);
    if(scenario==='ok') assert.equal(status.values.manualNoiseCanceling,3);
    else assert.equal(status.readError,true,scenario);
  }
} finally {fs.rmSync(dir,{recursive:true,force:true});}
console.log('Regression checks passed: model, queued writes, read errors, numeric ANC settings.');
