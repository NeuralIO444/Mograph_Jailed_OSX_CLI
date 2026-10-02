/*
 * MographJailed After Effects job runner (Tier 1: writes a NEW project, never the original).
 *
 * project.extract and project.conform write a job folder:
 *   before.aep   a verified copy of your project (the only project this script opens)
 *   plan.json    what will be done, item by item, with the value each item must still have
 *   run.jsx      this runner with the plan embedded as MJ_PLAN
 * Run run.jsx in After Effects (File > Scripts > Run Script File, or `mj ae run <job>`). It
 *   1. asks After Effects to close the open project (you are offered the usual Save dialog),
 *   2. opens before.aep from the job folder and checks it is that file,
 *   3. applies the plan; a step is skipped, never forced, when its item no longer matches,
 *   4. saves the result as a NEW file (result.aep, refused if it exists) and closes it unsaved,
 *   5. writes result.json beside it. Check it with `mj ae verify <job>` (project.jobcheck).
 * Your original .aep is never opened. A CI guard (scripts/check-job-runner.sh) keeps it that way:
 * it opens only the job copy and saves only the new result file; no shell, no dynamic code.
 * ExtendScript (ES3): no JSON object, no Array.prototype.indexOf.
 */
(function () {
    var P = (typeof MJ_PLAN !== "undefined") ? MJ_PLAN : null;
    var RUNNER_VERSION = "1.0";
    var log = { applied: 0, skipped: [], errors: [], steps: 0 };

    function mj_hex4(n) {
        var h = "0123456789abcdef";
        return h.charAt((n >> 12) & 15) + h.charAt((n >> 8) & 15) + h.charAt((n >> 4) & 15) + h.charAt(n & 15);
    }
    function mj_escape(s) {
        var out = [], i, c, code;
        for (i = 0; i < s.length; i++) {
            c = s.charAt(i); code = s.charCodeAt(i);
            if (c === '"') { out.push('\\"'); }
            else if (c === '\\') { out.push('\\\\'); }
            else if (code < 32 || code > 126) { out.push('\\u' + mj_hex4(code)); }
            else { out.push(c); }
        }
        return out.join("");
    }
    function mj_json(v) {
        var t = typeof v, i, parts, k;
        if (v === null || v === undefined) { return "null"; }
        if (t === "string") { return '"' + mj_escape(v) + '"'; }
        if (t === "number") { return isFinite(v) ? String(v) : "null"; }
        if (t === "boolean") { return v ? "true" : "false"; }
        if (v instanceof Array) {
            parts = [];
            for (i = 0; i < v.length; i++) { parts.push(mj_json(v[i])); }
            return "[" + parts.join(",") + "]";
        }
        parts = [];
        for (k in v) { if (v.hasOwnProperty(k)) { parts.push('"' + mj_escape(k) + '":' + mj_json(v[k])); } }
        return "{" + parts.join(",") + "}";
    }
    function pad(n) { return (n < 10 ? "0" : "") + n; }
    function isoNow() {
        var d = new Date();
        return d.getUTCFullYear() + "-" + pad(d.getUTCMonth() + 1) + "-" + pad(d.getUTCDate()) + "T" +
               pad(d.getUTCHours()) + ":" + pad(d.getUTCMinutes()) + ":" + pad(d.getUTCSeconds()) + "Z";
    }
    function skip(step, why) { log.skipped.push({ step: step, why: why }); }
    /* `mj ae run` drops a "quiet" file in the job folder: no alert at the end (nobody is there to click it). */
    var quiet = (P && P.quietFlag) ? new File(P.quietFlag).exists : false;
    function tell(msg) { if (!quiet) { alert(msg); } }

    function writeReceipt(status, extra) {
        var rec = { schema: "MJ_AE_JOB_RESULT_1", runnerVersion: RUNNER_VERSION, kind: P ? P.kind : null, label: P ? P.label : null,
                    status: status, finishedAt: isoNow(), aeVersion: String(app.version),
                    applied: log.applied, steps: log.steps, skipped: log.skipped, errors: log.errors };
        var k;
        if (extra) { for (k in extra) { if (extra.hasOwnProperty(k)) { rec[k] = extra[k]; } } }
        var receiptFile = new File(P.receipt);
        if (receiptFile.exists) { return false; }
        if (!receiptFile.open("w")) { return false; }
        receiptFile.encoding = "UTF-8";
        receiptFile.writeln(mj_json(rec));
        receiptFile.close();
        return true;
    }

    function itemsById() {
        var map = {}, i, it;
        for (i = 1; i <= app.project.numItems; i++) { it = app.project.item(i); map[String(it.id)] = it; }
        return map;
    }

    function propertyAt(layer, path) {
        var parts = String(path).split("/"), p = layer, i;
        for (i = 0; i < parts.length; i++) {
            try { p = p.property(parts[i]); } catch (e) { return null; }
            if (!p) { return null; }
        }
        return p;
    }

    function folderNamed(name) {
        var i, it;
        for (i = 1; i <= app.project.numItems; i++) {
            it = app.project.item(i);
            if (it instanceof FolderItem && it.name === name && it.parentFolder === app.project.rootFolder) { return it; }
        }
        return app.project.items.addFolder(name);
    }

    function runExtract(byId) {
        var keep = [], ids = P.extract.compIds, i, it;
        for (i = 0; i < ids.length; i++) {
            it = byId[String(ids[i])];
            log.steps++;
            if (!it || !(it instanceof CompItem)) { log.errors.push({ step: "comp " + ids[i], why: "comp not found in the copy" }); continue; }
            if (it.name !== P.extract.compNames[i]) { skip("comp " + ids[i], "name is now \"" + it.name + "\", expected \"" + P.extract.compNames[i] + "\""); }
            keep.push(it);
        }
        if (keep.length === 0 || log.errors.length > 0) { return null; }
        var before = app.project.numItems;
        app.project.reduceProject(keep);
        log.applied = keep.length;
        return { itemsBefore: before, itemsAfter: app.project.numItems };
    }

    function runConform(byId) {
        var c = P.conform, i, s, it, comp, layer, prop, cur;
        for (i = 0; i < c.layerRenames.length; i++) {
            s = c.layerRenames[i]; log.steps++;
            comp = byId[String(s.compId)];
            if (!(comp instanceof CompItem) || s.index > comp.numLayers) { skip("layer " + s.compId + ":" + s.index, "layer not found"); continue; }
            layer = comp.layer(s.index);
            if (layer.name !== s.from) { skip("layer " + s.from, "name is now \"" + layer.name + "\""); continue; }
            try { layer.name = s.to; log.applied++; } catch (e1) { log.errors.push({ step: "layer " + s.from, why: String(e1) }); }
        }
        for (i = 0; i < c.itemRenames.length; i++) {
            s = c.itemRenames[i]; log.steps++;
            it = byId[String(s.id)];
            if (!it) { skip("item " + s.from, "item not found"); continue; }
            if (it.name !== s.from) { skip("item " + s.from, "name is now \"" + it.name + "\""); continue; }
            try { it.name = s.to; log.applied++; } catch (e2) { log.errors.push({ step: "item " + s.from, why: String(e2) }); }
        }
        for (i = 0; i < c.expressions.length; i++) {
            s = c.expressions[i]; log.steps++;
            comp = byId[String(s.compId)];
            if (!(comp instanceof CompItem) || s.index > comp.numLayers) { skip("expression " + s.path, "layer not found"); continue; }
            prop = propertyAt(comp.layer(s.index), s.path);
            if (!prop) { skip("expression " + s.path, "property not found"); continue; }
            cur = String(prop.expression);
            if (cur === s.to) { log.applied++; continue; }            /* After Effects already followed the rename */
            if (cur !== s.from) { skip("expression " + s.path, "expression text changed since the scrape"); continue; }
            try { prop.expression = s.to; log.applied++; } catch (e3) { log.errors.push({ step: "expression " + s.path, why: String(e3) }); }
        }
        for (i = 0; i < c.layerLabels.length; i++) {
            s = c.layerLabels[i]; log.steps++;
            comp = byId[String(s.compId)];
            if (!(comp instanceof CompItem) || s.index > comp.numLayers) { skip("label " + s.compId + ":" + s.index, "layer not found"); continue; }
            layer = comp.layer(s.index);
            if (layer.label !== s.from) { skip("label " + layer.name, "label changed since the scrape"); continue; }
            try { layer.label = s.to; log.applied++; } catch (e4) { log.errors.push({ step: "label " + layer.name, why: String(e4) }); }
        }
        for (i = 0; i < c.itemLabels.length; i++) {
            s = c.itemLabels[i]; log.steps++;
            it = byId[String(s.id)];
            if (!it || it.label !== s.from) { skip("label item " + s.id, "item not found or label changed"); continue; }
            try { it.label = s.to; log.applied++; } catch (e5) { log.errors.push({ step: "label item " + s.id, why: String(e5) }); }
        }
        for (i = 0; i < c.moves.length; i++) {
            s = c.moves[i]; log.steps++;
            it = byId[String(s.id)];
            if (!it) { skip("move item " + s.id, "item not found"); continue; }
            try { it.parentFolder = folderNamed(s.to); log.applied++; } catch (e6) { log.errors.push({ step: "move item " + s.id, why: String(e6) }); }
        }
        return {};
    }

    /* ---------- main ---------- */
    if (!P || P.schema !== "MJ_AE_JOB_1") { tell("MographJailed: this script has no job plan. Run the run.jsx inside a job folder."); return; }
    var workFile = new File(P.work);
    var resultFile = new File(P.result);
    if (!workFile.exists) { tell("MographJailed: the job's copy is missing:\n" + P.work); return; }
    if (resultFile.exists || new File(P.receipt).exists) { tell("MographJailed: this job has already run (result.aep or result.json exists). Make a new job."); return; }
    try {
        if (app.preferences.getPrefAsLong("Main Pref Section", "Pref_SCRIPTING_FILE_NETWORK_SECURITY") !== 1) {
            tell("MographJailed: turn on Settings > Scripting & Expressions > Allow Scripts to Write Files and Access Network, then run this again.");
            return;
        }
    } catch (ep) {}
    if (app.project && !app.project.close(CloseOptions.PROMPT_TO_SAVE_CHANGES)) {
        tell("MographJailed: the open project was not closed, so nothing was done.");
        return;
    }
    var proj = app.open(workFile);
    if (!proj || !proj.file || proj.file.fsName !== workFile.fsName) {
        if (app.project) { app.project.close(CloseOptions.DO_NOT_SAVE_CHANGES); }
        writeReceipt("refused", { why: "After Effects did not open the job's copy" });
        tell("MographJailed: After Effects did not open the job's copy, so nothing was done.");
        return;
    }
    var extra = null;
    try {
        var byId = itemsById();
        extra = (P.kind === "extract") ? runExtract(byId) : runConform(byId);
    } catch (eRun) {
        log.errors.push({ step: "run", why: String(eRun) });
    }
    if (extra === null || (P.kind === "extract" && log.errors.length > 0)) {
        app.project.close(CloseOptions.DO_NOT_SAVE_CHANGES);
        writeReceipt("failed", null);
        tell("MographJailed: the job could not be applied; nothing was saved. See result.json in the job folder.");
        return;
    }
    app.project.save(resultFile);
    var saved = resultFile.exists;
    app.project.close(CloseOptions.DO_NOT_SAVE_CHANGES);
    if (extra) { extra.saved = saved; }
    writeReceipt(saved ? (log.errors.length ? "partial" : "done") : "failed", extra);
    tell("MographJailed " + P.kind + ": " + (saved ? "saved " + resultFile.fsName : "the result could not be saved") +
          "\n" + log.applied + " change(s) applied, " + log.skipped.length + " skipped, " + log.errors.length + " error(s).");
}());
