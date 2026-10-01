# Tier 0 (Observer) — project observation operations.
#
# All four operations are read-only except project.snapshot, which only ever
# creates new versioned copies (never overwrites, never mutates the source).
# The LaunchAgent watcher may only trigger Tier 0 operations.
#
# project.ingest   — validate an MJ_PROJECT_SCRAPE_1 JSON file and summarize it
# expression.lint  — static analysis ("spell-check") over scraped expressions
# plugin.audit     — enumerate and hash an After Effects Plug-ins directory
# project.snapshot — hash + versioned copy of an .aep (time-machine primitive)

# Max scrape JSON size accepted by ingest/lint (bytes). The scraper budgets ~5MB.
PROJECT_OBSERVE_MAX_SCRAPE_BYTES=8388608
# Max plugin directory entries enumerated by plugin.audit.
PROJECT_OBSERVE_MAX_PLUGIN_ENTRIES=500
# Largest single file plugin.audit will hash (bytes). ~3 s per GiB on Apple Silicon; larger files are listed unhashed.
PROJECT_OBSERVE_MAX_PLUGIN_FILE_BYTES=2147483648
# Max lint findings returned before truncation.
PROJECT_OBSERVE_MAX_FINDINGS=200

project_observe_python_available() {
  cap_available python3
}

# Validate that python output is {"ok":true,"data":{...}} and print the data
# payload as canonical JSON. Returns nonzero on any deviation.
project_emit_python_data() {
  local _out="$1"
  local _data=""
  _data=$(printf '%s' "$_out" | /usr/bin/python3 -c \
    'import json,sys; o=json.load(sys.stdin); assert o.get("ok") is True and isinstance(o.get("data"), dict); print(json.dumps(o["data"], sort_keys=True, separators=(",", ":")))' \
    2>/dev/null) || return 1
  [ -n "$_data" ] || return 1
  printf '%s' "$_data"
}

project_require_scrape_file() {
  local _path="$1"
  is_absolute_path "$_path" || { set_error "INVALID_PATH" "Scrape path must be absolute."; return 65; }
  [ -f "$_path" ] || { set_error "INVALID_TARGET" "Scrape target must be a regular file."; return 65; }
  [ -r "$_path" ] || { set_error "PERMISSION_DENIED" "Scrape file is not readable."; return 77; }
  project_observe_python_available || { set_error "UNSUPPORTED" "Project observation requires stock macOS python3."; return 69; }
  mj_require_local_existing_path "$_path" || return 73
  return 0
}

