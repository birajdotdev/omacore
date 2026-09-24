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
assert.equal(model.barBatteryLevel(80, 30, 90), 30);
assert.equal(model.barBatteryLevel(-1, 60, 90), 60);
assert.equal(model.barBatteryLevel(-1, -1, 70), 70);
assert.equal(model.barBatteryLevel(-1, -1, -1), -1);
assert.equal(model.codecLabel('aac'), 'AAC');
assert.equal(model.codecLabel('sbc_xq'), 'SBC XQ');
assert.equal(model.codecLabel(''), 'Unavailable');
assert.equal(model.parseCodec('{"codec":"ldac"}'), 'ldac');
assert.equal(model.parseCodec('bad'), '');
assert.equal(model.parseStatus('broken JSON').readError, true);
assert.equal(model.parseStatus('{}').readError, true);
assert.equal(model.statusFromMap({manualNoiseCanceling: 3}).manualNoiseCancelingLevel, 3);
assert.equal(model.statusFromMap({ldac:false}).ldacSupported, true);
assert.equal(model.statusFromMap({ldac:true}).ldacEnabled, true);
assert.equal(model.statusFromMap({autoPowerOff:'30m'}).autoPowerOff, '30m');
assert.equal(model.statusFromMap({autoPowerOff:'30m'}).autoPowerOffSupported, true);
assert.equal(model.statusFromMap({touchTone:true}).touchTone, true);
assert.equal(model.statusFromMap({lowBatteryPrompt:false}).lowBatteryPromptSupported, true);
assert.equal(model.statusFromMap({limitHighVolume:true,limitHighVolumeDbLimit:85,limitHighVolumeRefreshRate:'10s'}).limitDb,85);
assert.equal(model.statusFromMap({limitHighVolume:false}).limitHighVolumeSupported,true);
assert.equal(model.optionLabel([{value:'30m',label:'30 minutes'}],'30m'),'30 minutes');
const schema = [{settings:[{settingId:'presetEqualizerProfile',setting:{options:['Flat','Rock'],localizedOptions:['Flat EQ','Rock EQ']}}]}];
assert.equal(model.selectOptions(schema, model.SETTING_EQ_PRESET)[1].label, 'Rock EQ');
assert.equal(model.selectOptions([{settings:[{settingId:'autoPowerOff',setting:{options:['disabled','30m'],localizedOptions:['Disabled','30 minutes']}}]}],model.SETTING_AUTO_POWER_OFF)[1].label,'30 minutes');
const volumeSchema=[{categoryId:'limitHighVolume',settings:[
  {settingId:'limitHighVolume',type:'toggle'},
  {settingId:'limitHighVolumeDbLimit',type:'i32Range',setting:{start:75,end:100,step:5}},
  {settingId:'limitHighVolumeRefreshRate',type:'select',setting:{options:['RealTime','10s'],localizedOptions:['Real Time','10 seconds']}}
]}];
assert.equal(model.integerRangeOptions(volumeSchema,model.SETTING_LIMIT_HIGH_VOLUME_DB,' dB').length,6);
assert.equal(model.integerRangeOptions(volumeSchema,model.SETTING_LIMIT_HIGH_VOLUME_DB,' dB')[2].label,'85 dB');
const buttonSchema=[{categoryId:'buttonConfiguration',settings:[
  {settingId:'leftSinglePress',type:'optionalSelect',setting:{options:['PlayPause'],localizedOptions:['Play Pause']}},
  {settingId:'resetButtonsToDefault',type:'action'}
]}];
const buttons=model.buttonSettings(buttonSchema,{leftSinglePress:null});
assert.equal(buttons.bindings.leftSinglePress,'');
assert.equal(buttons.options.leftSinglePress[0].label,'Disabled');
assert.equal(buttons.options.leftSinglePress[1].label,'Play Pause');
assert.equal(buttons.resetSupported,true);
assert.equal(model.buttonOptions(buttonSchema,'unknown').length,0);
assert.equal(model.selectOptions([], model.SETTING_EQ_PRESET).length, 0);

