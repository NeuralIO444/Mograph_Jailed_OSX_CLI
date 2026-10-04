# After Effects jobs: changes that only After Effects can make, done on a copy, never the original.
#
# project.extract  — keep one comp or a list of comps (and everything they use) as a NEW project.
# project.conform  — bring a project to a studio spec: comp and layer names, labels, project-panel
#                    folders, and the expressions that refer to renamed things (plus, optionally,
#                    broken name references with one clear close match). format=plan (default) only
#                    reports the plan; format=job writes a job.
# project.jobcheck — after the job ran in After Effects: was it applied, and is the original untouched?
#
# Everything is planned here from the scrape, so it is reviewable and testable without After Effects.
# A job folder holds before.aep (a verified copy), plan.json and run.jsx (the fixed runner in
# integrations/after-effects/MographJailed_JobRunner.jsx with the plan embedded). The runner opens only
# before.aep, skips any step whose item no longer matches the plan, and saves result.aep as a new file.

IFS= read -r -d '' MJ_PY_AEJOB <<'PY_AEJOB_LIB' || true
import difflib

def require_same_project(doc, aep):
    """Comp ids and layer indexes only mean something for the project that was scraped. Two client folders
    can each hold a Main.aep, so compare the full resolved path, not the file name."""
    sp = doc.get("projectPath") or ""
    if not sp or os.path.realpath(sp) != os.path.realpath(aep):
        err("PROJECT_SCRAPE_MISMATCH", "The scrape was made from %s, not from %s; scrape this project again so the comp ids match." % (sp or "an unsaved project", aep))

def comp_index(doc):
    comps = [c for c in doc["comps"] if isinstance(c, dict) and isinstance(c.get("id"), int)]
    return comps, {c["id"]: c for c in comps}

def comp_closure(byid, ids):
    """The comps reachable from ids through precomp layers, and the footage ids they use."""
    seen, stack, footage = set(), list(ids), set()
    while stack:
        cid = stack.pop()
        if cid in seen or cid not in byid:
            continue
        seen.add(cid)
        for l in byid[cid].get("layers") or []:
            sid = l.get("sourceId") if isinstance(l, dict) else None
            if isinstance(sid, int) and sid:
                if sid in byid:
                    stack.append(sid)
                else:
                    footage.add(sid)
    return seen, footage

def make_job(kind, label, aep, outdir, plan_body, runner_path, scrape_path):
    """Create <outdir>/<label>.mjjob with a verified copy, plan.json and run.jsx. Never overwrites."""
    job = os.path.join(outdir, label + ".mjjob")
    try:
        os.mkdir(job, 0o755)
    except FileExistsError:
        err("OUTPUT_EXISTS", "A job named %s already exists in the output folder." % label)
    except OSError:
        err("OUTPUT_UNAVAILABLE", "The job folder could not be created.")
    try:
        runner = open(runner_path, encoding="utf-8").read()
    except OSError:
        shutil.rmtree(job, ignore_errors=True)
        err("NOT_FOUND", "The After Effects job runner is missing (integrations/after-effects/MographJailed_JobRunner.jsx).")
    src_sha = sha256_file(aep)
    work = os.path.join(job, "before.aep")
    try:
        cloned = clone_copy(aep, work)
    except OSError:
        shutil.rmtree(job, ignore_errors=True)
        err("SNAPSHOT_FAILED", "The project could not be copied into the job folder.")
    if sha256_file(work) != src_sha or sha256_file(aep) != src_sha:
        shutil.rmtree(job, ignore_errors=True)
        err("SNAPSHOT_UNSTABLE", "The project changed while it was being copied; save it in After Effects and try again.")
    plan = {"schema": "MJ_AE_JOB_1", "kind": kind, "label": label, "createdAt": utc_stamp(),
            "source": {"path": aep, "sha256": src_sha, "size": os.path.getsize(aep)}, "scrape": scrape_path,
            "work": work, "workSha256": src_sha, "result": os.path.join(job, "result.aep"), "receipt": os.path.join(job, "result.json"),
            "quietFlag": os.path.join(job, "quiet")}
    plan.update(plan_body)
    text = json.dumps(plan, indent=1, sort_keys=True, ensure_ascii=True)
    with open(os.path.join(job, "plan.json"), "x", encoding="utf-8") as f:
        f.write(text + "\n")
    with open(os.path.join(job, "run.jsx"), "x", encoding="utf-8") as f:
        f.write("#target aftereffects\n// MographJailed %s job \"%s\". Run this file in After Effects; it works on before.aep in this folder only.\n" % (kind, label))
        f.write("var MJ_PLAN = " + text + ";\n")
        f.write(runner)
    return job, plan, cloned

