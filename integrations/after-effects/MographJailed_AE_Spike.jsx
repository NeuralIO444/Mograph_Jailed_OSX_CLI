#target aftereffects
#include "MographJailed_Client.jsxinc"

(function () {
    try {
        var client = new MJNativeClient();
        var probe = client.probe();
        if (!probe.ok) {
            alert("MographJailed probe failed:\n" + probe.error.code + "\n" + probe.error.message);
            return;
        }

        var selected = File.openDialog("Choose one media file for MographJailed immutable inspection");
        if (!selected) { return; }

        var result = client.inspectMediaReadOnly(selected.fsName);
        if (!result.ok) {
            alert("MographJailed inspection failed at: " + result.stage);
            return;
        }

        var data = result.inspect.data;
        alert(
            "MographJailed AE Integration Spike\n\n" +
            "Native protocol: PASS\n" +
            "Source unchanged (size+mtime): " + (result.unchanged ? "PASS" : "FAIL") + "\n" +
            "Path: " + data.path + "\n" +
            "Type: " + data.basicType + "\n" +
            "Size: " + data.sizeBytes + " bytes\n" +
            "Duration: " + (data.durationSeconds === null ? "unavailable" : data.durationSeconds + " sec")
        );
    } catch (e) {
        alert("MographJailed AE spike error:\n" + e.toString());
    }
}());
