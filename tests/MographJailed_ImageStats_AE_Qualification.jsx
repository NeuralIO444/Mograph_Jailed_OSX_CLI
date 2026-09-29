/* MographJailed SL-M3 ImageStats After Effects child-process qualification. */
(function () {
    var scriptFile = new File($.fileName);
    var root = scriptFile.parent.parent;
    var clientFile = new File(root.fsName + "/integrations/after-effects/MographJailed_Client.jsxinc");
    var cliFile = new File(root.fsName + "/dist/mograph-jailed.zsh");
    var movie = new File("/System/Library/PrivateFrameworks/Slideshows.framework/Versions/A/Resources/Content/Styles/SlidingPanels.mrbStyle/Contents/Resources/Preview.mov");
    var frameA = new File(Folder.temp.fsName + "/MographJailed_ImageStats_A_" + (new Date().getTime()) + ".png");
    var frameB = new File(Folder.temp.fsName + "/MographJailed_ImageStats_B_" + (new Date().getTime()) + ".png");
    var receipt = new File(Folder.desktop.fsName + "/MographJailed_ImageStats_AE_Qualification.txt");
    var lines = [];
    var pass = 0, fail = 0;

    function record(ok, name, detail) {
        if (ok) { pass++; lines.push("PASS|" + name + "|" + detail); }
        else { fail++; lines.push("FAIL|" + name + "|" + detail); }
    }

    lines.push("HEADER|schema|MOGRAPHJAILED_IMAGESTATS_AE_TARGET_1");
    lines.push("HEADER|scope|LOCAL_ONLY");
    lines.push("HEADER|networkMutation|0");

    try {
        record(clientFile.exists, "client", "present");
        record(cliFile.exists, "runtime", "present");
        if (!clientFile.exists || !cliFile.exists) { throw new Error("Required SL-M3 files are missing."); }
        $.evalFile(clientFile);

        if (!movie.exists) {
            var found = system.callSystem("/usr/bin/mdfind -onlyin /System/Library 'kMDItemContentTypeTree == \"public.movie\"' | /usr/bin/awk 'NR==1{print;exit}'");
            found = String(found).replace(/[\r\n]+$/, "");
            movie = new File(found);
        }
        record(movie.exists, "fixture", "local_system_movie");
        if (!movie.exists) { throw new Error("No readable local system movie fixture found."); }

        var client = new MJNativeClient(cliFile);
        var desc = client.describe(true);
        record(!!(desc.ok && desc.data && desc.data.operations && desc.data.operations["image.stats"] && desc.data.operations["image.stats"].available === true), "stats", "available_from_ae_child");
        record(!!(desc.ok && desc.data && desc.data.operations && desc.data.operations["image.compare"] && desc.data.operations["image.compare"].available === true), "compare", "available_from_ae_child");

        // Extract two frames for test images
        var exA = client.mediaFrame(movie.fsName, frameA.fsName, 0.5, 320);
        var exB = client.mediaFrame(movie.fsName, frameB.fsName, 1.5, 320);
        record(!!(exA.ok && frameA.exists), "extract_a", "frame_ready");
        if (!exA.ok) { throw new Error("Frame extraction failed for stats test."); }

        // image.stats via AE client
        var stats = client.imageStats(frameA.fsName);
        record(!!(stats.ok && stats.data && stats.data.schema === "MJ_IMAGE_STATS_1"), "stats", "valid_schema");
        if (stats.ok && stats.data) {
            record(stats.data.histogram && stats.data.histogram.length === 64, "histogram", "64_bins");
            record(stats.data.gridAverages && stats.data.gridAverages.length === 64, "grid", "64_cells");
            record(stats.data.pixelWidth > 0 && stats.data.pixelHeight > 0, "dimensions", "positive");
            record(stats.data.sourceUnchanged === true, "immutability", "source_unchanged");
        }

        // Determinism: run twice
        var stats2 = client.imageStats(frameA.fsName);
        var det = false;
        if (stats.ok && stats2.ok && stats.data && stats2.data) {
            det = (stats.data.histogram.join(",") === stats2.data.histogram.join(","));
        }
        record(det, "determinism", "identical_twice");

        // image.compare on identical → 1.0
        var cmpSame = client.imageCompare(frameA.fsName, frameA.fsName);
        record(!!(cmpSame.ok && cmpSame.data && cmpSame.data.schema === "MJ_IMAGE_COMPARE_1" && cmpSame.data.score === 1.0), "compare_same", "score_1");

        // image.compare on different (if second frame available)
        if (exB.ok && frameB.exists) {
            var cmpDiff = client.imageCompare(frameA.fsName, frameB.fsName);
            record(!!(cmpDiff.ok && cmpDiff.data && cmpDiff.data.score < 1.0 && cmpDiff.data.score >= 0.0), "compare_diff", "score_in_range");
        }

        // Rejects missing file
        var bad = client.imageStats("/nonexistent/image.png");
        record(!!(!bad.ok), "rejection", "missing_file_rejected");
    } catch (e) {
        record(false, "exception", e && e.message ? e.message : String(e));
    }

    try { if (frameA.exists) { frameA.remove(); } } catch (ignoreA) {}
    try { if (frameB.exists) { frameB.remove(); } } catch (ignoreB) {}
    lines.push("SUMMARY|pass=" + pass + "|fail=" + fail + "|skip=0");
    lines.push("POLICY|networkReads=0|networkWrites=0|sudo=0|python=system_stdlib|xcodeTools=0");

    try {
        receipt.encoding = "UTF-8";
        receipt.open("w");
        for (var i = 0; i < lines.length; i++) { receipt.writeln(lines[i]); }
        receipt.close();
    } catch (ignoreReceipt) {}

    alert("MographJailed ImageStats AE Qualification\n\nPass: " + pass + " / Fail: " + fail + "\n\nReceipt: " + receipt.fsName);
}());