# ---- studio spec ----
LAYER_KINDS = ("text", "shape", "solid", "null", "adjustment", "camera", "light", "precomp", "footage", "audio")
DEFAULT_STUDIO_SPEC = {
    "name": "MographJailed studio default",
    "precompPrefix": "PRE_", "mainCompPrefix": "", "spaces": "_",
    "layerPrefix.text": "TXT_", "layerPrefix.shape": "SHP_", "layerPrefix.solid": "SOL_", "layerPrefix.null": "NULL_",
    "layerPrefix.adjustment": "ADJ_", "layerPrefix.camera": "CAM_", "layerPrefix.light": "LGT_", "layerPrefix.precomp": "PRE_",
    "layerPrefix.footage": "", "layerPrefix.audio": "AUD_",
    "label.text": "1", "label.shape": "8", "label.solid": "2", "label.null": "11", "label.adjustment": "5", "label.camera": "4",
    "label.light": "6", "label.precomp": "15", "label.footage": "14", "label.audio": "7",
    "label.mainComp": "9", "label.precompItem": "15",
    "folder.mainComps": "01_Comps", "folder.precomps": "02_Precomps", "folder.footage": "03_Footage", "folder.solids": "04_Solids", "folder.audio": "05_Audio",
    "fixBrokenRefs": "suggest",
}
STUDIO_KEYS = {"name", "precompPrefix", "mainCompPrefix", "spaces", "fixBrokenRefs", "label.mainComp", "label.precompItem"} | \
    {"layerPrefix." + k for k in LAYER_KINDS} | {"label." + k for k in LAYER_KINDS} | \
    {"folder." + k for k in ("mainComps", "precomps", "footage", "solids", "audio")}

def parse_studio_spec(path):
    spec = {}
    try:
        lines = open(path, encoding="utf-8").read(65536).splitlines()
    except (OSError, UnicodeDecodeError):
        err("INVALID_SPEC", "The studio spec could not be read as UTF-8 text.")
    for n, line in enumerate(lines, 1):
        s = line.strip()
        if not s or s.startswith("#"):
            continue
        if "=" not in s:
            err("INVALID_SPEC", "Spec line %d is not key = value." % n)
        k, v = (x.strip() for x in s.split("=", 1))
        if k not in STUDIO_KEYS:
            err("INVALID_SPEC", "Spec line %d: unknown key %s." % (n, k))
        if k.startswith("label.") and v and not (v.isdigit() and 0 <= int(v) <= 16):
            err("INVALID_SPEC", "Spec line %d: %s must be a label number 0-16 (or empty to leave labels alone)." % (n, k))
        if k == "spaces" and v not in ("keep", "_", "-"):
            err("INVALID_SPEC", "Spec line %d: spaces must be keep, _ or -." % n)
        if k == "fixBrokenRefs" and v not in ("off", "suggest", "apply"):
            err("INVALID_SPEC", "Spec line %d: fixBrokenRefs must be off, suggest or apply." % n)
        if any(ch in v for ch in '"\\') or len(v) > 64:
            err("INVALID_SPEC", "Spec line %d: values may not contain quotes or backslashes and must be short." % n)
        spec[k] = v
    return spec