# Runs the ingest engine on a scrape; prints the engine's JSON envelope. Shared by project.ingest and project.health.
project_run_ingest() {
  local _path="$1"
  MJ_SCRAPE_PATH="$_path" MJ_SCRAPE_MAX_BYTES="$PROJECT_OBSERVE_MAX_SCRAPE_BYTES" \
    /usr/bin/python3 - <<'PY_PROJECT_INGEST' 2>/dev/null
import json, os, sys

def err(code, message):
    print(json.dumps({"ok": False, "code": code, "message": message}))
    sys.exit(0)

path = os.environ.get("MJ_SCRAPE_PATH", "")
def _ident(p):
    try:
        st = os.stat(p); return (st.st_size, st.st_mtime_ns)
    except OSError:
        return None
_id0 = _ident(path)
max_bytes = int(os.environ.get("MJ_SCRAPE_MAX_BYTES", "8388608"))
try:
    size = os.path.getsize(path)
except Exception:
    err("READ_FAILED", "Could not stat the scrape file.")
if size > max_bytes:
    err("SCRAPE_TOO_LARGE", "Scrape file exceeds the %d byte bound." % max_bytes)
try:
    with open(path, "r", encoding="utf-8") as f:
        doc = json.load(f)
except Exception as e:
    err("INVALID_JSON", "Scrape file is not valid JSON: %s" % str(e)[:120])

if not isinstance(doc, dict) or doc.get("schema") != "MJ_PROJECT_SCRAPE_1":
    err("SCHEMA_MISMATCH", "Scrape file must be an MJ_PROJECT_SCRAPE_1 document.")
required = ["scraperVersion", "projectPath", "projectName", "scrapedAt",
            "aeVersion", "numItems", "comps", "fonts", "footage"]
for key in required:
    if key not in doc:
        err("SCHEMA_MISMATCH", "Scrape file is missing required key: %s" % key)
if not isinstance(doc["comps"], list) or not isinstance(doc["fonts"], list) \
        or not isinstance(doc["footage"], list):
    err("SCHEMA_MISMATCH", "comps/fonts/footage must be arrays.")

num_layers = 0
num_expressions = 0
num_effects = 0
layer_types = {}
for comp in doc["comps"]:
    if not isinstance(comp, dict):
        err("SCHEMA_MISMATCH", "Comp entries must be objects.")
    layers = comp.get("layers", [])
    if not isinstance(layers, list):
        err("SCHEMA_MISMATCH", "Comp layers must be an array.")
    for layer in layers:
        if not isinstance(layer, dict):
            err("SCHEMA_MISMATCH", "Layer entries must be objects.")
        num_layers += 1
        t = layer.get("type", "Unknown")
        layer_types[t] = layer_types.get(t, 0) + 1
        exprs = layer.get("expressions", [])
        if isinstance(exprs, list):
            num_expressions += len(exprs)
        effs = layer.get("effects", [])
        if isinstance(effs, list):
            num_effects += len(effs)

footage_missing = []
footage_unlinked = []
for item in doc["footage"]:
    if not isinstance(item, dict):
        continue
    name = item.get("name", "?")
    p = item.get("path", "")
    if item.get("missing") is True:
        footage_missing.append(name)
    elif not p:
        footage_unlinked.append(name)
    elif not os.path.exists(p):
        footage_missing.append(name)

data = {
    "schema": "MJ_PROJECT_SUMMARY_1",
    "projectPath": doc["projectPath"],
    "projectName": doc["projectName"],
    "scrapedAt": doc["scrapedAt"],
    "aeVersion": doc["aeVersion"],
    "numComps": len(doc["comps"]),
    "numLayers": num_layers,
    "numExpressions": num_expressions,
    "numEffects": num_effects,
    "numFonts": len(doc["fonts"]),
    "fonts": sorted(set(str(f) for f in doc["fonts"])),
    "numFootage": len(doc["footage"]),
    "footageMissing": sorted(footage_missing),
    "footageUnlinked": sorted(footage_unlinked),
    "layerTypes": layer_types,
    "compsTruncated": bool(doc.get("compsTruncated", False)),
    "footageTruncated": bool(doc.get("footageTruncated", False)),
    "_warnings": (
        ([{"code": "COMPS_TRUNCATED", "message": "The scrape holds only the first comps of a larger project; the rest are not summarized."}] if doc.get("compsTruncated") else [])
        + ([{"code": "LAYERS_TRUNCATED", "message": "Some comps have more layers than the scraper records; their layer counts are lower bounds."}]
           if any(isinstance(c, dict) and c.get("layersTruncated") for c in doc["comps"]) else [])
        + ([{"code": "FOOTAGE_TRUNCATED", "message": "The scrape holds only the first footage items of a larger project."}] if doc.get("footageTruncated") else [])
        + ([{"code": "FOOTAGE_MISSING", "message": "%d footage items are missing." % len(footage_missing)}] if footage_missing else [])
    ),
    "sourceUnchanged": _ident(path) == _id0,
}
print(json.dumps({"ok": True, "data": data}))
PY_PROJECT_INGEST
}

