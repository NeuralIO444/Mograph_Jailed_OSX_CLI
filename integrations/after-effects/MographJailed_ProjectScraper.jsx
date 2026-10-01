#target aftereffects
/*
 * MographJailed Project Scraper — Tier 0 (Observer)
 *
 * Walks the currently open After Effects project and emits a
 * MJ_PROJECT_SCRAPE_1 JSON document. Consumed by the CLI commands
 * project.ingest (validate + summarize) and expression.lint (static analysis).
 *
 * STRICTLY READ-ONLY: this script never saves, modifies, or deletes anything
 * in the project. The only file it writes is the JSON document it produces,
 * at a location the user picks. A CI guard (scripts/check-scraper-readonly.sh)
 * rejects any AE DOM mutation call in this file.
 *
 * Usage: in After Effects, File > Scripts > Run Script File, pick this file,
 * then choose a receipts folder when prompted.
 *
 * Bounds enforced: 200 comps max, 500 layers per comp max, expressions
 * truncated to 2000 chars, total JSON kept under ~5 MB.
 */

(function () {

    var SCRAPER_VERSION = "1.0";
    var MAX_COMPS = 200;
    var MAX_LAYERS_PER_COMP = 500;
    var MAX_EXPRESSION_CHARS = 2000;
    var MAX_FOOTAGE = 2000;
    var SIZE_BUDGET = 4750000; /* ~4.5 MB, under the ~5 MB cap */

    /* ---------- minimal JSON stringifier (ES3, no JSON object) ---------- */

    function mj_hex4(n) {
        var h = "0123456789abcdef";
        return h.charAt((n >> 12) & 15) + h.charAt((n >> 8) & 15) +
               h.charAt((n >> 4) & 15) + h.charAt(n & 15);
    }

    function mj_escape(s) {
        var out = [];
        var i, c, code;
        for (i = 0; i < s.length; i++) {
            c = s.charAt(i);
            code = s.charCodeAt(i);
            if (c === '"') { out.push('\\"'); }
            else if (c === '\\') { out.push('\\\\'); }
            else if (c === '\n') { out.push('\\n'); }
            else if (c === '\r') { out.push('\\r'); }
            else if (c === '\t') { out.push('\\t'); }
            else if (c === '\b') { out.push('\\b'); }
            else if (c === '\f') { out.push('\\f'); }
            else if (code < 32) { out.push('\\u' + mj_hex4(code)); }
            else { out.push(c); }
        }
        return out.join("");
    }

    function mj_json(v) {
        var t = typeof v;
        var i, parts, k;
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
        for (k in v) {
            if (v.hasOwnProperty(k)) {
                parts.push('"' + mj_escape(k) + '":' + mj_json(v[k]));
            }
        }
        return "{" + parts.join(",") + "}";
    }

    /* ---------- helpers ---------- */

    function mj_pad(n) { return (n < 10 ? "0" : "") + n; }

    /* UTC with a trailing Z, so it can be compared with snapshot names (also UTC) on any machine. */
    function mj_isoNow(d) {
        return d.getUTCFullYear() + "-" + mj_pad(d.getUTCMonth() + 1) + "-" + mj_pad(d.getUTCDate()) +
               "T" + mj_pad(d.getUTCHours()) + ":" + mj_pad(d.getUTCMinutes()) + ":" + mj_pad(d.getUTCSeconds()) + "Z";
    }

    function mj_fileStamp(d) {
        return d.getFullYear() + mj_pad(d.getMonth() + 1) + mj_pad(d.getDate()) +
               "-" + mj_pad(d.getHours()) + mj_pad(d.getMinutes()) + mj_pad(d.getSeconds());
    }

    function mj_layerType(layer) {
        try {
            if (layer instanceof TextLayer) { return "TextLayer"; }
            if (layer instanceof ShapeLayer) { return "ShapeLayer"; }
            if (layer instanceof CameraLayer) { return "CameraLayer"; }
            if (layer instanceof LightLayer) { return "LightLayer"; }
            if (layer instanceof AVLayer) {
                try { if (layer.nullLayer) { return "NullLayer"; } } catch (e1) {}
                return "AVLayer";
            }
        } catch (e2) {}
        return "Unknown";
    }

    function mj_bool(v) { return v ? true : false; }

    /* Examine one property: count it, note keyframes, capture expressions. */
    function mj_examineProperty(prop, path, acc) {
        var expr = "";
        acc.numProperties++;
        try { if (prop.numKeys > 0) { acc.numKeyframed++; } } catch (e1) {}
        try { expr = prop.expression; } catch (e2) { expr = ""; }
        if (expr !== null && expr !== undefined && String(expr).length > 0) {
            var text = String(expr);
            var rec = { propertyPath: path, expression: text };
            if (text.length > MAX_EXPRESSION_CHARS) {
                rec.expression = text.substring(0, MAX_EXPRESSION_CHARS);
                rec.expressionTruncated = true;
            }
            acc.expressions.push(rec);
        }
    }

    function mj_effects(layer) {
        var arr = [];
        try {
            var eg = layer.effect;
            if (eg) {
                for (var j = 1; j <= eg.numProperties; j++) {
                    var e = eg.property(j);
                    arr.push({ name: String(e.name), matchName: String(e.matchName) });
                }
            }
        } catch (ex) {}
        return arr;
    }

    function mj_scrapeLayer(layer, index, fontSeen) {
        var acc = { numProperties: 0, numKeyframed: 0, expressions: [] };
        var j, k, p, child, path;

        /* Shallow property walk: top-level properties, plus children of the
           Transform group. Groups other than Transform count as one property. */
        try {
            for (j = 1; j <= layer.numProperties; j++) {
                p = layer.property(j);
                if (p instanceof PropertyGroup &&
                    String(p.matchName).indexOf("ADBE Transform Group") === 0) {
                    for (k = 1; k <= p.numProperties; k++) {
                        child = p.property(k);
                        path = String(p.name) + "/" + String(child.name);
                        mj_examineProperty(child, path, acc);
                    }
                } else {
                    mj_examineProperty(p, String(p.name), acc);
                }
            }
        } catch (ew) {}

        /* Fonts from text layers (first character's font; per-layer, so a
           missing font can be traced to the comps and layers that use it). */
        var layerFont = "";
        if (mj_layerType(layer) === "TextLayer") {
            try {
                var td = layer.property("ADBE Text Properties")
                              .property("ADBE Text Document").value;
                var f = td.font;
                if (f !== null && f !== undefined && String(f).length > 0) {
                    layerFont = String(f);
                    fontSeen[layerFont] = true;
                }
            } catch (ef) {}
        }

        var sourceName = "";
        var sourcePath = "";
        var sourceId = 0;
        try {
            var src = layer.source;
            if (src) {
                sourceName = String(src.name);
                try { sourceId = src.id; } catch (e0) {}
                try { if (src.file) { sourcePath = String(src.file.fsName); } } catch (e1) {}
            }
        } catch (e2) {}

        var hasVideo = false, hasAudio = false;
        try { hasVideo = mj_bool(layer.hasVideo); } catch (e3) {}
        try { hasAudio = mj_bool(layer.hasAudio); } catch (e4) {}

        var markers = 0;
        try { markers = layer.marker.numKeys; } catch (e5) {}

        var rec = {
            name: String(layer.name),
            index: index,
            type: mj_layerType(layer),
            enabled: mj_bool(layer.enabled),
            solo: mj_bool(layer.solo),
            locked: mj_bool(layer.locked),
            hasVideo: hasVideo,
            hasAudio: hasAudio,
            sourceName: sourceName,
            sourcePath: sourcePath,
            sourceId: sourceId,
            font: layerFont,
            effects: mj_effects(layer),
            markers: markers,
            numProperties: acc.numProperties,
            numKeyframedProperties: acc.numKeyframed,
            expressions: acc.expressions
        };
        return rec;
    }

    function mj_scrapeComp(comp, fontSeen) {
        var layers = [];
        var totalLayers = comp.numLayers;
        var limit = totalLayers > MAX_LAYERS_PER_COMP ? MAX_LAYERS_PER_COMP : totalLayers;
        var i;
        for (i = 1; i <= limit; i++) {
            layers.push(mj_scrapeLayer(comp.layer(i), i, fontSeen));
        }
        var rec = {
            name: String(comp.name),
            id: comp.id,
            width: comp.width,
            height: comp.height,
            pixelAspect: comp.pixelAspect,
            frameRate: comp.frameRate,
            duration: comp.duration,
            numLayers: totalLayers,
            layers: layers
        };
        if (totalLayers > MAX_LAYERS_PER_COMP) { rec.layersTruncated = true; }
        return rec;
    }

    /* ---------- main ---------- */

    try {
        if (!app.project) {
            alert("MographJailed scraper: no project is open.");
            return;
        }
        var proj = app.project;

        var outFolder = Folder.selectDialog("Choose Tier 0 receipts folder");
        if (!outFolder) { return; }

        var projFile = proj.file;
        var projectPath = projFile ? String(projFile.fsName) : "";
        var projectName = projFile ? String(projFile.name) : "unsaved-project";
        var dot = projectName.lastIndexOf(".");
        var base = dot > 0 ? projectName.substring(0, dot) : projectName;

        var now = new Date();
        var fontSeen = {};
        var compsOut = [];
        var compsTruncated = false;
        var totalLayers = 0;
        var totalExpressions = 0;

        /* Size-budgeted emission: stop adding comps before ~5 MB. */
        var approxSize = 0;

        var i, item, compJson, compRec;
        var compCount = 0;
        for (i = 1; i <= proj.numItems && compCount < MAX_COMPS; i++) {
            item = proj.item(i);
            if (!(item instanceof CompItem)) { continue; }
            compRec = mj_scrapeComp(item, fontSeen);
            compJson = mj_json(compRec);
            if (approxSize + compJson.length > SIZE_BUDGET) {
                compsTruncated = true;
                break;
            }
            compsOut.push(compJson);
            approxSize += compJson.length;
            totalLayers += compRec.layers.length;
            totalExpressions += (function (layers) {
                var n = 0, q;
                for (q = 0; q < layers.length; q++) { n += layers[q].expressions.length; }
                return n;
            })(compRec.layers);
            compCount++;
        }
        /* If we hit the comp cap while more comps may exist, flag it. */
        if (compCount >= MAX_COMPS) {
            for (i = i; i <= proj.numItems; i++) {
                if (proj.item(i) instanceof CompItem) { compsTruncated = true; break; }
            }
        }

        var fonts = [];
        var fk;
        for (fk in fontSeen) {
            if (fontSeen.hasOwnProperty(fk)) { fonts.push(fk); }
        }
        fonts.sort();

        var footage = [];
        var footageTruncated = false;
        var footageCount = 0;
        for (i = 1; i <= proj.numItems && footageCount < MAX_FOOTAGE; i++) {
            item = proj.item(i);
            if (!(item instanceof FootageItem)) { continue; }
            var fpath = "";
            try { if (item.file) { fpath = String(item.file.fsName); } } catch (ef2) {}
            footage.push({
                id: item.id,
                name: String(item.name),
                path: fpath,
                missing: mj_bool(item.missing),
                hasVideo: mj_bool(item.hasVideo),
                hasAudio: mj_bool(item.hasAudio)
            });
            footageCount++;
        }
        /* If more footage items may exist past the cap, flag it. */
        if (footageCount >= MAX_FOOTAGE) {
            for (i = i; i <= proj.numItems; i++) {
                if (proj.item(i) instanceof FootageItem) { footageTruncated = true; break; }
            }
        }

        var topParts = [];
        topParts.push('"schema":' + mj_json("MJ_PROJECT_SCRAPE_1"));
        topParts.push('"scraperVersion":' + mj_json(SCRAPER_VERSION));
        topParts.push('"projectPath":' + mj_json(projectPath));
        topParts.push('"projectName":' + mj_json(projectName));
        topParts.push('"scrapedAt":' + mj_json(mj_isoNow(now)));
        topParts.push('"aeVersion":' + mj_json(String(app.version)));
        topParts.push('"numItems":' + mj_json(proj.numItems));
        topParts.push('"comps":[' + compsOut.join(",") + "]");
        topParts.push('"fonts":' + mj_json(fonts));
        topParts.push('"footage":' + mj_json(footage));
        if (compsTruncated) { topParts.push('"compsTruncated":true'); }
        if (footageTruncated) { topParts.push('"footageTruncated":true'); }
        var json = "{" + topParts.join(",") + "}";

        var outName = base + "." + mj_fileStamp(now) + ".scrape.json";
        var outFile = new File(outFolder.fsName + "/" + outName);
        /* Never overwrite: if the name collides (same-second rerun), suffix. */
        var suffix = 2;
        while (outFile.exists) {
            outFile = new File(outFolder.fsName + "/" + base + "." +
                               mj_fileStamp(now) + "-" + suffix + ".scrape.json");
            suffix++;
            if (suffix > 999) { alert("MographJailed scraper: too many collisions."); return; }
        }
        if (!outFile.open("w")) {
            alert("MographJailed scraper: could not write " + outFile.fsName);
            return;
        }
        outFile.writeln(json);
        outFile.close();

        alert("MographJailed Tier 0 scrape complete\n\n" +
              "Project: " + projectName + "\n" +
              "Comps: " + compCount + (compsTruncated ? " (truncated)" : "") + "\n" +
              "Layers: " + totalLayers + "\n" +
              "Expressions: " + totalExpressions + "\n" +
              "Fonts: " + fonts.length + "\n" +
              "Footage items: " + footage.length + "\n\n" +
              "Wrote: " + outName);
    } catch (err) {
        alert("MographJailed scraper error:\n" + err.toString());
    }
}());