def layer_kind(l, comp_ids):
    t = l.get("type")
    simple = {"TextLayer": "text", "ShapeLayer": "shape", "CameraLayer": "camera", "LightLayer": "light", "NullLayer": "null"}
    if t in simple:
        return simple[t]
    if l.get("adjustment"):
        return "adjustment"
    sk = l.get("sourceKind") or ("comp" if l.get("sourceId") in comp_ids else "")
    if sk == "comp":
        return "precomp"
    if sk == "solid":
        return "solid"
    if l.get("hasAudio") and not l.get("hasVideo"):
        return "audio"
    return "footage"

def styled(name, spec):
    n = " ".join(str(name).split())
    sp = spec.get("spaces", "keep")
    if sp in ("_", "-"):
        n = n.replace(" ", sp)
    return n

def prefixed(name, prefix):
    if prefix and not name.lower().startswith(prefix.lower()):
        return prefix + name
    return name

def unique(name, taken):
    if name not in taken:
        return name
    i = 2
    while "%s_%d" % (name, i) in taken:
        i += 1
    return "%s_%d" % (name, i)

REF = re.compile(r'(\bcomp|\.layer|\blayer)\(\s*(["\'])((?:(?!\2)[^\\\n])*)\2\s*\)')
THIS_COMP = re.compile(r'\bthisComp\s*$')

def rewrite_expression(text, own_comp, comp_new, layer_new, layer_names, fix, suggestions, where, unresolved):
    """Rename name references inside one expression. Returns (new text, changed?).
    A layer("...") lookup is followed only when its comp is certain: it directly follows thisComp, or follows
    comp("...") (whitespace and line breaks allowed between). Anything else (c.layer("x") on a variable, a
    layer found through another call) is left alone and counted in `unresolved`."""
    out, pos, changed = [], 0, False
    last_comp_end, last_comp_name = -1, None
    for m in REF.finditer(text):
        fn, q, name = m.group(1), m.group(2), m.group(3)
        new = name
        if fn == "comp":
            last_comp_end, last_comp_name = m.end(), name
            new = comp_new.get(name, name)
        else:
            if fn == "layer":
                target = own_comp
            elif last_comp_end >= 0 and text[last_comp_end:m.start()].strip() == "":
                target = last_comp_name
            elif THIS_COMP.search(text[:m.start()]):
                target = own_comp
            else:
                unresolved.append(where); continue
            names = layer_names.get(target)
            if names is not None and name not in names and fix != "off":
                close = difflib.get_close_matches(name, sorted(names), n=2, cutoff=0.8)
                if len(close) == 1:
                    suggestions.append(dict(where, reference=name, suggestion=close[0], comp=target, applied=fix == "apply"))
                    if fix == "apply":
                        name_fixed = close[0]
                        new = layer_new.get((target, name_fixed), name_fixed)
            if new == name:
                new = layer_new.get((target, name), name)
        if new != name:
            out.append(text[pos:m.start(3)]); out.append(new); pos = m.end(3); changed = True
    out.append(text[pos:])
    return "".join(out), changed

NAME_CAP = 255      # After Effects will not make a comp, layer or footage name longer than this