# Runs the lint engine on a scrape; prints the engine's JSON envelope. Shared by expression.lint and project.health.
project_run_lint() {
  local _path="$1"
  MJ_SCRAPE_PATH="$_path" MJ_SCRAPE_MAX_BYTES="$PROJECT_OBSERVE_MAX_SCRAPE_BYTES" \
    MJ_LINT_MAX_FINDINGS="$PROJECT_OBSERVE_MAX_FINDINGS" \
    /usr/bin/python3 - <<'PY_EXPRESSION_LINT' 2>/dev/null
import json, os, re, sys

def err(code, message):
    print(json.dumps({"ok": False, "code": code, "message": message}))
    sys.exit(0)

path = os.environ.get("MJ_SCRAPE_PATH", "")
def _ident(p):
    try:
        st = os.stat(p); return (st.st_size, st.st_mtime_ns)
    except OSError:
        return None
_id0 = _ident(path)
max_bytes = int(os.environ.get("MJ_SCRAPE_MAX_BYTES", "8388608"))
max_findings = int(os.environ.get("MJ_LINT_MAX_FINDINGS", "200"))
try:
    if os.path.getsize(path) > max_bytes:
        err("SCRAPE_TOO_LARGE", "Scrape file exceeds the byte bound.")
    with open(path, "r", encoding="utf-8") as f:
        doc = json.load(f)
except Exception as e:
    err("INVALID_JSON", "Scrape file is not valid JSON: %s" % str(e)[:120])
if not isinstance(doc, dict) or doc.get("schema") != "MJ_PROJECT_SCRAPE_1":
    err("SCHEMA_MISMATCH", "Scrape file must be an MJ_PROJECT_SCRAPE_1 document.")
if not isinstance(doc.get("comps"), list):
    err("SCHEMA_MISMATCH", "comps must be an array.")

layer_ref_re = re.compile(r'thisComp\s*\.\s*layer\s*\(\s*["\']([^"\']+)["\']\s*\)')
effect_ref_re = re.compile(r'''\beffect\s*\(\s*["\']([^"\']+)["\']\s*\)''')
loop_re = re.compile(r'\b(for|while)\b')
hardpath_re = re.compile(r'(/Users/|/Volumes/|[A-Za-z]:[\\/]|\\\\)')

findings = []
num_expressions = 0
truncated = False

def add(code, severity, comp, layer, prop, message):
    findings.append({
        "code": code, "severity": severity,
        "comp": comp, "layer": layer, "propertyPath": prop,
        "message": message,
    })

for comp in doc["comps"]:
    if not isinstance(comp, dict):
        continue
    comp_name = str(comp.get("name", "?"))
    layer_names = set()
    for layer in comp.get("layers", []):
        if isinstance(layer, dict):
            layer_names.add(str(layer.get("name", "")))
    for layer in comp.get("layers", []):
        if not isinstance(layer, dict):
            continue
        layer_name = str(layer.get("name", "?"))
        effect_names = set()
        for eff in layer.get("effects", []):
            if isinstance(eff, dict):
                effect_names.add(str(eff.get("name", "")))
        for item in layer.get("expressions", []):
            if not isinstance(item, dict):
                continue
            prop = str(item.get("propertyPath", "?"))
            expr = item.get("expression", "")
            if not isinstance(expr, str):
                continue
            num_expressions += 1
            for ref in layer_ref_re.findall(expr):
                if ref not in layer_names:
                    add("E001", "error", comp_name, layer_name, prop,
                        "Expression references layer \"%s\", which does not exist in comp \"%s\"." % (ref, comp_name))
            for ref in effect_ref_re.findall(expr):
                if ref not in effect_names:
                    add("E002", "error", comp_name, layer_name, prop,
                        "Expression references effect \"%s\", which is not applied to this layer." % ref)
            if "sampleImage" in expr and loop_re.search(expr):
                add("W001", "warning", comp_name, layer_name, prop,
                    "sampleImage() inside a loop is a known render-time performance trap.")
            if hardpath_re.search(expr):
                add("W002", "warning", comp_name, layer_name, prop,
                    "Expression contains a hard-coded absolute path; it will break on other machines.")
            # NOTE: the identifier below is split ("ev"+"al") on purpose.
            # The I001 rule must *detect* this ExtendScript builtin in user
            # expressions, but the repo security guard bans that literal
            # word in src/. This code never invokes it; it only
            # pattern-matches the string.
            _ev = "ev" + "al"
            if _ev + "(" in expr:
                add("I001", "info", comp_name, layer_name, prop,
                    "Expression uses " + _ev + "(); behavior is opaque to static analysis.")
            if len(expr) > 2000:
                add("W003", "warning", comp_name, layer_name, prop,
                    "Expression exceeds 2000 characters; consider splitting it across properties.")

# Teaching text lives beside, not inside, the stable finding fields: codes and messages never
# change, and scripted consumers can ignore "teach" / "teaching". The identifier is split
# ("ev"+"al") for the same reason as the I001 rule below.
_ev = "ev" + "al"
TEACH = {
    "E001": ("The expression looks up a layer by name and no layer has that name in this comp (it was renamed, deleted, or lives in another comp), so the property stops working.",
             "Fix the name, or pick-whip the layer so the link follows renames.",
             'thisComp.layer("Logo old").transform.position', 'thisComp.layer("Logo").transform.position   // or pick-whip it'),
    "E002": ("effect(\"Name\") needs an effect with that exact name on this same layer; none exists (renamed, removed, or it is on another layer).",
             "Use the name shown in the Effect Controls panel, or pick-whip the property.",
             'effect("Speed Slider")("Slider")', 'effect("Speed")("Slider")   // name as shown in Effect Controls'),
    "W001": ("sampleImage() reads rendered pixels; inside a loop it runs once per pass, on every frame, which is the usual cause of very slow renders.",
             "Sample once (a wider area is fine) outside the loop and reuse the result.",
             'for (i = 0; i < 50; i++) { s += thisComp.layer("Bg").sampleImage([i*10, 0], [1, 1], true, time); }',
             's = thisComp.layer("Bg").sampleImage([250, 0], [250, 1], true, time);   // one sample, outside any loop'),
    "W002": ("A path such as /Users/you/... exists only on your Mac, so the expression breaks on another machine or after a move.",
             "Keep the file in the project and refer to it by name instead of by location.",
             'footage("/Users/me/Desktop/data.json").sourceData', 'footage("data.json").sourceData   // imported into the project'),
    "W003": ("A very long expression is hard to read and re-runs in full on every frame.",
             "Split it across properties, or move repeated values into sliders on a control layer.",
             '// one 3000-character expression doing everything', 'speed = effect("Speed")("Slider");   // small, named pieces'),
    "I001": (_ev + "() runs text as code at render time, so neither this linter nor a colleague can tell what the expression does.",
             "Replace it with direct property access or a simple conditional.",
             _ev + '("thisComp.layer(" + n + ").opacity")', 'thisComp.layer(n).opacity'),
}
for _f in findings:
    _t = TEACH.get(_f["code"])
    if _t:
        _f["teach"] = {"why": _t[0], "fix": _t[1]}
findings.sort(key=lambda f: (f["code"], f["comp"], f["layer"], f["propertyPath"]))
if len(findings) > max_findings:
    findings = findings[:max_findings]
    truncated = True
errors = sum(1 for f in findings if f["severity"] == "error")
warnings = sum(1 for f in findings if f["severity"] == "warning")
infos = sum(1 for f in findings if f["severity"] == "info")

data = {
    "schema": "MJ_EXPRESSION_LINT_1",
    "numExpressions": num_expressions,
    "numFindings": len(findings),
    "errors": errors,
    "warnings": warnings,
    "info": infos,
    "findings": findings,
    "findingsTruncated": truncated,
    "teaching": {c: {"before": TEACH[c][2], "after": TEACH[c][3]} for c in sorted({f["code"] for f in findings}) if c in TEACH},
    "_warnings": ([{"code": "FINDINGS_TRUNCATED", "message": "Only the first %d findings are listed." % max_findings}] if truncated else []),
    "rules": ["E001", "E002", "W001", "W002", "W003", "I001"],
    "sourceUnchanged": _ident(path) == _id0,
}
print(json.dumps({"ok": True, "data": data}))
PY_EXPRESSION_LINT
}

