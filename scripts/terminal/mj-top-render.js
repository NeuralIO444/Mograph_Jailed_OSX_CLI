ObjC.import('Foundation');

function readJSON(path) {
    var s = $.NSString.stringWithContentsOfFileEncodingError(path, $.NSUTF8StringEncoding, null);
    if (!s) throw new Error('Unable to read ' + path);
    return JSON.parse(s.js);
}

function repeat(ch, n) {
    var out = '';
    while (out.length < n) out += ch;
    return out.slice(0, n);
}

function pad(s, n) {
    s = String(s);
    if (s.length >= n) return s.slice(0, n);
    return s + repeat(' ', n - s.length);
}

function humanBytes(n) {
    if (n === null || n === undefined) return 'unknown';
    var units = ['B','KB','MB','GB','TB'];
    var v = Number(n), i = 0;
    while (v >= 1024 && i < units.length - 1) { v /= 1024; i++; }
    return (i === 0 ? String(Math.round(v)) : v.toFixed(v >= 100 ? 0 : 1)) + ' ' + units[i];
}

function run(argv) {
    var doctor = readJSON(argv[0]);
    var describe = readJSON(argv[1]);
    var verify = readJSON(argv[2]);
    var storage = readJSON(argv[3]);
    var mode = argv[4] || 'modern';
    var colorEnabled = argv[5] === '1';
    var cols = parseInt(argv[6] || '80', 10);
    if (!isFinite(cols)) cols = 80;
    var width = Math.max(36, Math.min(cols - 2, 96));
    var labelWidth = width >= 70 ? 24 : (width >= 50 ? 18 : 14);
    var unicode = mode === 'modern';
    var ESC = String.fromCharCode(27);
    var C = {
        reset: colorEnabled ? ESC + '[0m' : '',
        blue: colorEnabled ? ESC + '[38;2;88;166;255m' : '',
        green: colorEnabled ? ESC + '[38;2;63;185;80m' : '',
        yellow: colorEnabled ? ESC + '[38;2;210;153;34m' : '',
        red: colorEnabled ? ESC + '[38;2;248;81;73m' : '',
        cyan: colorEnabled ? ESC + '[38;2;57;197;207m' : '',
        magenta: colorEnabled ? ESC + '[38;2;188;140;255m' : '',
        dim: colorEnabled ? ESC + '[2m' : '',
        bold: colorEnabled ? ESC + '[1m' : ''
    };
    var B = unicode ? {tl:'╭',tr:'╮',bl:'╰',br:'╯',h:'─',v:'│'} : {tl:'+',tr:'+',bl:'+',br:'+',h:'-',v:'|'};
    var lines = [];
    function top(title) {
        var label = ' ' + title + ' ';
        var fill = Math.max(0, width - label.length - 2);
        lines.push(C.blue + B.tl + label + repeat(B.h, fill) + B.tr + C.reset);
    }
    function row(label, value, status) {
        var contentWidth = width - 4;
        var left = pad(label, labelWidth);
        var val = String(value);
        var maxValue = Math.max(6, contentWidth - labelWidth - 1);
        if (val.length > maxValue) val = val.slice(0, Math.max(3, maxValue - 3)) + '...';
        var color = C.cyan;
        if (status === 'ok') color = C.green;
        else if (status === 'warn') color = C.yellow;
        else if (status === 'bad') color = C.red;
        lines.push(C.blue + B.v + C.reset + ' ' + left + color + val + C.reset + repeat(' ', Math.max(0, contentWidth - left.length - val.length)) + ' ' + C.blue + B.v + C.reset);
    }
    function bottom() { lines.push(C.blue + B.bl + repeat(B.h, width - 2) + B.br + C.reset); }

    var d = doctor.data || {};
    var p = d.probe || {};
    var ops = (describe.data && describe.data.operations) || {};
    var keys = Object.keys(ops);
    var available = 0, interactive = 0, lab = 0;
    keys.forEach(function(k){ if (ops[k].available) available++; if (ops[k].interactiveSafe) interactive++; if (ops[k].state === 'LAB_GATED') lab++; });
    var ready = doctor.ok && d.ready;
    var compatible = verify.ok && verify.data && verify.data.compatible;

    top('MJ NATIVE');
    row('Status', ready ? 'READY' : 'NOT READY', ready ? 'ok' : 'bad');
    row('CLI', doctor.cliVersion || 'unknown', 'info');
    row('Protocol', String(doctor.protocolVersion || 'unknown'), 'info');
    row('macOS', (p.osVersion || 'unknown') + (p.osBuild ? ' (' + p.osBuild + ')' : ''), 'info');
    row('Architecture', p.architecture || 'unknown', 'info');
    bottom();

    top('RUNTIME');
    row('Core capabilities', d.coreCapabilities ? 'PASS' : 'FAIL', d.coreCapabilities ? 'ok' : 'bad');
    row('Runtime verify', compatible ? 'PASS' : 'FAIL', compatible ? 'ok' : 'bad');
    row('Warnings', String((doctor.warnings || []).length), (doctor.warnings || []).length ? 'warn' : 'ok');
    bottom();

    top('CAPABILITY REGISTRY');
    row('Available operations', available + '/' + keys.length, available === keys.length - lab ? 'ok' : 'warn');
    row('Interactive safe', String(interactive), 'info');
    row('Lab gated', String(lab), lab ? 'warn' : 'ok');
    bottom();

    var sd = storage.data || {};
    top('STORAGE');
    row('Project filesystem', sd.filesystem || 'unknown', sd.filesystem ? 'ok' : 'warn');
    row('Classification', sd.classification || 'unknown', sd.network ? 'warn' : 'ok');
    row('Free', humanBytes(sd.freeBytes), 'info');
    row('Readable', sd.readable ? 'YES' : 'NO', sd.readable ? 'ok' : 'bad');
    row('Writable hint', sd.writableHint ? 'YES (advisory)' : 'NO (advisory)', sd.writableHint ? 'warn' : 'bad');
    bottom();

    top('ASSET / MEDIA INTELLIGENCE');
    function opStatus(name) {
        var o = ops[name];
        if (!o) return ['UNKNOWN','warn'];
        if (o.state === 'LAB_GATED') return ['LAB','warn'];
        return [o.available ? 'READY' : 'UNAVAILABLE', o.available ? 'ok' : 'bad'];
    }
    [['Spotlight search','search.candidate'],['Provenance','file.provenance'],['Image inspect','image.inspect'],['Image derivative','image.derivative'],['Media inspect','media.inspect'],['Media timing','media.timing']].forEach(function(pair){ var s=opStatus(pair[1]); row(pair[0], s[0], s[1]); });
    bottom();

    top('SAFETY');
    row('Source mutation', 'DISABLED BY DEFAULT', 'ok');
    row('Arbitrary shell API', 'DISABLED', 'ok');
    row('Admin dependency', 'NONE', 'ok');
    row('Downloaded runtime deps', 'NONE', 'ok');
    bottom();

    lines.push(C.dim + '  mj-man terminal   mj-man commands   mj-status   mj-doctor' + C.reset);
    return lines.join('\n');
}