def plan_conform(doc, spec):
    comps, byid = comp_index(doc)
    # A name longer than After Effects allows did not come from After Effects. Such comps and layers are left out of the
    # plan entirely (never renamed, never copied into a job), and counted so the person is told.
    too_long, kept = 0, []
    for c in comps:
        if len(str(c.get("name", ""))) > NAME_CAP:
            too_long += 1
            continue
        all_layers = [l for l in c.get("layers") or [] if isinstance(l, dict)]
        ok_layers = [l for l in all_layers if len(str(l.get("name", ""))) <= NAME_CAP]
        too_long += len(all_layers) - len(ok_layers)
        c = dict(c)
        c["layers"] = ok_layers
        kept.append(c)
    comps = kept
    byid = {c["id"]: c for c in comps}
    comp_ids = set(byid)
    used_as_precomp = {l.get("sourceId") for c in comps for l in (c.get("layers") or []) if isinstance(l, dict) and l.get("sourceId") in comp_ids}
    names_count = {}
    for c in comps:
        names_count[c.get("name")] = names_count.get(c.get("name"), 0) + 1
    item_renames, comp_new, taken = [], {}, set()
    # Names that already match the spec keep their name; reserve them first so a rename never lands on one.
    for c in comps:
        role0 = "precomp" if c["id"] in used_as_precomp else "main"
        if prefixed(styled(c["name"], spec), spec.get("precompPrefix" if role0 == "precomp" else "mainCompPrefix", "")) == c["name"]:
            taken.add(c["name"])
    for c in comps:
        role = "precomp" if c["id"] in used_as_precomp else "main"
        new = prefixed(styled(c["name"], spec), spec.get("precompPrefix" if role == "precomp" else "mainCompPrefix", ""))
        if new != c["name"]:
            new = unique(new, taken)
        taken.add(new)
        c["_role"] = role
        if new != c["name"]:
            item_renames.append({"id": c["id"], "kind": "comp", "role": role, "from": c["name"], "to": new})
            if names_count[c["name"]] == 1:
                comp_new[c["name"]] = new
    layer_renames, layer_new, layer_labels, layer_names = [], {}, [], {}
    for c in comps:
        layer_names[c["name"]] = {l.get("name") for l in (c.get("layers") or []) if isinstance(l, dict)}
        seen, lc = set(), {}
        for l in c.get("layers") or []:
            lc[l.get("name")] = lc.get(l.get("name"), 0) + 1
            if isinstance(l, dict) and prefixed(styled(l.get("name", ""), spec), spec.get("layerPrefix." + layer_kind(l, comp_ids), "")) == l.get("name"):
                seen.add(l.get("name"))
        for l in c.get("layers") or []:
            if not isinstance(l, dict) or not isinstance(l.get("index"), int):
                continue
            kind = layer_kind(l, comp_ids)
            new = prefixed(styled(l.get("name", ""), spec), spec.get("layerPrefix." + kind, ""))
            if new != l.get("name"):
                new = unique(new, seen)
            seen.add(new)
            if new != l.get("name"):
                layer_renames.append({"compId": c["id"], "comp": c["name"], "index": l["index"], "kind": kind, "from": l.get("name"), "to": new})
                if lc[l.get("name")] == 1:
                    layer_new[(c["name"], l.get("name"))] = new
            want = spec.get("label." + kind, "")
            if want != "" and isinstance(l.get("label"), int) and l["label"] != int(want):
                layer_labels.append({"compId": c["id"], "comp": c["name"], "index": l["index"], "layer": l.get("name"), "kind": kind, "from": l["label"], "to": int(want)})
    item_labels, moves, folders = [], [], []
    def move(item_id, kind, frm, folder_key, name):
        dest = spec.get(folder_key, "")
        if dest and frm != dest:
            moves.append({"id": item_id, "kind": kind, "name": name, "from": frm, "to": dest})
            if dest not in folders:
                folders.append(dest)
    for c in comps:
        want = spec.get("label.precompItem" if c["_role"] == "precomp" else "label.mainComp", "")
        if want != "" and isinstance(c.get("label"), int) and c["label"] != int(want):
            item_labels.append({"id": c["id"], "kind": "comp", "name": c["name"], "from": c["label"], "to": int(want)})
        if "folder" in c:
            move(c["id"], "comp", c.get("folder", ""), "folder.precomps" if c["_role"] == "precomp" else "folder.mainComps", c["name"])
    for f in doc["footage"]:
        if not isinstance(f, dict) or not isinstance(f.get("id"), int) or "folder" not in f or len(str(f.get("name", ""))) > NAME_CAP:
            continue
        key = "folder.solids" if f.get("kind") == "solid" else "folder.audio" if (f.get("hasAudio") and not f.get("hasVideo")) else "folder.footage"
        move(f["id"], "footage", f.get("folder", ""), key, f.get("name", ""))
    expressions, suggestions, dynamic = [], [], 0
    fix = spec.get("fixBrokenRefs", "suggest")
    for c in comps:
        for l in c.get("layers") or []:
            if not isinstance(l, dict):
                continue
            for e in l.get("expressions") or []:
                if not isinstance(e, dict) or e.get("expressionTruncated"):
                    continue
                text = e.get("expression", "")
                where = {"comp": c["name"], "layer": l.get("name"), "path": e.get("propertyPath")}
                unresolved = []
                new, changed = rewrite_expression(text, c["name"], comp_new, layer_new, layer_names, fix, suggestions, where, unresolved)
                if unresolved:
                    dynamic += 1
                if changed:
                    expressions.append({"compId": c["id"], "comp": c["name"], "index": l.get("index"), "layer": l.get("name"), "path": e.get("propertyPath"), "from": text, "to": new})
                if re.search(r"\b(?:comp|layer)\(\s*[^\"'\s)]", text) and not unresolved:
                    dynamic += 1
    return {"nameTooLong": too_long, "itemRenames": item_renames, "layerRenames": layer_renames, "expressions": expressions, "layerLabels": layer_labels,
            "itemLabels": item_labels, "folders": folders, "moves": moves, "suggestions": suggestions, "dynamicReferences": dynamic}