const timer = () => ({stop(){}, restart(){}});
const ctx = vm.createContext({Model:model, connected:true, discoveredMac:'test-mac', setScript:'set', ldacScript:'ldac',
  updating:false,
  spatialAudioSupported:true, spatialAudioModeSupported:true, eqOptions:[{value:'Flat'}],
  ldacSupported:false, ldacEnabled:false,
  autoPowerOffSupported:false, autoPowerOff:'', autoPowerOffOptions:[],
  limitHighVolumeSupported:false, limitHighVolume:false, limitDbSupported:false, limitDb:-1, limitDbOptions:[], limitRateSupported:false, limitRate:'', limitRateOptions:[],
  buttonBindings:{}, buttonOptions:{}, buttonResetSupported:false, hasButtonControls:false,
  _actionQueue:[], queuedActions:0, _pendingWrites:{}, _pendingMode:'', _windNoisePending:false,
  statusProcess:{running:false}, actionProcess:{running:false}, transferProcess:{running:false}, deviceChoiceProcess:{running:false},
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
ctx.availableDevices=[{mac:'AA:BB:CC:DD:EE:FF',name:'soundcore test'}];
ctx.deviceMatch='';
ctx.connected=true;
ctx.discoveredMac='test-mac';
ctx.chooseDevice('not-connected');
assert.equal(ctx.deviceChoiceProcess.running,false,'picker rejects unknown devices');
ctx.chooseDevice('AA:BB:CC:DD:EE:FF');
assert.equal(ctx.deviceChoiceProcess.command.at(-1),'AA:BB:CC:DD:EE:FF');
assert.equal(ctx.connected,false,'picker blocks writes while switching');
ctx.deviceChoiceProcess.running=false;

// Custom EQ: schema-derived units, full-band writes, saved profile commands.
const eqSpec={bandHz:[100,200,400], fractionDigits:1, min:-120, max:134};
assert.equal(model.eqSpecification([{settings:[{settingId:'volumeAdjustments',type:'equalizer',setting:eqSpec}]}]).max,134);
assert.equal(model.eqSpecification([{settings:[{settingId:'volumeAdjustments',type:'equalizer',readOnly:true,setting:eqSpec}]}]),null);
assert.equal(model.normalizeEqBands([1,2],eqSpec),null);
assert.equal(model.normalizeEqBands([1,NaN,3],eqSpec),null);
assert.equal(JSON.stringify(model.normalizeEqBands([-200,0.5,200],eqSpec)), '[-120,1,134]');
assert.equal(model.frequencyLabel(12800),'12.8k');
ctx.connected=true;
ctx.discoveredMac='test-mac';
ctx.customEqSupported=true;
ctx.customEqProfilesSupported=true;
ctx.eqSpec=eqSpec;
ctx.eqBands=[0,0,0];
ctx.customEqOptions=[{value:'+Bass'}];
ctx.actionProcess.running=false;
ctx.setCustomEqBand(1,25);
assert.equal(ctx.actionProcess.command[2],'spatialAudio=false');
assert.equal(ctx.actionProcess.command[3],'volumeAdjustments=0,25,0');
assert.equal(ctx.eqPreset,'');
assert.equal(ctx._settleValue('eqBands',[0,25,0]).join(','),'0,25,0');
assert.equal('eqBands' in ctx._pendingWrites,false,'arrays settle by value');
ctx.actionProcess.running=false;
assert.equal(ctx.saveCustomEqProfile(' Evening '),true);
assert.equal(ctx.actionProcess.command.at(-1),'customEqualizerProfile=+Evening');
assert.equal(ctx.actionProcess.command.at(-2),'volumeAdjustments=0,25,0');
assert.equal(ctx.saveCustomEqProfile('   '),false);
ctx.actionProcess.running=false;
ctx.loadCustomEqProfile('+Bass');
assert.equal(ctx.actionProcess.command.at(-1),'customEqualizerProfile=\\+Bass');
ctx.actionProcess.running=false;
ctx.customEqSupported=false;
ctx.setCustomEqBands([0,0,0]);
assert.equal(ctx.actionProcess.running,false,'unsupported models must not receive custom writes');
ctx.ldacSupported=true;
ctx.ldacScript='ldac-helper';
ctx.actionProcess.running=false;
ctx.spatialAudio=true;
ctx.setLdac(true);
assert.equal(ctx.actionProcess.command.join(','),'ldac-helper,test-mac,true');
assert.equal(ctx.ldacEnabled,false,'LDAC remains off until verified readback');
assert.equal(ctx.spatialAudio,true,'the helper changes Spatial Audio only after checking device state');
ctx.actionProcess.running=false;
ctx.ldacEnabled=true;
ctx.setSoundEffect('Movie');
assert.equal(ctx.actionProcess.command[2],'ldac=false');
assert.equal(ctx.actionProcess.command[3],'spatialAudio=true');
assert.equal(ctx.actionProcess.command.at(-1),'spatialAudioMode=Movie');
assert.equal(ctx.ldacEnabled,false);
ctx.actionProcess.running=false;
ctx.ldacSupported=false;
ctx.setLdac(false);
assert.equal(ctx.actionProcess.running,false,'unsupported models must not receive LDAC writes');
ctx.autoPowerOffSupported=true;
ctx.autoPowerOffOptions=[{value:'20m',label:'20 minutes'},{value:'30m',label:'30 minutes'}];
ctx.setAutoPowerOff('invalid');
assert.equal(ctx.actionProcess.running,false,'power timer rejects values outside the device schema');
ctx.setAutoPowerOff('20m');
assert.equal(ctx.actionProcess.command.at(-1),'autoPowerOff=20m');
assert.equal(ctx.autoPowerOff,'20m');
ctx.actionProcess.running=false;
ctx.autoPowerOffSupported=false;
ctx.setAutoPowerOff('30m');
assert.equal(ctx.actionProcess.running,false,'unsupported models must not receive power timer writes');
ctx.limitHighVolumeSupported=true;
ctx.limitDbSupported=true;
ctx.limitRateSupported=true;
ctx.limitDbOptions=model.integerRangeOptions(volumeSchema,model.SETTING_LIMIT_HIGH_VOLUME_DB,' dB');
ctx.limitRateOptions=model.selectOptions(volumeSchema,model.SETTING_LIMIT_HIGH_VOLUME_RATE);
ctx.setHighVolumeLimit(true);
assert.equal(ctx.actionProcess.command.at(-1),'limitHighVolume=true');
ctx.actionProcess.running=false;
ctx.setLimitDb(87);
assert.equal(ctx.actionProcess.running,false,'volume threshold rejects values outside the device range');
ctx.setLimitDb(85);
assert.equal(ctx.actionProcess.command.at(-1),'limitHighVolumeDbLimit=85');
ctx.actionProcess.running=false;
ctx.setLimitRate('10s');
assert.equal(ctx.actionProcess.command.at(-1),'limitHighVolumeRefreshRate=10s');
ctx.actionProcess.running=false;
ctx.limitHighVolumeSupported=false;
ctx.setHighVolumeLimit(false);
assert.equal(ctx.actionProcess.running,false,'unsupported models must not receive volume limit writes');
ctx.statusStale=false;
ctx.buttonBindings={leftSinglePress:''};
ctx.buttonOptions={leftSinglePress:buttons.options.leftSinglePress};
ctx.buttonResetSupported=true;
ctx.hasButtonControls=true;
ctx.setButtonBinding('leftSinglePress','invalid');
assert.equal(ctx.actionProcess.running,false,'button controls reject values outside the schema');
ctx.setButtonBinding('leftSinglePress','PlayPause');
assert.equal(ctx.actionProcess.command.at(-1),'leftSinglePress=PlayPause');
ctx.actionProcess.running=false;
ctx.buttonBindings.leftSinglePress='PlayPause';
ctx.setButtonBinding('leftSinglePress','');
assert.equal(ctx.actionProcess.command.at(-1),'leftSinglePress=');
ctx.actionProcess.running=false;
ctx.resetButtonBindings();
assert.equal(ctx.actionProcess.command.at(-1),'resetButtonsToDefault');
ctx.actionProcess.running=false;
ctx.buttonResetSupported=false;
ctx.resetButtonBindings();
assert.equal(ctx.actionProcess.running,false,'reset must be advertised by the device');
let resetCalls=0;
const panelCtx=vm.createContext({pods:{buttonResetSupported:true,hasButtonControls:true,resetButtonBindings(){resetCalls++;}},resetButtonsArmed:false});
const panelSource=fs.readFileSync('Panel.qml','utf8');
vm.runInContext(panelSource.match(/^  function confirmResetButtons\(\) \{[\s\S]*?^  \}/m)[0],panelCtx);
panelCtx.confirmResetButtons();
assert.equal(panelCtx.resetButtonsArmed,true);
assert.equal(resetCalls,0,'reset needs a second activation');
panelCtx.confirmResetButtons();
assert.equal(resetCalls,1);
assert.equal(panelCtx.resetButtonsArmed,false);

// Exercise discovery and errors with fake executables; no Bluetooth writes.
const dir=fs.mkdtempSync(path.join(os.tmpdir(),'omacore-tests-'));
try {
  fs.writeFileSync(path.join(dir,'bluetoothctl'),'#!/bin/sh\nprintf "Device AA:BB:CC:DD:EE:FF soundcore test\\nDevice 11:22:33:44:55:66 soundcore second\\n"\n',{mode:0o755});
  fs.writeFileSync(path.join(dir,'openscq30'),`#!/bin/sh
case "$*" in
  'paired-devices list --json') echo '[{"macAddress":"AA:BB:CC:DD:EE:FF","model":"Test"},{"macAddress":"11:22:33:44:55:66","model":"Test"}]' ;;
  *list-settings*)
    [ "$TEST_CASE" = schema_failure ] && exit 1
    echo '[{"categoryId":"soundModes","settings":[{"settingId":"manualNoiseCanceling","type":"i32Range"}]},{"categoryId":"buttonConfiguration","settings":[{"settingId":"leftSinglePress","type":"optionalSelect","setting":{"options":["PlayPause"],"localizedOptions":["Play Pause"]}},{"settingId":"resetButtonsToDefault","type":"action"}]},{"categoryId":"limitHighVolume","settings":[{"settingId":"limitHighVolume","type":"toggle"},{"settingId":"limitHighVolumeDbLimit","type":"i32Range","setting":{"start":75,"end":100,"step":5}},{"settingId":"limitHighVolumeRefreshRate","type":"select","setting":{"options":["RealTime","10s"]}}]}]' ;;
  *setting*)
    [ "$TEST_CASE" = read_failure ] && exit 1
    [ "$TEST_CASE" = malformed ] && { echo '{}'; exit 0; }
    case "$*" in *'--get manualNoiseCanceling'*) echo '[{"settingId":"manualNoiseCanceling","value":{"value":3}},{"settingId":"leftSinglePress","value":{"value":null}},{"settingId":"limitHighVolume","value":{"value":false}},{"settingId":"limitHighVolumeDbLimit","value":{"value":90}},{"settingId":"limitHighVolumeRefreshRate","value":{"value":"RealTime"}}]' ;; *) exit 2 ;; esac ;;
esac
`,{mode:0o755});
  fs.writeFileSync(path.join(dir,'pactl'),`#!/bin/sh
printf '%s\\n' '[{"properties":{"api.bluez5.address":"11:22:33:44:55:66","api.bluez5.codec":"sbc"}},{"properties":{"api.bluez5.address":"AA:BB:CC:DD:EE:FF","api.bluez5.codec":"ldac"}}]'
`,{mode:0o755});
  const codec=spawnSync('bash',['omacore-codec','AA:BB:CC:DD:EE:FF'],{encoding:'utf8',env:{...process.env,PATH:dir+':'+process.env.PATH}});
  assert.equal(codec.status,0,codec.stderr);
  assert.equal(JSON.parse(codec.stdout).codec,'ldac');
  const absent=spawnSync('bash',['omacore-codec','AA:BB:CC:DD:EE:00'],{encoding:'utf8',env:{...process.env,PATH:dir+':'+process.env.PATH}});
  assert.equal(JSON.parse(absent.stdout).codec,'');
  for (const scenario of ['ok','schema_failure','read_failure','malformed']) {
    const result=spawnSync('bash',['omacore-status'],{encoding:'utf8',env:{...process.env,PATH:dir+':'+process.env.PATH,TEST_CASE:scenario}});
    assert.equal(result.status,0,result.stderr);
    const status=JSON.parse(result.stdout);
    if(scenario==='ok') {
      assert.equal(status.values.manualNoiseCanceling,3);
      assert.equal(status.values.leftSinglePress,null);
      assert.equal(status.values.limitHighVolumeDbLimit,90);
      assert.ok(status.schema.some(category=>category.categoryId==='buttonConfiguration'));
      assert.ok(status.schema.some(category=>category.categoryId==='limitHighVolume'));
      assert.equal(status.devices.length,2);
    }
    else assert.equal(status.readError,true,scenario);
  }
  for (const [match, expectedMac] of [['second','11:22:33:44:55:66'],['11:22:33','11:22:33:44:55:66'],['missing',null]]) {
    const result=spawnSync('bash',['omacore-status','--device-match',match],{encoding:'utf8',env:{...process.env,PATH:dir+':'+process.env.PATH,TEST_CASE:'ok'}});
    assert.equal(result.status,0,result.stderr);
    const status=JSON.parse(result.stdout);
    assert.equal(status.connected,expectedMac !== null);
    if(expectedMac) assert.equal(status.mac,expectedMac);
    assert.equal(status.devices.length,2);
    if(!expectedMac) assert.equal(status.preferredMissing,true);
  }
} finally {fs.rmSync(dir,{recursive:true,force:true});}
const ldacDir=fs.mkdtempSync(path.join(os.tmpdir(),'omacore-ldac-tests-'));
try {
  fs.copyFileSync('omacore-ldac',path.join(ldacDir,'omacore-ldac'));
  fs.writeFileSync(path.join(ldacDir,'sleep'),'#!/bin/sh\nexit 0\n',{mode:0o755});
  fs.writeFileSync(path.join(ldacDir,'omacore-status'),`#!/bin/sh
if [ "$LDAC_TEST_ACCEPT" = delayed ] && [ -f "$LDAC_TEST_DIR/pending" ]; then
  count=$(cat "$LDAC_TEST_DIR/count")
  count=$((count + 1))
  printf '%s' "$count" > "$LDAC_TEST_DIR/count"
  [ "$count" -ge 4 ] && { printf true > "$LDAC_TEST_DIR/ldac"; rm "$LDAC_TEST_DIR/pending"; }
fi
printf '{"connected":true,"values":{"spatialAudio":%s,"spatialAudioMode":"%s","ldac":%s}}\\n' "$(cat "$LDAC_TEST_DIR/spatial")" "$(cat "$LDAC_TEST_DIR/mode")" "$(cat "$LDAC_TEST_DIR/ldac")"
`,{mode:0o755});
  fs.writeFileSync(path.join(ldacDir,'omacore-set'),`#!/bin/sh
shift
for setting in "$@"; do
  case "$setting" in
    spatialAudio=*) printf '%s' "\${setting#*=}" > "$LDAC_TEST_DIR/spatial" ;;
    spatialAudioMode=*) printf '%s' "\${setting#*=}" > "$LDAC_TEST_DIR/mode" ;;
    ldac=*)
      if [ "$LDAC_TEST_ACCEPT" = 1 ]; then printf '%s' "\${setting#*=}" > "$LDAC_TEST_DIR/ldac"; fi
      if [ "$LDAC_TEST_ACCEPT" = delayed ]; then touch "$LDAC_TEST_DIR/pending"; fi ;;
  esac
done
exit 0
`,{mode:0o755});
  for (const accept of ['0','1','delayed']) {
    fs.writeFileSync(path.join(ldacDir,'spatial'),'true');
    fs.writeFileSync(path.join(ldacDir,'mode'),'Movie');
    fs.writeFileSync(path.join(ldacDir,'ldac'),'false');
    fs.writeFileSync(path.join(ldacDir,'count'),'0');
    const result=spawnSync('bash',[path.join(ldacDir,'omacore-ldac'),'AA:BB:CC:DD:EE:FF','true'],{
      encoding:'utf8',env:{...process.env,PATH:ldacDir+':'+process.env.PATH,LDAC_TEST_DIR:ldacDir,LDAC_TEST_ACCEPT:accept}});
    assert.equal(result.status,accept==='0'?1:0,result.stderr);
    assert.equal(fs.readFileSync(path.join(ldacDir,'spatial'),'utf8'),accept==='0'?'true':'false');
    assert.equal(fs.readFileSync(path.join(ldacDir,'mode'),'utf8'),'Movie');
    assert.equal(fs.readFileSync(path.join(ldacDir,'ldac'),'utf8'),accept==='0'?'false':'true');
  }
  // A missing/null readback must never count as a successful disable.
  for (const value of ['{}', '{"ldac":null}', '{"ldac":false}']) {
    fs.writeFileSync(path.join(ldacDir,'omacore-status'), `#!/bin/sh
printf '%s\\n' '{"connected":true,"values":${value}}'
`, {mode:0o755});
    const result = spawnSync('bash', [path.join(ldacDir,'omacore-ldac'), 'AA:BB:CC:DD:EE:FF', 'false'], {
      encoding:'utf8', env:{...process.env,PATH:ldacDir+':'+process.env.PATH,LDAC_TEST_DIR:ldacDir,LDAC_TEST_ACCEPT:'0'}});
    assert.equal(result.status, value === '{"ldac":false}' ? 0 : 1, 'LDAC requires explicit boolean readback: ' + value);
  }
} finally {fs.rmSync(ldacDir,{recursive:true,force:true});}
console.log('Regression checks passed: model, device picker, codec, LDAC, Auto Power-Off, volume limit, button controls, queued writes, read errors, numeric ANC, custom EQ and saved presets.');

assert.equal(model.batteryDisplayMode(0), 0);
assert.equal(model.batteryDisplayMode(2), 2);
assert.equal(model.batteryDisplayMode(99), 1);
assert.equal(model.barBatteryText(0, 90, 80, 100), '');
assert.equal(model.barBatteryText(1, 90, 80, 100), '80%');
assert.equal(model.barBatteryText(1, -1, -1, 60), '60%');
assert.equal(model.barBatteryText(2, 90, -1, 100), 'L 90% · R — · C 100%');