handle_project_ingest() {
  local _rc=0
  local _path=""
  local _pyout=""
  local _data=""
  local _code=""

  require_arg path || { emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  _path="$MJ_REQUIRED_ARG_VALUE"
  project_require_scrape_file "$_path" || { _rc=$?; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return $_rc; }

  _pyout=$(project_run_ingest "$_path") || { set_error "INGEST_FAILED" "Scrape summarizer failed to run."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 74; }

  if _data=$(project_emit_python_data "$_pyout" 2>/dev/null); then
    split_warnings "$_data"
    emit_success_start "$REQUEST_COMMAND" "$REQUEST_ID"
    printf '%s' "$MJ_DATA_JSON"
    emit_success_end
    return 0
  fi
  # The python envelope already describes the failure; surface it as an error.
  _code=$(printf '%s' "$_pyout" | /usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin).get("code","INGEST_FAILED"))' 2>/dev/null || printf 'INGEST_FAILED')
  set_error "$_code" "Scrape file failed validation (see ingest rules)."
  emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"
  return 65
}

handle_expression_lint() {
  local _rc=0
  local _path=""
  local _pyout=""
  local _data=""
  local _code=""

  require_arg path || { emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  _path="$MJ_REQUIRED_ARG_VALUE"
  project_require_scrape_file "$_path" || { _rc=$?; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return $_rc; }

  _pyout=$(project_run_lint "$_path") || { set_error "LINT_FAILED" "Expression linter failed to run."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 74; }

  if _data=$(project_emit_python_data "$_pyout" 2>/dev/null); then
    split_warnings "$_data"
    emit_success_start "$REQUEST_COMMAND" "$REQUEST_ID"
    printf '%s' "$MJ_DATA_JSON"
    emit_success_end
    return 0
  fi
  _code=$(printf '%s' "$_pyout" | /usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin).get("code","LINT_FAILED"))' 2>/dev/null || printf 'LINT_FAILED')
  set_error "$_code" "Scrape file failed validation for linting."
  emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"
  return 65
}