PY_AEJOB_LIB

aejob_python() {
  local _main=""
  IFS= read -r -d '' _main || true
  printf '%s\n%s\n%s' "$MJ_PY_PROTECT_LIB" "$MJ_PY_AEJOB" "$_main" | /usr/bin/python3 - 2>/dev/null
}

aejob_runner_path() {
  local _self
  _self=$(runtime_self_path) || return 1
  printf '%s/../integrations/after-effects/MographJailed_JobRunner.jsx' "${_self%/*}"
}

# Shared checks for an .aep + its scrape (+ optional output folder and label for a job).
aejob_require_inputs() {
  local _aep="$1" _scrape="$2"
  is_absolute_path "$_aep" || { set_error "INVALID_PATH" "Project path must be absolute."; return 65; }
  case "${_aep##*/}" in *.[aA][eE][pP]) ;; *) set_error "INVALID_TARGET" "Project must be an After Effects .aep file."; return 65 ;; esac
  [ -f "$_aep" ] || { set_error "NOT_FOUND" "Project not found."; return 66; }
  mj_require_local_existing_path "$_aep" || return 73
  file_require_materialized "$_aep" || return $?
  project_require_scrape_file "$_scrape" || return $?
}

aejob_require_job_output() {
  local _out="$1" _label="$2"
  protect_require_output_dir "$_out" || return $?
  case "$_label" in ""|.*|*[!A-Za-z0-9._-]*) set_error "INVALID_ARGUMENT" "label may contain only letters, digits, dot, dash and underscore."; return 65 ;; esac
  [ ${#_label} -le 64 ] || { set_error "INVALID_ARGUMENT" "label must be at most 64 characters."; return 65; }
}

handle_project_extract() {
  local _rc=0 _aep _scrape _ids _outdir _label _out a
  for a in path input target output label; do require_arg "$a" || { emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }; done
  _aep=$(request_arg_get path); _scrape=$(request_arg_get input); _ids=$(request_arg_get target)
  _outdir=$(request_arg_get output); _label=$(request_arg_get label)
  case "$_ids" in ""|*[!0-9,]*|,*|*,|*,,*) set_error "INVALID_ARGUMENT" "target must be comp ids from the scrape, separated by commas (for example 12,40)."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65 ;; esac
  aejob_require_inputs "$_aep" "$_scrape" || { _rc=$?; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return $_rc; }
  aejob_require_job_output "$_outdir" "$_label" || { _rc=$?; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return $_rc; }
  _out=$(MJ_AEP="$_aep" MJ_SCRAPE="$_scrape" MJ_IDS="$_ids" MJ_OUT="$_outdir" MJ_LABEL="$_label" MJ_RUNNER="$(aejob_runner_path)" aejob_python <<'PY_EXTRACT'
doc = load_scrape(os.environ["MJ_SCRAPE"])
comps, byid = comp_index(doc)
ids = [int(x) for x in os.environ["MJ_IDS"].split(",")]
missing = [i for i in ids if i not in byid]
if missing:
    err("NOT_FOUND", "No comp with id %s in the scrape." % ", ".join(map(str, missing)))
if len(set(ids)) != len(ids):
    err("INVALID_ARGUMENT", "A comp id is listed twice.")
warnings = []
aep = os.environ["MJ_AEP"]
require_same_project(doc, aep)
keep, footage_ids = comp_closure(byid, ids)
fnames = {f.get("id"): f.get("name") for f in doc["footage"] if isinstance(f, dict)}
# Expressions in kept comps that name a comp which will not be in the new project break after extract
# (found running it in After Effects 26.5: comp("Main Comp") inside the extracted precomp).
kept_names = {byid[i]["name"] for i in keep}
outside = []
for cid in sorted(keep):
    for l in byid[cid].get("layers") or []:
        for e in (l.get("expressions") or []) if isinstance(l, dict) else []:
            for m in REF.finditer(e.get("expression", "") if isinstance(e, dict) else ""):
                if m.group(1) == "comp" and m.group(3) not in kept_names:
                    outside.append({"comp": byid[cid]["name"], "layer": l.get("name"), "path": e.get("propertyPath"), "references": m.group(3)})
if outside:
    warnings.append({"code": "EXTERNAL_REFERENCES", "message": "%d expression(s) refer to comps that will not be in the new project (%s); they will error after the extract." % (
        len(outside), ", ".join(sorted({o["references"] for o in outside})))})
body = {"extract": {"compIds": ids, "compNames": [byid[i]["name"] for i in ids]}}
job, plan, cloned = make_job("extract", os.environ["MJ_LABEL"], aep, os.environ["MJ_OUT"], body, os.environ["MJ_RUNNER"], os.environ["MJ_SCRAPE"])
print(json.dumps({"ok": True, "data": {
    "schema": "MJ_AE_JOB_PLAN_1", "kind": "extract", "job": job, "runScript": os.path.join(job, "run.jsx"), "result": plan["result"],
    "source": plan["source"], "copiedInstantly": cloned,
    "comps": [{"id": i, "name": byid[i]["name"]} for i in ids],
    "keeps": {"comps": sorted(byid[i]["name"] for i in keep), "footage": sorted(str(fnames.get(i, i)) for i in footage_ids)},
    "removes": {"comps": len(comps) - len(keep), "footage": max(len(fnames) - len(footage_ids), 0)},
    "externalReferences": outside[:50],
    "_warnings": warnings,
}}))
PY_EXTRACT
) || true
  frames_emit_python_result "$_out"
}

