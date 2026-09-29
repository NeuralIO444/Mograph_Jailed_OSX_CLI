const fs = require('fs');
const vm = require('vm');
const cp = require('child_process');
const path = require('path');
const clientPath = path.join(__dirname, '..', 'integrations', 'after-effects', 'MographJailed_Client.jsxinc');
const code = fs.readFileSync(clientPath, 'utf8');
function DummyFile(p){ this.fsName=p; this.exists=true; this.parent={parent:{parent:{fsName:'/root'}}}; }
const ctx = {
  File: DummyFile,
  Folder: {temp:{fsName:'/tmp'}},
  $: {fileName:'/root/integrations/after-effects/client.jsxinc'},
  system: {callSystem:()=>''},
  JSON: JSON,
  Date: Date,
  Math: Math,
  Error: Error,
  String: String
};
ctx.this = ctx;
vm.createContext(ctx);
vm.runInContext(code, ctx);
let pass=0, fail=0;
function check(name, cond){ if(cond){pass++;} else {fail++; console.error('FAIL:',name);} }
const I=ctx.MJNativeInternals;
check('base64 ascii', I.base64Utf8('abc')==='YWJj');
check('base64 unicode', I.base64Utf8('雪')===Buffer.from('雪','utf8').toString('base64'));
check('base64 emoji', I.base64Utf8('A😀B')===Buffer.from('A😀B','utf8').toString('base64'));
const q=I.shellQuote("/tmp/a b'c;$(touch X)");
check('shell quote wraps', q[0]==="'" && q[q.length-1]==="'");
check('shell quote escapes apostrophe', q.indexOf("'\\''")>=0);
const original = "/tmp/a b'c;$(touch X)";
const shellRoundTrip = cp.execFileSync('/bin/bash', ['-lc', 'printf %s ' + I.shellQuote(original)], {encoding:'utf8'});
check('shell quote round trip', shellRoundTrip===original);
const good=I.parseResponse('{"protocol":"MOGRAPHJAILED","protocolVersion":1,"ok":true,"data":{},"requestId":"x","command":"system.probe","warnings":[],"error":null}');
check('parse response', good.ok===true && good.protocol==='MOGRAPHJAILED');
let bad=false; try{I.parseResponse('{"protocol":"OTHER","protocolVersion":1,"ok":true}');}catch(e){bad=true;}
check('reject bad envelope',bad);
check('no Finder automation', code.indexOf('System Events')<0 && code.indexOf('tell application')<0);
check('fixed shell', code.indexOf('/bin/zsh -f ')>=0);
check('allowlisted command accepted', I.isAllowedCommand('system.probe')===true);
check('raw shell command rejected by client', I.isAllowedCommand('shell.execute')===false);
check('control characters detected', I.hasProtocolControl('a\nb')===true);
check('bounded default media path', code.indexOf('inspectMediaReadOnly')>=0 && code.indexOf('verification: "size+mtime"')>=0);
console.log(`M4 static tests: ${pass} passed, ${fail} failed`);
process.exit(fail?1:0);