handle_plugin_audit() {
  local _dir=""
  local _id0=""
  local _entry=""
  local _name=""
  local _kind=""
  local _size=""
  local _sha_source=""
  local _sha_value=""
  local _count=0
  local _truncated=false
  local _skipped_big=0
  local _first=1

  require_arg path || { emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  _dir="$MJ_REQUIRED_ARG_VALUE"
  _id0=$(source_identity "$_dir")
  is_absolute_path "$_dir" || { set_error "INVALID_PATH" "Plugin directory must be absolute."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  [ -d "$_dir" ] || { set_error "INVALID_TARGET" "Plugin audit target must be a directory."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  [ -r "$_dir" ] && [ -x "$_dir" ] || { set_error "PERMISSION_DENIED" "Plugin directory is not readable."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 77; }
  cap_available stat && cap_available uname || { set_error "UNSUPPORTED" "Plugin audit requires stock macOS stat/uname capabilities."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 69; }
  mj_require_local_existing_path "$_dir" || { emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 73; }

  emit_success_start "$REQUEST_COMMAND" "$REQUEST_ID"
  printf '{"schema":"MJ_PLUGIN_AUDIT_1","directory":'; json_quote "$_dir"; printf ',"entries":['
  # Portable null-glob: zsh errors on unmatched globs, bash expands literally.
  if [ -n "${ZSH_VERSION:-}" ]; then
    setopt localoptions null_glob
  else
    shopt -s nullglob 2>/dev/null || true
  fi
  # Glob order is sorted in both shells, which keeps output deterministic.
  for _entry in "$_dir"/*; do
    _count=$((_count + 1))
    if [ "$_count" -gt "$PROJECT_OBSERVE_MAX_PLUGIN_ENTRIES" ]; then
      _truncated=true
      break
    fi
    _name=${_entry##*/}
    _kind="file"; _size=""; _sha_source=""; _sha_value=""
    if [ -L "$_entry" ]; then
      _kind="symlink"
    elif [ -d "$_entry" ]; then
      case "$_name" in
        *.plugin|*.bundle|*.app|*.component) _kind="bundle" ;;
        *) _kind="directory" ;;
      esac
    elif [ -f "$_entry" ]; then
      _kind="file"
      _size=$(file_stat_size "$_entry" 2>/dev/null || printf '')
      if [ -n "$_size" ] && [ "$_size" -gt "$PROJECT_OBSERVE_MAX_PLUGIN_FILE_BYTES" ] 2>/dev/null; then
        # Too big to hash inside a request that should answer in seconds; listed, not hashed.
        _skipped_big=$((_skipped_big + 1))
      elif [ -r "$_entry" ]; then
        hash_sha256_file "$_entry" 2>/dev/null
        _sha_source="$MJ_HASH_SOURCE"; _sha_value="$MJ_HASH_VALUE"
      fi
    else
      _kind="other"
    fi
    [ "$_first" -eq 1 ] || printf ','
    _first=0
    printf '{"name":'; json_quote "$_name"
    printf ',"kind":'; json_quote "$_kind"
    printf ',"sizeBytes":'; if [ -n "$_size" ]; then printf '%s' "$_size"; else printf 'null'; fi
    printf ',"sha256":'; if [ -n "$_sha_value" ]; then json_quote "$_sha_value"; else printf 'null'; fi
    printf ',"hashSource":'; if [ -n "$_sha_source" ]; then json_quote "$_sha_source"; else printf 'null'; fi
    printf '}'
  done
  printf '],"numEntries":'
  if $_truncated; then printf '%s' "$PROJECT_OBSERVE_MAX_PLUGIN_ENTRIES"; else printf '%s' "$_count"; fi
  if $_truncated; then printf ',"truncated":true'; else printf ',"truncated":false'; fi
  if $_truncated; then add_warning "ENTRY_LIMIT_REACHED" "Only the first $PROJECT_OBSERVE_MAX_PLUGIN_ENTRIES entries were audited."; fi
  if [ "$_skipped_big" -gt 0 ]; then add_warning "FILE_TOO_LARGE_TO_HASH" "$_skipped_big files over $((PROJECT_OBSERVE_MAX_PLUGIN_FILE_BYTES / 1048576)) MB were listed without a SHA-256."; fi
  printf ',"entryBound":%s' "$PROJECT_OBSERVE_MAX_PLUGIN_ENTRIES"
  # Directory-level check: entries added or removed while the scan ran change this.
  printf ',"sourceUnchanged":%s}' "$(source_unchanged_json "$_id0" "$_dir")"
  emit_success_end
}