handle_project_conform() {
  local _rc=0 _aep="" _scrape _spec="" _fmt="plan" _outdir="" _label="" _out a
  require_arg input || { emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  _scrape="$MJ_REQUIRED_ARG_VALUE"
  request_arg_present format && _fmt=$(request_arg_get format)
  case "$_fmt" in plan|job) ;; *) set_error "INVALID_ARGUMENT" "format must be plan (default) or job."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65 ;; esac
  request_arg_present spec && _spec=$(request_arg_get spec)
  if [ -n "$_spec" ]; then
    is_absolute_path "$_spec" || { set_error "INVALID_PATH" "Spec path must be absolute."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
    [ -f "$_spec" ] || { set_error "NOT_FOUND" "Studio spec not found."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 66; }
  fi
  if [ "$_fmt" = job ]; then
    for a in path output label; do require_arg "$a" || { emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }; done
    _aep=$(request_arg_get path); _outdir=$(request_arg_get output); _label=$(request_arg_get label)
    aejob_require_inputs "$_aep" "$_scrape" || { _rc=$?; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return $_rc; }
    aejob_require_job_output "$_outdir" "$_label" || { _rc=$?; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return $_rc; }
  else
    project_require_scrape_file "$_scrape" || { _rc=$?; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return $_rc; }
  fi
  _out=$(MJ_AEP="$_aep" MJ_SCRAPE="$_scrape" MJ_SPEC="$_spec" MJ_FMT="$_fmt" MJ_OUT="$_outdir" MJ_LABEL="$_label" MJ_RUNNER="$(aejob_runner_path)" aejob_python <<'PY_CONFORM'
id0 = tree_id(os.environ["MJ_SCRAPE"])
doc = load_scrape(os.environ["MJ_SCRAPE"])
spec = dict(DEFAULT_STUDIO_SPEC)
if os.environ["MJ_SPEC"]:
    spec.update(parse_studio_spec(os.environ["MJ_SPEC"]))
plan = plan_conform(doc, spec)
warnings = []
old = str(doc.get("scraperVersion", "")) < "1.1"
if old:
    warnings.append({"code": "SCRAPE_TOO_OLD", "message": "This scrape is from scraper %s; labels, folders, solids and adjustment layers need scraper 1.1, so only names and expressions are planned." % doc.get("scraperVersion")})
if any(c.get("layersTruncated") for c in doc["comps"] if isinstance(c, dict)) or doc.get("compsTruncated"):
    warnings.append({"code": "SCRAPE_TRUNCATED", "message": "The scrape is truncated; comps or layers beyond its limits are not in the plan."})
if plan.get("nameTooLong"):
    warnings.append({"code": "NAME_TOO_LONG", "message": "%d comp or layer name(s) are longer than After Effects allows (255 characters), so they are not from After Effects and were left out of the plan." % plan["nameTooLong"]})
if plan["dynamicReferences"]:
    warnings.append({"code": "DYNAMIC_REFERENCES", "message": "%d expression(s) look layers or comps up by a computed name; those references cannot be followed and may need a look after renaming." % plan["dynamicReferences"]})
counts = {k: len(plan[k]) for k in ("itemRenames", "layerRenames", "expressions", "layerLabels", "itemLabels", "moves")}
data = {"schema": "MJ_CONFORM_PLAN_1", "projectName": doc.get("projectName"), "specName": spec.get("name"), "spec": os.environ["MJ_SPEC"] or "built-in",
        "counts": counts, "changes": sum(counts.values()), "plan": plan, "job": None}
if os.environ["MJ_FMT"] == "job":
    aep = os.environ["MJ_AEP"]
    require_same_project(doc, aep)
if os.environ["MJ_FMT"] == "job" and data["changes"] == 0:
    warnings.append({"code": "NOTHING_TO_DO", "message": "The project already matches the spec, so no job was made."})
elif os.environ["MJ_FMT"] == "job":
    body = {"conform": {k: plan[k] for k in ("itemRenames", "layerRenames", "expressions", "layerLabels", "itemLabels", "moves")}, "specName": spec.get("name")}
    job, jp, cloned = make_job("conform", os.environ["MJ_LABEL"], aep, os.environ["MJ_OUT"], body, os.environ["MJ_RUNNER"], os.environ["MJ_SCRAPE"])
    data["job"] = {"folder": job, "runScript": os.path.join(job, "run.jsx"), "result": jp["result"], "source": jp["source"], "copiedInstantly": cloned}
data["sourceUnchanged"] = tree_id(os.environ["MJ_SCRAPE"]) == id0
data["_warnings"] = warnings
print(json.dumps({"ok": True, "data": data}))
PY_CONFORM
) || true
  frames_emit_python_result "$_out"
}

