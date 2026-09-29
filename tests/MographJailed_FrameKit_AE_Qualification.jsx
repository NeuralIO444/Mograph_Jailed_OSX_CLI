/* MographJailed 0.3.0-dev.2 FrameKit After Effects child-process qualification. */
(function () {
    var scriptFile = new File($.fileName);
    var root = scriptFile.parent.parent;
    var clientFile = new File(root.fsName + "/integrations/after-effects/MographJailed_Client.jsxinc");
    var cliFile = new File(root.fsName + "/dist/mograph-jailed.zsh");
    var movie = new File("/System/Library/PrivateFrameworks/Slideshows.framework/Versions/A/Resources/Content/Styles/SlidingPanels.mrbStyle/Contents/Resources/Preview.mov");
    var output = new File(Folder.temp.fsName + "/MographJailed_FrameKit_AE_" + (new Date().getTime()) + ".png");
    var receipt = new File(Folder.temp.fsName + "/MographJailed_FrameKit_AE_Qualification.txt");
    var lines = [];
    var pass = 0, fail = 0;

    function record(ok, name, detail) {
        if (ok) { pass++; lines.push("PASS|" + name + "|" + detail); }
        else { fail++; lines.push("FAIL|" + name + "|" + detail); }
    }

    lines.push("HEADER|schema|MOGRAPHJAILED_FRAMEKIT_AE_TARGET_1");
    lines.push("HEADER|scope|LOCAL_ONLY");
    lines.push("HEADER|networkMutation|0");

    try {
        record(clientFile.exists, "client", "present");
        record(cliFile.exists, "runtime", "present");
        if (!clientFile.exists || !cliFile.exists) { throw new Error("Required dev.2 files are missing."); }
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
        record(!!(desc.ok && desc.cliVersion === "0.3.0-dev.2"), "describe", "dev2");
        record(!!(desc.ok && desc.data && desc.data.operations && desc.data.operations["media.frame"] && desc.data.operations["media.frame"].available === true), "framekit", "available_from_ae_child");

        var frame = client.mediaFrame(movie.fsName, output.fsName, 1.0, 640);
        record(!!(frame.ok && frame.data && frame.data.schema === "MJ_MEDIA_FRAME_1"), "extract", "media_frame_ok");
        record(output.exists, "output", "png_created_in_temp");
        if (frame.ok && frame.data) {
            record(frame.data.scope && frame.data.scope.classification === "local" && frame.data.scope.policy === "LOCAL_ONLY", "scope", "local_only");
            record(frame.data.frameAccurateRequest === true && frame.data.toleranceBeforeSeconds === 0 && frame.data.toleranceAfterSeconds === 0, "timing", "zero_tolerance");
            record(typeof frame.data.actualTime.seconds === "number" && typeof frame.data.requestedTime.seconds === "number", "actual_time", "reported");
            record(frame.data.preferredTrackTransformApplied === true, "transform", "applied");
            record(frame.data.sourceUnchanged === true, "immutability", "source_unchanged");
        }

        var repeat = client.mediaFrame(movie.fsName, output.fsName, 1.0, 640);
        record(!!(!repeat.ok && repeat.error && repeat.error.code === "OUTPUT_EXISTS"), "no_overwrite", "refused_existing_output");
    } catch (e) {
        record(false, "exception", e && e.message ? e.message : String(e));
    }

    try { if (output.exists) { output.remove(); } } catch (ignoreRemove) {}
    lines.push("SUMMARY|pass=" + pass + "|fail=" + fail + "|skip=0");
    lines.push("POLICY|networkReads=0|networkWrites=0|sudo=0|python=system_stdlib|xcodeTools=0");

    receipt.encoding = "UTF-8";
    receipt.lineFeed = "Unix";
    if (receipt.open("w")) {
        var i;
        for (i = 0; i < lines.length; i++) { receipt.writeln(lines[i]); }
        receipt.close();
    }

    alert("MographJailed FrameKit AE Qualification\n\n" + (fail === 0 ? "PASS" : "FAIL") + "\nPass: " + pass + "\nFail: " + fail + "\n\nReceipt:\n" + receipt.fsName);
}());
