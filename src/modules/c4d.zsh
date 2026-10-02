# Cinema 4D intelligence over MJ_C4D_SCRAPE_1 receipts, and the AE/C4D bridge. All read-only.
#
# c4d.inspect  — summarize a scene receipt: renderer, resolution, fps, range, passes, textures
# c4d.lint     — check a scene receipt (missing/absolute textures, camera, odd sizes, range, output, renderer)
# bridge.check — compare a scene receipt with the After Effects comps that use that scene
#
# The receipt is written by integrations/cinema4d/MographJailed_C4DScraper.py under c4dpy. Everything
# here works on the receipt, so it needs no Cinema 4D licence and never opens a scene.

IFS= read -r -d '' MJ_PY_C4D <<'PY_C4D_LIB' || true
C4D_MAX_BYTES = 8388608

def load_c4d(path):
    try:
        if os.path.getsize(path) > C4D_MAX_BYTES:
            err("SCRAPE_TOO_LARGE", "Scene scrape exceeds the byte bound.")
        with open(path, "r", encoding="utf-8") as f:
            doc = json.load(f)
    except Exception as e:
        err("INVALID_JSON", "Scene scrape is not valid JSON: %s" % str(e)[:120])
    if not isinstance(doc, dict) or doc.get("schema") != "MJ_C4D_SCRAPE_1":
        err("SCHEMA_MISMATCH", "Scene scrape must be an MJ_C4D_SCRAPE_1 document.")
    def num(k):
        v = doc.get(k)
        return isinstance(v, (int, float)) and not isinstance(v, bool)
    for k in ("scenePath", "sceneName", "scrapedAt", "c4dVersion", "renderer"):
        if not isinstance(doc.get(k), str):
            err("SCHEMA_MISMATCH", "Scene scrape is missing required key: %s" % k)
    for k in ("fps", "startFrame", "endFrame", "width", "height"):
        if not num(k):
            err("SCHEMA_MISMATCH", "Scene scrape is missing a numeric %s." % k)
    if doc["fps"] <= 0:
        err("SCHEMA_MISMATCH", "Scene scrape has a non-positive fps.")
    for k in ("passes", "cameras", "takes", "materials", "textures"):
        if k in doc and not isinstance(doc[k], list):
            err("SCHEMA_MISMATCH", "%s must be an array." % k)
    return doc

def scene_seconds(d):
    return (d["endFrame"] - d["startFrame"] + 1) / float(d["fps"])
PY_C4D_LIB

c4d_python() {
  local _main=""
  IFS= read -r -d '' _main || true
  printf '%s\n%s\n%s' "$MJ_PY_PROTECT_LIB" "$MJ_PY_C4D" "$_main" | /usr/bin/python3 - 2>/dev/null
}

c4d_require_receipt() {
  local _path="$1"
  is_absolute_path "$_path" || { set_error "INVALID_PATH" "Scene scrape path must be absolute."; return 65; }
  [ -f "$_path" ] || { set_error "INVALID_TARGET" "Scene scrape must be a regular file."; return 65; }
  [ -r "$_path" ] || { set_error "PERMISSION_DENIED" "Scene scrape is not readable."; return 77; }
  cap_available python3 || { set_error "UNSUPPORTED" "Cinema 4D scene checks require python3."; return 69; }
  mj_require_local_existing_path "$_path" || return 73
}