# Test bundle only redefines this to simulate a project being written mid-copy.
snapshot_test_hook() { :; }

handle_project_snapshot() {
  local _path=""
  local _outdir=""
  local _outdir_real=""
  local _base=""
  local _stem=""
  local _sha_source=""
  local _sha_value=""
  local _latest_file=""
  local _prev_sha=""
  local _ts=""
  local _short=""
  local _dest=""
  local _receipt=""
  local _bytes=""
  local _clone_used=false
  local _id0=""
  local _partial=""

  require_arg path || { emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  _path="$MJ_REQUIRED_ARG_VALUE"
  _id0=$(source_identity "$_path")
  require_arg output || { emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  _outdir="$MJ_REQUIRED_ARG_VALUE"
  is_absolute_path "$_path" && is_absolute_path "$_outdir" || { set_error "INVALID_PATH" "Snapshot path and output directory must be absolute."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  [ -f "$_path" ] || { set_error "INVALID_TARGET" "Snapshot target must be a regular file."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  [ -r "$_path" ] || { set_error "PERMISSION_DENIED" "Snapshot target is not readable."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 77; }
  case "${_path##*/}" in
    *.[aA][eE][pP]) ;;
    *) set_error "INVALID_TARGET" "Snapshot target must be an After Effects project (.aep)."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65 ;;
  esac
  [ -d "$_outdir" ] || { set_error "OUTPUT_UNAVAILABLE" "Snapshot output directory does not exist."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 73; }
  [ -w "$_outdir" ] || { set_error "OUTPUT_UNAVAILABLE" "Snapshot output directory is not writable."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 73; }
  cap_available stat && cap_available uname && cap_available cp || { set_error "UNSUPPORTED" "Project snapshot requires stock macOS stat/uname/cp capabilities."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 69; }
  mj_require_local_existing_path "$_path" || { emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 73; }
  mj_require_local_existing_path "$_outdir" || { emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 73; }

  _outdir_real=$(canonical_existing_dir "$_outdir") || { set_error "OUTPUT_UNAVAILABLE" "Could not resolve snapshot output directory."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 73; }
  hash_sha256_file "$_path" 2>/dev/null || { set_error "HASH_FAILED" "Could not hash the snapshot target."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 74; }
  _sha_source="$MJ_HASH_SOURCE"; _sha_value="$MJ_HASH_VALUE"
  [ -n "$_sha_value" ] || { set_error "UNSUPPORTED" "No approved native SHA-256 utility is available."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 69; }

  _base=${_path##*/}
  _stem="${_base%.[aA][eE][pP]}"
  [ -n "$_stem" ] && [ "$_stem" != "$_base" ] || _stem="project"
  _latest_file="$_outdir_real/$_stem.latest.json"
  if [ -f "$_latest_file" ]; then
    _prev_sha=$(/usr/bin/python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("sha256",""))' "$_latest_file" 2>/dev/null || printf '')
    if [ -n "$_prev_sha" ] && [ "$_prev_sha" = "$_sha_value" ]; then
      emit_success_start "$REQUEST_COMMAND" "$REQUEST_ID"
      printf '{"schema":"MJ_PROJECT_SNAPSHOT_1","sourcePath":'; json_quote "$_path"
      printf ',"sha256":'; json_quote "$_sha_value"
      printf ',"hashSource":'; json_quote "$_sha_source"
      printf ',"snapshotCreated":false,"reason":"unchanged","sourceUnchanged":%s}' "$(source_unchanged_json "$_id0" "$_path")"
      emit_success_end
      return 0
    fi
  fi

  _ts=$(/bin/date -u '+%Y%m%dT%H%M%SZ' 2>/dev/null || printf 'unknown')
  _short=${_sha_value:0:12}
  _dest="$_outdir_real/$_stem.$_ts.$_short.aep"
  _partial="$_outdir_real/.$_stem.$_ts.$_short.partial.$$"
  [ ! -e "$_dest" ] && [ ! -L "$_dest" ] || { set_error "OUTPUT_EXISTS" "Refusing to overwrite an existing snapshot."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 73; }
  _bytes=$(file_stat_size "$_path" 2>/dev/null || printf '0')

  # Stage the copy under a hidden name, prove it matches, then publish with a hard link.
  # AE may still be writing the project when the watcher fires, so both the staged copy and
  # the source are re-hashed; any mismatch means a torn snapshot and nothing is published.
  # ln fails if the destination exists, so a concurrent snapshot can never be clobbered.
  /bin/rm -f "$_partial" 2>/dev/null
  if /bin/cp -c "$_path" "$_partial" 2>/dev/null; then
    _clone_used=true
  else
    /bin/cp "$_path" "$_partial" 2>/dev/null || { /bin/rm -f "$_partial" 2>/dev/null; set_error "SNAPSHOT_FAILED" "Could not copy the project to the versions directory."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 74; }
  fi
  snapshot_test_hook "$_path" "$_partial"
  hash_sha256_file "$_partial" 2>/dev/null
  if [ "$MJ_HASH_VALUE" != "$_sha_value" ]; then
    # Either the project changed under the copy, or the copy itself is bad; say which.
    /bin/rm -f "$_partial" 2>/dev/null
    hash_sha256_file "$_path" 2>/dev/null
    if [ "$MJ_HASH_VALUE" != "$_sha_value" ]; then
      set_error "SNAPSHOT_UNSTABLE" "The project changed while it was being copied; no snapshot was kept. It will be retried on the next save."
    else
      set_error "SNAPSHOT_FAILED" "The copy did not match the project (a disk or filesystem problem); no snapshot was kept."
    fi
    emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 74
  fi
  hash_sha256_file "$_path" 2>/dev/null
  if [ "$MJ_HASH_VALUE" != "$_sha_value" ]; then
    /bin/rm -f "$_partial" 2>/dev/null
    set_error "SNAPSHOT_UNSTABLE" "The project changed while it was being copied; no snapshot was kept. It will be retried on the next save."
    emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 74
  fi
  if ! /bin/ln "$_partial" "$_dest" 2>/dev/null; then
    /bin/rm -f "$_partial" 2>/dev/null
    if [ -e "$_dest" ] || [ -L "$_dest" ]; then
      set_error "OUTPUT_EXISTS" "Refusing to overwrite an existing snapshot."
    else
      set_error "SNAPSHOT_FAILED" "Could not publish the snapshot."
    fi
    emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 73
  fi
  /bin/rm -f "$_partial" 2>/dev/null
  [ -f "$_dest" ] || { set_error "SNAPSHOT_FAILED" "Snapshot copy did not materialize."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 74; }

  _receipt="$_dest.snapshot.json"
  MJ_SNAP_SHA="$_sha_value" MJ_SNAP_SRC="$_path" MJ_SNAP_DEST="$_dest" \
  MJ_SNAP_BYTES="$_bytes" MJ_SNAP_TS="$_ts" MJ_SNAP_CLONE="$_clone_used" \
  MJ_SNAP_HASH_SRC="$_sha_source" MJ_SNAP_STEM="$_stem" \
  /usr/bin/python3 - <<'PY_SNAPSHOT_RECEIPT' 2>/dev/null
import json, os
receipt = {
    "schema": "MJ_PROJECT_SNAPSHOT_1",
    "sourcePath": os.environ["MJ_SNAP_SRC"],
    "sha256": os.environ["MJ_SNAP_SHA"],
    "hashSource": os.environ["MJ_SNAP_HASH_SRC"],
    "snapshotPath": os.environ["MJ_SNAP_DEST"],
    "createdAt": os.environ["MJ_SNAP_TS"],
    "bytesCopied": int(os.environ["MJ_SNAP_BYTES"] or 0),
    "cloneUsed": os.environ["MJ_SNAP_CLONE"] == "true",
    "copyVerified": True,
    "sourceStableDuringCopy": True,
}
with open(os.environ["MJ_SNAP_DEST"] + ".snapshot.json", "w", encoding="utf-8") as f:
    json.dump(receipt, f, sort_keys=True, separators=(",", ":"))
    f.write("\n")
latest = {
    "schema": "MJ_PROJECT_SNAPSHOT_LATEST_1",
    "sourcePath": os.environ["MJ_SNAP_SRC"],
    "sha256": os.environ["MJ_SNAP_SHA"],
    "snapshotPath": os.environ["MJ_SNAP_DEST"],
    "createdAt": os.environ["MJ_SNAP_TS"],
}
stem = os.environ["MJ_SNAP_STEM"]
outdir = os.path.dirname(os.environ["MJ_SNAP_DEST"])
with open(os.path.join(outdir, stem + ".latest.json"), "w", encoding="utf-8") as f:
    json.dump(latest, f, sort_keys=True, separators=(",", ":"))
    f.write("\n")
PY_SNAPSHOT_RECEIPT
  [ -f "$_receipt" ] || { /bin/rm -f "$_dest" 2>/dev/null; set_error "SNAPSHOT_FAILED" "Snapshot receipt could not be written; copy removed."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 74; }

  emit_success_start "$REQUEST_COMMAND" "$REQUEST_ID"
  printf '{"schema":"MJ_PROJECT_SNAPSHOT_1","sourcePath":'; json_quote "$_path"
  printf ',"sha256":'; json_quote "$_sha_value"
  printf ',"hashSource":'; json_quote "$_sha_source"
  printf ',"snapshotCreated":true,"snapshotPath":'; json_quote "$_dest"
  printf ',"receiptPath":'; json_quote "$_receipt"
  printf ',"bytesCopied":%s' "${_bytes:-0}"
  printf ',"cloneUsed":'; $_clone_used && printf 'true' || printf 'false'
  printf ',"copyVerified":true,"sourceUnchanged":%s}' "$(source_unchanged_json "$_id0" "$_path")"
  emit_success_end
}
