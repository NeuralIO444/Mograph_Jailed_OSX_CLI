/* MographJailed M6 LAB ONLY — never invoked by the production CLI. */
function run(argv) {
    var result = {
        schema: "MOGRAPHJAILED_JXA_PROBE_1",
        foundation: false,
        avFoundation: false,
        coreImage: false,
        notes: []
    };
    try {
        ObjC.import('Foundation');
        result.foundation = (typeof $.NSFileManager !== 'undefined');
    } catch (e1) {
        result.notes.push('Foundation import failed: ' + String(e1));
    }
    try {
        ObjC.import('AVFoundation');
        result.avFoundation = (typeof $.AVAssetImageGenerator !== 'undefined');
    } catch (e2) {
        result.notes.push('AVFoundation import failed: ' + String(e2));
    }
    try {
        ObjC.import('CoreImage');
        result.coreImage = (typeof $.CIImage !== 'undefined' && typeof $.CIFilter !== 'undefined');
    } catch (e3) {
        result.notes.push('CoreImage import failed: ' + String(e3));
    }
    return JSON.stringify(result);
}