handle_project_jobcheck() {
  local _rc=0 _job _out
  require_arg path || { emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  _job="$MJ_REQUIRED_ARG_VALUE"
  is_absolute_path "$_job" || { set_error "INVALID_PATH" "Job path must be absolute."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  [ -d "$_job" ] && [ -f "$_job/plan.json" ] || { set_error "INVALID_TARGET" "That is not a job folder (no plan.json)."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  mj_require_local_existing_path "$_job" || { emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 73; }
  cap_available python3 || { set_error "UNSUPPORTED" "Job checks require python3."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 69; }
  _out=$(MJ_JOB="$_job" aejob_python <<'PY_JOBCHECK'
job = os.path.realpath(os.environ["MJ_JOB"])
try:
    plan = json.load(open(os.path.join(job, "plan.json"), encoding="utf-8"))
    assert plan.get("schema") == "MJ_AE_JOB_1"
except Exception:
    err("INVALID_RECEIPT", "plan.json is not a MographJailed job plan.")
inside = lambda p: os.path.realpath(p).startswith(job + os.sep)
if not all(inside(plan.get(k, "/")) for k in ("work", "result", "receipt", "quietFlag")):
    err("INVALID_RECEIPT", "The plan points outside its job folder.")
checks = []
def add(name, ok, msg):
    checks.append({"check": name, "ok": ok, "message": msg})
src = plan["source"]["path"]
if os.path.isfile(src):
    same = sha256_file(src) == plan["source"]["sha256"]
    add("originalUnchanged", same, "The original project is byte-for-byte what it was when the job was made." if same else
        "The original project has changed since the job was made (you saved it in After Effects); the job was still applied to the copy.")
else:
    add("originalUnchanged", False, "The original project is no longer at %s." % src)
w = plan["work"]
add("copyUnchanged", os.path.isfile(w) and sha256_file(w) == plan["workSha256"], "before.aep is still the copy the job started from." if os.path.isfile(w) and sha256_file(w) == plan["workSha256"] else "before.aep was changed or removed.")
status, result = "notRun", None
if os.path.isfile(plan["receipt"]):
    try:
        result = json.load(open(plan["receipt"], encoding="utf-8"))
        status = result.get("status", "unknown")
    except Exception:
        status = "unreadable"
add("ran", status != "notRun", "After Effects ran the job (%s)." % status if status != "notRun" else "The job has not been run in After Effects yet.")
res = plan["result"]
has_result = os.path.isfile(res) and os.path.getsize(res) > 0
if status != "notRun":
    add("resultSaved", has_result, "result.aep was saved (%d bytes)." % os.path.getsize(res) if has_result else "There is no result.aep.")
# Complete: After Effects applied it, saved the result, and the copy it worked from is intact. Whether the
# original changed since is reported, not held against the job (you may have kept working on it).
ok = status in ("done", "partial") and has_result and checks[1]["ok"]
print(json.dumps({"ok": True, "data": {
    "schema": "MJ_AE_JOB_CHECK_1", "job": job, "kind": plan.get("kind"), "label": plan.get("label"), "status": status, "complete": ok,
    "result": res if has_result else None, "checks": checks,
    "applied": (result or {}).get("applied"), "steps": (result or {}).get("steps"),
    "skipped": (result or {}).get("skipped", [])[:50], "errors": (result or {}).get("errors", [])[:50],
    "itemsBefore": (result or {}).get("itemsBefore"), "itemsAfter": (result or {}).get("itemsAfter"),
}}))
PY_JOBCHECK
) || true
  frames_emit_python_result "$_out"
}
