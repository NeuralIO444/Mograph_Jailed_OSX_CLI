# Project insight — what changed, and how healthy is it. Both are read-only (Tier 0) and built on
# the existing ingest and lint engines; nothing here edits a project.
#
# project.diff   — compare two MJ_PROJECT_SCRAPE_1 receipts: comps, layers, expressions, footage,
#                  fonts and effect types added, removed or changed
# project.health — a 0-100 score from missing footage, expression problems and snapshot freshness.
#                  The formula is versioned (HEALTH_FORMULA_VERSION) and every point lost links back
#                  to the findings behind it. format=record keeps the score in the local store so
#                  it can be trended; format=all lists every recorded project with its trend.

HEALTH_FORMULA_VERSION=1

handle_project_diff() {
  local _rc=0 _a="" _b="" _out=""
  require_arg path || { emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  _a="$MJ_REQUIRED_ARG_VALUE"
  require_arg input || { emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  _b="$MJ_REQUIRED_ARG_VALUE"
  project_require_scrape_file "$_a" || { _rc=$?; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return $_rc; }
  project_require_scrape_file "$_b" || { _rc=$?; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return $_rc; }

  _out=$(MJ_A="$_a" MJ_B="$_b" protect_python <<'PY_PROJECT_DIFF'
MAX_CHANGES = 200
ida, idb = tree_id(os.environ["MJ_A"]), tree_id(os.environ["MJ_B"])
a, b = load_scrape(os.environ["MJ_A"]), load_scrape(os.environ["MJ_B"])
S = {k: 0 for k in ("compsAdded", "compsRemoved", "compsChanged", "layersAdded", "layersRemoved", "layersChanged", "expressionsChanged",
                    "footageAdded", "footageRemoved", "footageMissingChanged", "fontsAdded", "fontsRemoved", "effectsAdded", "effectsRemoved")}
changes = []
def note(kind, text, **extra):
    d = {"kind": kind, "text": text}; d.update(extra); changes.append(d)

def num(v):
    return v if isinstance(v, (int, float)) and not isinstance(v, bool) else None

def keyed(items, key_fn):
    """Key each item; duplicates get #2, #3 ... so same-named layers still pair up in order."""
    seen, out = {}, {}
    for it in items:
        k = key_fn(it)
        seen[k] = seen.get(k, 0) + 1
        out[k if seen[k] == 1 else "%s#%d" % (k, seen[k])] = it
    return out

def comps_of(doc):
    return [c for c in doc["comps"] if isinstance(c, dict)]

ca, cb = comps_of(a), comps_of(b)
ids_ok = all(isinstance(c.get("id"), int) and c["id"] > 0 for c in ca + cb) and len({c["id"] for c in ca}) == len(ca) and len({c["id"] for c in cb}) == len(cb)
ck = (lambda c: "id:%d" % c["id"]) if ids_ok else (lambda c: "name:%s" % c.get("name", ""))
A, B = keyed(ca, ck), keyed(cb, ck)

def eff_set(layer):
    out = {}
    for e in layer.get("effects") or []:
        if isinstance(e, dict) and e.get("matchName"):
            out[str(e["matchName"])] = str(e.get("name", e["matchName"]))
    return out

def exprs(layer):
    return {str(x.get("propertyPath", "")): str(x.get("expression", "")) for x in (layer.get("expressions") or []) if isinstance(x, dict)}

for k in sorted(set(B) - set(A)):
    S["compsAdded"] += 1; note("comp", 'comp "%s" added (%d layers)' % (B[k].get("name"), len(B[k].get("layers") or [])), comp=B[k].get("name"))
for k in sorted(set(A) - set(B)):
    S["compsRemoved"] += 1; note("comp", 'comp "%s" removed' % A[k].get("name"), comp=A[k].get("name"))
for k in sorted(set(A) & set(B)):
    x, y = A[k], B[k]
    cname = y.get("name")
    comp_changed = False
    if x.get("name") != y.get("name"):
        comp_changed = True; note("comp", 'comp renamed "%s" -> "%s"' % (x.get("name"), y.get("name")), comp=cname)
    for field, label in (("width", "width"), ("height", "height"), ("frameRate", "frame rate"), ("duration", "duration"), ("pixelAspect", "pixel aspect")):
        if num(x.get(field)) is not None and num(y.get(field)) is not None and x[field] != y[field]:
            comp_changed = True; note("comp", 'comp "%s": %s %s -> %s' % (cname, label, x[field], y[field]), comp=cname)
    LA = keyed([l for l in x.get("layers") or [] if isinstance(l, dict)], lambda l: str(l.get("name", "")))
    LB = keyed([l for l in y.get("layers") or [] if isinstance(l, dict)], lambda l: str(l.get("name", "")))
    for lk in sorted(set(LB) - set(LA)):
        S["layersAdded"] += 1; note("layer", 'layer "%s" added to "%s"' % (LB[lk].get("name"), cname), comp=cname, layer=LB[lk].get("name"))
    for lk in sorted(set(LA) - set(LB)):
        S["layersRemoved"] += 1; note("layer", 'layer "%s" removed from "%s"' % (LA[lk].get("name"), cname), comp=cname, layer=LA[lk].get("name"))
    for lk in sorted(set(LA) & set(LB)):
        p, q = LA[lk], LB[lk]
        lname, bits = q.get("name"), []
        for field in ("enabled", "locked", "solo"):
            if p.get(field) != q.get(field) and field in p and field in q:
                bits.append("%s %s -> %s" % (field, p[field], q[field]))
        if p.get("sourceName") != q.get("sourceName") or p.get("sourcePath") != q.get("sourcePath"):
            bits.append("source %s -> %s" % (p.get("sourceName") or "none", q.get("sourceName") or "none"))
        if p.get("type") != q.get("type"):
            bits.append("type %s -> %s" % (p.get("type"), q.get("type")))
        ep, eq = eff_set(p), eff_set(q)
        if set(ep) != set(eq):
            add_, rem_ = sorted(set(eq) - set(ep)), sorted(set(ep) - set(eq))
            bits.append("effects" + ("".join(" +" + eq[m] for m in add_)) + ("".join(" -" + ep[m] for m in rem_)))
        xp, xq = exprs(p), exprs(q)
        changed_props = sorted(pp for pp in set(xp) | set(xq) if xp.get(pp) != xq.get(pp))
        for pp in changed_props:
            S["expressionsChanged"] += 1
            what = "added" if pp not in xp else "removed" if pp not in xq else "changed"
            note("expression", 'layer "%s" in "%s": expression on %s %s' % (lname, cname, pp, what), comp=cname, layer=lname, propertyPath=pp)
        if num(p.get("index")) is not None and num(q.get("index")) is not None and p["index"] != q["index"] and not bits and not changed_props:
            bits.append("moved from position %d to %d" % (p["index"], q["index"]))
        if bits:
            S["layersChanged"] += 1
            note("layer", 'layer "%s" in "%s": %s' % (lname, cname, "; ".join(bits)), comp=cname, layer=lname)
        if bits or changed_props:
            comp_changed = True
    if comp_changed:
        S["compsChanged"] += 1

# footage: by id when every item has one, else by path (or name)
fa = [f for f in a["footage"] if isinstance(f, dict)]
fb = [f for f in b["footage"] if isinstance(f, dict)]
fids = all(isinstance(f.get("id"), int) and f["id"] > 0 for f in fa + fb)
fk = (lambda f: "id:%d" % f["id"]) if fids else (lambda f: "p:%s" % (f.get("path") or f.get("name") or ""))
FA, FB = keyed(fa, fk), keyed(fb, fk)
for k in sorted(set(FB) - set(FA)):
    S["footageAdded"] += 1; note("footage", 'footage "%s" added' % FB[k].get("name"))
for k in sorted(set(FA) - set(FB)):
    S["footageRemoved"] += 1; note("footage", 'footage "%s" removed' % FA[k].get("name"))
for k in sorted(set(FA) & set(FB)):
    p, q = FA[k], FB[k]
    if bool(p.get("missing")) != bool(q.get("missing")):
        S["footageMissingChanged"] += 1
        note("footage", 'footage "%s" %s' % (q.get("name"), "went missing" if q.get("missing") else "is no longer missing"))
    elif (p.get("path") or "") != (q.get("path") or ""):
        note("footage", 'footage "%s" moved: %s -> %s' % (q.get("name"), p.get("path") or "none", q.get("path") or "none"))
fonta, fontb = {str(f) for f in a["fonts"]}, {str(f) for f in b["fonts"]}
for f in sorted(fontb - fonta):
    S["fontsAdded"] += 1; note("font", 'font "%s" added' % f)
for f in sorted(fonta - fontb):
    S["fontsRemoved"] += 1; note("font", 'font "%s" no longer used' % f)
def all_effects(doc):
    out = set()
    for c in comps_of(doc):
        for l in c.get("layers") or []:
            if isinstance(l, dict):
                out |= set(eff_set(l))
    return out
ea, eb = all_effects(a), all_effects(b)
for m in sorted(eb - ea):
    S["effectsAdded"] += 1; note("effect", 'effect type %s now used' % m)
for m in sorted(ea - eb):
    S["effectsRemoved"] += 1; note("effect", 'effect type %s no longer used' % m)

def side(doc, path):
    return {"path": path, "projectName": doc.get("projectName"), "projectPath": doc.get("projectPath"), "scrapedAt": doc.get("scrapedAt")}
warnings = []
if a.get("projectPath") != b.get("projectPath"):
    warnings.append({"code": "DIFFERENT_PROJECTS", "message": "The two scrapes are from different project paths (%s, %s)." % (a.get("projectPath"), b.get("projectPath"))})
if str(a.get("scrapedAt", "")) > str(b.get("scrapedAt", "")):
    warnings.append({"code": "SCRAPES_OUT_OF_ORDER", "message": "The first scrape is newer than the second; 'added' and 'removed' are reversed from a history point of view."})
print(json.dumps({"ok": True, "data": {
    "schema": "MJ_DIFF_1", "before": side(a, os.environ["MJ_A"]), "after": side(b, os.environ["MJ_B"]),
    "identical": not changes, "summary": S, "changes": changes[:MAX_CHANGES], "changesTruncated": len(changes) > MAX_CHANGES,
    "matchedBy": {"comps": "id" if ids_ok else "name", "footage": "id" if fids else "path"},
    "sourceUnchanged": tree_id(os.environ["MJ_A"]) == ida and tree_id(os.environ["MJ_B"]) == idb,
    "_warnings": warnings + ([{"code": "CHANGES_TRUNCATED", "message": "Only the first %d changes are listed." % MAX_CHANGES}] if len(changes) > MAX_CHANGES else []),
}}))
PY_PROJECT_DIFF
) || true
  frames_emit_python_result "$_out"
}

handle_project_health() {
  local _rc=0 _path="" _versions="" _fmt="score" _ing="" _lint="" _out=""
  request_arg_present format && _fmt=$(request_arg_get format)
  case "$_fmt" in score|record|all) ;; *) set_error "INVALID_ARGUMENT" "format must be score, record or all."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65 ;; esac

  if [ "$_fmt" = all ]; then
    library_require_store existing || { _rc=$?; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return $_rc; }
    _out=$(MJ_STORE="$MJ_STORE" MJ_FORMULA="$HEALTH_FORMULA_VERSION" library_python <<'PY_HEALTH_ALL'
db = open_db(os.environ["MJ_STORE"])
rows = db.execute("SELECT project_path, scraped_at, score FROM health ORDER BY project_path, scraped_at").fetchall()
by = {}
for pp, at, sc in rows:
    by.setdefault(pp, []).append((at, sc))
projects = []
for pp, series in sorted(by.items()):
    projects.append({"projectPath": pp, "latestScore": series[-1][1], "latestAt": series[-1][0],
                     "series": [sc for _, sc in series][-30:], "snapshots": len(series),
                     "direction": "improving" if len(series) > 1 and series[-1][1] > series[0][1] else "worsening" if len(series) > 1 and series[-1][1] < series[0][1] else "steady"})
print(json.dumps({"ok": True, "data": {"schema": "MJ_HEALTH_TRENDS_1", "formulaVersion": int(os.environ["MJ_FORMULA"]), "projects": projects}}))
PY_HEALTH_ALL
) || true
    frames_emit_python_result "$_out"
    return
  fi

  require_arg path || { emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  _path="$MJ_REQUIRED_ARG_VALUE"
  request_arg_present input && _versions=$(request_arg_get input)
  if [ -n "$_versions" ]; then
    is_absolute_path "$_versions" && [ -d "$_versions" ] || { set_error "INVALID_PATH" "The versions folder must be an existing absolute directory."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
    mj_require_local_existing_path "$_versions" || { emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 73; }
  fi
  project_require_scrape_file "$_path" || { _rc=$?; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return $_rc; }
  if [ "$_fmt" = record ]; then
    library_require_store create || { _rc=$?; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return $_rc; }
  else
    MJ_STORE=""
  fi
  _ing=$(project_run_ingest "$_path") || { set_error "INGEST_FAILED" "Scrape summarizer failed to run."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 74; }
  _ing=$(project_emit_python_data "$_ing" 2>/dev/null) || { set_error "SCHEMA_MISMATCH" "Scrape file must be an MJ_PROJECT_SCRAPE_1 document."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 74; }
  _lint=$(project_run_lint "$_path") || { set_error "LINT_FAILED" "Expression linter failed to run."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 74; }
  _lint=$(project_emit_python_data "$_lint" 2>/dev/null) || { set_error "LINT_FAILED" "Expression linter failed to run."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 74; }

  _out=$(MJ_SCRAPE="$_path" MJ_VERSIONS="$_versions" MJ_FMT="$_fmt" MJ_STORE="$MJ_STORE" MJ_INGEST="$_ing" MJ_LINT="$_lint" MJ_FORMULA="$HEALTH_FORMULA_VERSION" library_python <<'PY_PROJECT_HEALTH'
import calendar
ing, lint = json.loads(os.environ["MJ_INGEST"]), json.loads(os.environ["MJ_LINT"])
scrape_id = tree_id(os.environ["MJ_SCRAPE"])
doc = load_scrape(os.environ["MJ_SCRAPE"])
missing, unlinked = ing.get("footageMissing") or [], ing.get("footageUnlinked") or []
comps = []

# footage (35): 12 per missing item, 3 per item not linked to a file
lost = min(35, 12 * len(missing) + 3 * len(unlinked))
comps.append({"name": "footage", "max": 35, "points": 35 - lost, "measured": True,
              "why": ("%d missing and %d unlinked footage items." % (len(missing), len(unlinked))) if lost else "All footage is linked and present.",
              "findings": [{"kind": "missing", "name": n} for n in missing[:20]] + [{"kind": "unlinked", "name": n} for n in unlinked[:20]]})

# expressions (40): 8 per error, 3 per warning (notes cost nothing)
errs, warns = lint.get("errors", 0), lint.get("warnings", 0)
lost = min(40, 8 * errs + 3 * warns)
comps.append({"name": "expressions", "max": 40, "points": 40 - lost, "measured": True,
              "why": ("%d expression errors and %d warnings." % (errs, warns)) if lost else "No expression problems.",
              "findings": [{"code": f["code"], "severity": f["severity"], "comp": f["comp"], "layer": f["layer"], "propertyPath": f["propertyPath"]}
                           for f in lint.get("findings", []) if f["severity"] in ("error", "warning")][:20]})

# snapshots (25): only measured when a versions folder is given
pname = str(doc.get("projectName", ""))
stem = pname[:-4] if pname.lower().endswith(".aep") else pname
versions = os.environ["MJ_VERSIONS"]
if versions:
    pat = re.compile(r"^" + re.escape(stem) + r"\.(\d{8}T\d{6}Z)\.[0-9a-f]{12}\.aep$", re.I)
    stamps = sorted(m.group(1) for n in os.listdir(versions) for m in [pat.match(n)] if m)
    scraped = str(doc.get("scrapedAt", ""))
    try:
        scraped_epoch = calendar.timegm(time.strptime(scraped[:19], "%Y-%m-%dT%H:%M:%S"))
    except ValueError:
        scraped_epoch = time.time()
    if not stamps:
        pts, why = 0, "No snapshots of this project exist."
    else:
        newest = calendar.timegm(time.strptime(stamps[-1], "%Y%m%dT%H%M%SZ"))
        gap = scraped_epoch - newest
        pts, why = (25, "Newest of %d snapshots is current." % len(stamps)) if gap <= 3600 else (15, "Newest snapshot is %d hours older than the scrape." % (gap // 3600)) if gap <= 86400 else (0, "Newest snapshot is %d days older than the scrape." % (gap // 86400))
    comps.append({"name": "snapshots", "max": 25, "points": pts, "measured": True, "why": why, "findings": [{"kind": "snapshot", "name": s} for s in stamps[-5:]]})
else:
    comps.append({"name": "snapshots", "max": 25, "points": 0, "measured": False, "why": "Not measured; pass a versions folder to include it.", "findings": []})

earned = sum(c["points"] for c in comps if c["measured"])
possible = sum(c["max"] for c in comps if c["measured"])
score = round(100 * earned / possible)
band = "healthy" if score >= 90 else "needs a look" if score >= 70 else "at risk" if score >= 40 else "unhealthy"
out = {"schema": "MJ_PROJECT_HEALTH_1", "projectName": pname, "projectPath": doc.get("projectPath"), "scrapedAt": doc.get("scrapedAt"),
       "score": score, "band": band, "formulaVersion": int(os.environ["MJ_FORMULA"]), "components": comps,
       "formula": "100 x earned / measurable points. footage 35 (-12 per missing item, -3 per unlinked), expressions 40 (-8 per error, -3 per warning), snapshots 25 (0/15/25 by age of newest snapshot, only when measured).",
       "recorded": False, "trend": None, "sourceUnchanged": tree_id(os.environ["MJ_SCRAPE"]) == scrape_id}
if os.environ["MJ_FMT"] == "record":
    db = open_db(os.environ["MJ_STORE"], create=True)
    sha = sha256_file(os.environ["MJ_SCRAPE"])
    with db:
        db.execute("INSERT OR REPLACE INTO health(project_path, scraped_at, score, formula_version, receipt_sha256, recorded_at) VALUES (?,?,?,?,?,?)",
                   (str(doc.get("projectPath") or pname), str(doc.get("scrapedAt", "")), score, int(os.environ["MJ_FORMULA"]), sha, now_iso()))
    out["recorded"] = True
    out["trend"] = [r[0] for r in db.execute("SELECT score FROM health WHERE project_path = ? AND formula_version = ? ORDER BY scraped_at", (str(doc.get("projectPath") or pname), int(os.environ["MJ_FORMULA"])))][-30:]
print(json.dumps({"ok": True, "data": out}))
PY_PROJECT_HEALTH
) || true
  frames_emit_python_result "$_out"
}