handle_c4d_inspect() {
  local _rc=0 _path="" _out=""
  require_arg path || { emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  _path="$MJ_REQUIRED_ARG_VALUE"
  c4d_require_receipt "$_path" || { _rc=$?; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return $_rc; }
  _out=$(MJ_RECEIPT="$_path" c4d_python <<'PY_C4D_INSPECT'
id0 = tree_id(os.environ["MJ_RECEIPT"])
d = load_c4d(os.environ["MJ_RECEIPT"])
tex = [t for t in d.get("textures", []) if isinstance(t, dict)]
mats = [m for m in d.get("materials", []) if isinstance(m, dict)]
by_type = {}
for m in mats:
    by_type[m.get("type", "other")] = by_type.get(m.get("type", "other"), 0) + 1
missing = [t.get("path", "") for t in tex if t.get("missing")]
absolute = [t.get("path", "") for t in tex if t.get("absolute") and not t.get("missing")]
cams = [c for c in d.get("cameras", []) if isinstance(c, dict)]
warnings = []
if missing:
    warnings.append({"code": "TEXTURES_MISSING", "message": "Missing textures: %d." % len(missing)})
if d.get("truncated"):
    warnings.append({"code": "SCENE_TRUNCATED", "message": "The scene held more textures, materials or cameras than the scraper records; counts are lower bounds."})
print(json.dumps({"ok": True, "data": {
    "schema": "MJ_C4D_SUMMARY_1", "sceneName": d["sceneName"], "scenePath": d["scenePath"], "c4dVersion": d["c4dVersion"], "scrapedAt": d["scrapedAt"],
    "renderer": d["renderer"], "width": d["width"], "height": d["height"], "fps": d["fps"],
    "startFrame": d["startFrame"], "endFrame": d["endFrame"], "frames": d["endFrame"] - d["startFrame"] + 1, "seconds": round(scene_seconds(d), 3),
    "outputPath": d.get("outputPath") or "", "multipass": bool(d.get("multipass")),
    "passes": [p.get("name", "") for p in d.get("passes", []) if isinstance(p, dict)],
    "cameras": len(cams), "activeCamera": next((c.get("name") for c in cams if c.get("active")), None),
    "takes": [t.get("name", "") for t in d.get("takes", []) if isinstance(t, dict)],
    "materials": {"total": len(mats), "byType": by_type},
    "textures": {"total": len(tex), "missing": missing[:50], "absolute": absolute[:50]},
    "objects": d.get("objects"),
    "sourceUnchanged": tree_id(os.environ["MJ_RECEIPT"]) == id0,
    "_warnings": warnings,
}}))
PY_C4D_INSPECT
) || true
  frames_emit_python_result "$_out"
}

handle_c4d_lint() {
  local _rc=0 _path="" _out=""
  require_arg path || { emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  _path="$MJ_REQUIRED_ARG_VALUE"
  c4d_require_receipt "$_path" || { _rc=$?; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return $_rc; }
  _out=$(MJ_RECEIPT="$_path" c4d_python <<'PY_C4D_LINT'
MAX_FINDINGS = 200
id0 = tree_id(os.environ["MJ_RECEIPT"])
d = load_c4d(os.environ["MJ_RECEIPT"])
TEACH = {
    "C001": ("A texture file the scene points at is not on disk, so it renders as a missing-texture placeholder or black.",
             "Relink it, or use File > Save Project with Assets to collect everything beside the scene.",
             'tex/wood_old.png   (not found)', 'tex/wood.png   (relinked, next to the scene)'),
    "C002": ("An absolute texture path such as /Users/you/... exists only on your Mac, so the scene breaks on another machine or after a move.",
             "Collect assets with Save Project with Assets so paths become relative to the scene.",
             '/Users/me/Desktop/wood.png', 'tex/wood.png'),
    "C003": ("With no camera the scene renders from the editor view, which changes whenever someone orbits the viewport.",
             "Add a camera object and make it the active camera.", '(no camera)', 'Camera   (active)'),
    "C004": ("Common video formats need even pixel dimensions; an odd width or height fails to encode or gets cropped by a pixel.",
             "Change the output size to even numbers.", '1921 x 1081', '1920 x 1080'),
    "C005": ("The end frame is before the start frame, so there is nothing to render.", "Fix the frame range in Render Settings or the document settings.",
             'frames 120 to 10', 'frames 10 to 120'),
    "C006": ("There is no render output path, so a render finishes without saving frames.", "Set the output path and format in Render Settings > Save.",
             '(empty)', '/work/renders/shot_$frame.png'),
    "C007": ("This is a Redshift scene but it contains standard materials, which Redshift will not shade the way you expect.",
             "Convert them to Redshift materials, or switch the scene to the standard/physical renderer.", '12 standard materials in a Redshift scene', 'Redshift materials throughout'),
    "C008": ("The scene uses a renderer other than Redshift or Physical.", "Nothing is wrong; MographJailed renders with the scene's own renderer. This note is here so you are not surprised by the look.",
             'renderer: standard', 'renderer: redshift or physical'),
    "C009": ("Multi-pass output is switched on but no passes or AOVs were found, so you get only the beauty image.",
             "Add the passes you need to composite separately (for example depth, cryptomatte), or switch multi-pass off.", 'multi-pass on, 0 passes', 'multi-pass on, 4 passes'),
}
findings = []
def add(code, sev, msg, subject=""):
    t = TEACH[code]
    findings.append({"code": code, "severity": sev, "subject": subject, "message": msg, "teach": {"why": t[0], "fix": t[1]}})
tex = [t for t in d.get("textures", []) if isinstance(t, dict)]
for t in tex:
    if t.get("missing"):
        add("C001", "error", 'Texture "%s" is missing.' % t.get("path", ""), t.get("path", ""))
for t in tex:
    if t.get("absolute") and not t.get("missing"):
        add("C002", "warning", 'Texture "%s" uses an absolute path.' % t.get("path", ""), t.get("path", ""))
cams = [c for c in d.get("cameras", []) if isinstance(c, dict)]
if not cams:
    add("C003", "warning", "The scene has no camera; it renders from the editor view.")
if d["width"] % 2 or d["height"] % 2:
    add("C004", "warning", "Resolution %d x %d has an odd dimension." % (d["width"], d["height"]))
if d["endFrame"] < d["startFrame"]:
    add("C005", "error", "The end frame (%d) is before the start frame (%d)." % (d["endFrame"], d["startFrame"]))
if not (d.get("outputPath") or "").strip():
    add("C006", "warning", "The render output path is empty.")
mats = [m for m in d.get("materials", []) if isinstance(m, dict)]
std = sum(1 for m in mats if m.get("type") == "standard")
if d["renderer"] == "redshift" and std:
    add("C007", "warning", "%d standard material%s in a Redshift scene." % (std, "" if std == 1 else "s"))
if d["renderer"] in ("standard", "other"):
    add("C008", "info", "The scene uses the %s renderer, not Redshift or Physical." % d["renderer"])
if d.get("multipass") and not d.get("passes"):
    add("C009", "info", "Multi-pass output is on but no passes were found.")
order = {"error": 0, "warning": 1, "info": 2}
findings.sort(key=lambda f: (order[f["severity"]], f["code"], f["subject"]))
truncated = len(findings) > MAX_FINDINGS
findings = findings[:MAX_FINDINGS]
print(json.dumps({"ok": True, "data": {
    "schema": "MJ_C4D_LINT_1", "sceneName": d["sceneName"], "renderer": d["renderer"], "numFindings": len(findings),
    "errors": sum(1 for f in findings if f["severity"] == "error"), "warnings": sum(1 for f in findings if f["severity"] == "warning"),
    "info": sum(1 for f in findings if f["severity"] == "info"), "findings": findings, "findingsTruncated": truncated,
    "teaching": {c: {"before": TEACH[c][2], "after": TEACH[c][3]} for c in sorted({f["code"] for f in findings})},
    "rules": sorted(TEACH), "sourceUnchanged": tree_id(os.environ["MJ_RECEIPT"]) == id0,
    "_warnings": ([{"code": "FINDINGS_TRUNCATED", "message": "Only the first %d findings are listed." % MAX_FINDINGS}] if truncated else []),
}}))
PY_C4D_LINT
) || true
  frames_emit_python_result "$_out"
}

handle_bridge_check() {
  local _rc=0 _c4d="" _ae="" _comp="" _out=""
  require_arg path || { emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  _c4d="$MJ_REQUIRED_ARG_VALUE"
  require_arg input || { emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  _ae="$MJ_REQUIRED_ARG_VALUE"
  request_arg_present target && _comp=$(request_arg_get target)
  c4d_require_receipt "$_c4d" || { _rc=$?; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return $_rc; }
  project_require_scrape_file "$_ae" || { _rc=$?; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return $_rc; }

  _out=$(MJ_C4D="$_c4d" MJ_AE="$_ae" MJ_COMP="$_comp" c4d_python <<'PY_BRIDGE_CHECK'
ida, idb = tree_id(os.environ["MJ_C4D"]), tree_id(os.environ["MJ_AE"])
c = load_c4d(os.environ["MJ_C4D"])
ae = load_scrape(os.environ["MJ_AE"])
only = os.environ["MJ_COMP"]
TEACH = {
    "B001": ("The After Effects comp runs at a different frame rate from the Cinema 4D scene, so frames are dropped or duplicated and motion stutters.",
             "Set the comp's frame rate to the scene's, or re-render the scene at the comp's rate."),
    "B002": ("The comp and the scene have different pixel dimensions, so the render is scaled or cropped in the comp.",
             "Match the comp size to the scene, or set the scene's output size to the comp's."),
    "B003": ("The comp and the scene run for different lengths: a shorter comp cuts the end of the animation, a longer one holds or goes blank.",
             "Match the comp duration to the scene's frame range, or change the range on the Cinema 4D side."),
    "B004": ("The layer points at a different .c4d than the scene that was checked, so After Effects is showing another copy.",
             "Replace the layer's source with the scene you checked, or check the scene the layer actually uses."),
    "B005": ("The After Effects project reports this scene file as missing, so the layer shows nothing.",
             "Relink it with Replace Footage, then check again."),
}
scene = c["scenePath"]; sname = c["sceneName"].lower()
footage = [f for f in ae["footage"] if isinstance(f, dict)]
def is_scene(path, name):
    base = (os.path.basename(path or "") or name or "").lower()
    return base.endswith(".c4d") and base == sname
matches, findings = [], []
def add(code, sev, comp, layer, msg):
    findings.append({"code": code, "severity": sev, "comp": comp, "layer": layer, "message": msg, "teach": {"why": TEACH[code][0], "fix": TEACH[code][1]}})
for comp in ae["comps"]:
    if not isinstance(comp, dict) or (only and comp.get("name") != only):
        continue
    cname = str(comp.get("name", ""))
    for layer in comp.get("layers") or []:
        if not isinstance(layer, dict) or not is_scene(layer.get("sourcePath"), layer.get("sourceName")):
            continue
        lname = str(layer.get("name", ""))
        spath = str(layer.get("sourcePath") or "")
        matches.append({"comp": cname, "layer": lname, "layerIndex": layer.get("index"), "samePath": (spath == scene) if spath else None})
        fr, du, w, h = comp.get("frameRate"), comp.get("duration"), comp.get("width"), comp.get("height")
        if isinstance(fr, (int, float)) and abs(fr - c["fps"]) > 0.01:
            add("B001", "error", cname, lname, 'Comp "%s" runs at %s fps; the scene is %s fps.' % (cname, fr, c["fps"]))
        if isinstance(w, int) and isinstance(h, int) and (w != c["width"] or h != c["height"]):
            add("B002", "warning", cname, lname, 'Comp "%s" is %d x %d; the scene is %d x %d.' % (cname, w, h, c["width"], c["height"]))
        if isinstance(du, (int, float)) and abs(du - scene_seconds(c)) > 1.0 / c["fps"] + 1e-6:
            add("B003", "warning", cname, lname, 'Comp "%s" is %.2f s; the scene range is %.2f s (%d frames).' % (cname, du, scene_seconds(c), c["endFrame"] - c["startFrame"] + 1))
        if spath and spath != scene:
            add("B004", "error", cname, lname, 'Layer "%s" uses %s, not %s.' % (lname, spath, scene))
        if any(f.get("missing") and ((f.get("path") or "") == spath or (spath == "" and (f.get("name") or "").lower() == sname)) for f in footage):
            add("B005", "error", cname, lname, 'After Effects reports "%s" as missing.' % sname)
order = {"error": 0, "warning": 1, "info": 2}
findings.sort(key=lambda f: (order[f["severity"]], f["code"], f["comp"], f["layer"]))
errors = sum(1 for f in findings if f["severity"] == "error")
warns = []
if not matches:
    warns.append({"code": "NO_MATCHING_LAYER", "message": "No layer%s in the After Effects project uses %s, so nothing was compared." % (" in comp \"%s\"" % only if only else "", c["sceneName"])})
print(json.dumps({"ok": True, "data": {
    "schema": "MJ_BRIDGE_CHECK_1", "sceneName": c["sceneName"], "projectName": ae.get("projectName"), "matched": len(matches), "matches": matches,
    "numFindings": len(findings), "errors": errors, "warnings": sum(1 for f in findings if f["severity"] == "warning"),
    "consistent": bool(matches) and errors == 0 and not findings, "findings": findings,
    "scene": {"fps": c["fps"], "width": c["width"], "height": c["height"], "frames": c["endFrame"] - c["startFrame"] + 1, "seconds": round(scene_seconds(c), 3), "renderer": c["renderer"]},
    "sourceUnchanged": tree_id(os.environ["MJ_C4D"]) == ida and tree_id(os.environ["MJ_AE"]) == idb,
    "_warnings": warns,
}}))
PY_BRIDGE_CHECK
) || true
  frames_emit_python_result "$_out"
}
