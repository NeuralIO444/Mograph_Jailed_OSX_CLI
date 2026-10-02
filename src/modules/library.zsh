# Search and recall — MJ-owned local store (SL-M4 NativeDB product store).
#
# index.add    — index MJ receipts (scrapes, snapshots, golden records, handoff manifests)
# index.search — full-text search across everything indexed; read-only
# index.verify — SQLite + FTS integrity, schema version, stale docs, preset blob hashes; read-only
# preset.add   — content-addressed (SHA-256), per-label versioned preset library
# preset.get   — copy a preset version out as a new file; never overwrites
#
# Store: ${MJ_STORE_DIR:-~/Library/Application Support/MographJailed} (local only).
# Fixed schema, migrated by PRAGMA user_version. There is no SQL request API:
# every statement is fixed text with bound parameters.

IFS= read -r -d '' MJ_PY_LIBRARY <<'PY_LIBRARY' || true
import sqlite3

SCHEMA_VERSION = 3
SUPPORTED = ("MJ_PROJECT_SCRAPE_1", "MJ_PROJECT_SNAPSHOT_1", "MJ_GOLDEN_1", "MJ_HANDOFF_1")
MAX_ENTRIES_PER_DOC = 20000

def now_iso():
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())

def db_path(store):
    return os.path.join(store, "index.sqlite")

def open_db(store, create=False):
    path = db_path(store)
    if not create and not os.path.isfile(path):
        err("STORE_EMPTY", "Nothing has been indexed yet; run index.add or preset.add first.")
    db = sqlite3.connect(path, timeout=15)
    v = db.execute("PRAGMA user_version").fetchone()[0]
    if v > SCHEMA_VERSION:
        err("STORE_TOO_NEW", "Store schema %d is newer than this runtime supports (%d)." % (v, SCHEMA_VERSION))
    if v < 1:
        with db:
            db.executescript("""
                CREATE TABLE docs(id INTEGER PRIMARY KEY, path TEXT UNIQUE NOT NULL, sha256 TEXT NOT NULL,
                                  schema TEXT NOT NULL, title TEXT, indexed_at TEXT NOT NULL);
                CREATE VIRTUAL TABLE entries USING fts5(doc_id UNINDEXED, kind, name, detail,
                                  tokenize='unicode61 remove_diacritics 2');
                CREATE TABLE presets(id INTEGER PRIMARY KEY, label TEXT NOT NULL, version INTEGER NOT NULL,
                                  sha256 TEXT NOT NULL, kind TEXT NOT NULL, original_name TEXT NOT NULL,
                                  bytes INTEGER NOT NULL, added_at TEXT NOT NULL, UNIQUE(label, version));
                PRAGMA user_version = 1;
            """)
    if v < 2:
        # v2: normalized project tables for exact audit queries. Filled by index.add
        # from MJ_PROJECT_SCRAPE_1 receipts (newest scrape per project path wins).
        with db:
            db.executescript("""
                CREATE TABLE projects(id INTEGER PRIMARY KEY, project_path TEXT UNIQUE NOT NULL, name TEXT,
                                  ae_version TEXT, scraped_at TEXT NOT NULL, receipt_path TEXT NOT NULL,
                                  receipt_sha256 TEXT NOT NULL);
                CREATE TABLE compositions(id INTEGER PRIMARY KEY, project_id INTEGER NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
                                  ae_id INTEGER NOT NULL, name TEXT NOT NULL, width INTEGER, height INTEGER,
                                  fps REAL, duration REAL);
                CREATE TABLE layers(id INTEGER PRIMARY KEY, comp_id INTEGER NOT NULL REFERENCES compositions(id) ON DELETE CASCADE,
                                  idx INTEGER NOT NULL, name TEXT NOT NULL, type TEXT, source_ae_id INTEGER NOT NULL,
                                  source_name TEXT, source_path TEXT, font TEXT);
                CREATE TABLE assets(id INTEGER PRIMARY KEY, project_id INTEGER NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
                                  ae_id INTEGER NOT NULL, name TEXT NOT NULL, path TEXT, missing INTEGER NOT NULL);
                CREATE TABLE fonts(id INTEGER PRIMARY KEY, project_id INTEGER NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
                                  name TEXT NOT NULL, UNIQUE(project_id, name));
                CREATE TABLE plugins(id INTEGER PRIMARY KEY, project_id INTEGER NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
                                  comp_id INTEGER NOT NULL REFERENCES compositions(id) ON DELETE CASCADE,
                                  layer_id INTEGER NOT NULL REFERENCES layers(id) ON DELETE CASCADE,
                                  match_name TEXT NOT NULL, name TEXT);
                CREATE INDEX idx_plugins_match ON plugins(match_name);
                CREATE INDEX idx_layers_font ON layers(font);
                CREATE INDEX idx_layers_src ON layers(source_ae_id, source_path);
                CREATE INDEX idx_assets_missing ON assets(missing);
                CREATE INDEX idx_comps_project ON compositions(project_id);
                -- Receipts indexed under v1 have no relational rows; force one re-read.
                UPDATE docs SET sha256 = '' WHERE schema = 'MJ_PROJECT_SCRAPE_1';
                PRAGMA user_version = 2;
            """)
    if v < 3:
        # v3: recorded project health scores (project.health format=record), for trends.
        with db:
            db.executescript("""
                CREATE TABLE health(id INTEGER PRIMARY KEY, project_path TEXT NOT NULL, scraped_at TEXT NOT NULL, score INTEGER NOT NULL,
                                  formula_version INTEGER NOT NULL, receipt_sha256 TEXT NOT NULL, recorded_at TEXT NOT NULL,
                                  UNIQUE(project_path, receipt_sha256, formula_version));
                CREATE INDEX idx_health_project ON health(project_path, scraped_at);
                PRAGMA user_version = 3;
            """)
    db.execute("PRAGMA foreign_keys = ON")
    return db

def to_int(v):
    try:
        return int(v)
    except (TypeError, ValueError):
        return 0

def put_project(db, doc, receipt_path, sha):
    """Replace the relational rows of one project from a scrape. Returns False when the
    stored scrape for this project path is newer (an older receipt never wins)."""
    ppath = s(doc.get("projectPath")) or receipt_path
    scraped = s(doc.get("scrapedAt"))
    with db:
        row = db.execute("SELECT id, scraped_at FROM projects WHERE project_path = ?", (ppath,)).fetchone()
        if row and row[1] > scraped:
            return False
        if row:
            db.execute("DELETE FROM projects WHERE id = ?", (row[0],))
        pid = db.execute("INSERT INTO projects(project_path, name, ae_version, scraped_at, receipt_path, receipt_sha256) VALUES (?,?,?,?,?,?)",
                         (ppath, s(doc.get("projectName")), s(doc.get("aeVersion")), scraped, receipt_path, sha)).lastrowid
        for f in doc.get("footage") or []:
            if isinstance(f, dict):
                db.execute("INSERT INTO assets(project_id, ae_id, name, path, missing) VALUES (?,?,?,?,?)",
                           (pid, to_int(f.get("id")), s(f.get("name")), s(f.get("path")), 1 if f.get("missing") else 0))
        for name in sorted({s(x) for x in doc.get("fonts") or [] if s(x)}):
            db.execute("INSERT INTO fonts(project_id, name) VALUES (?,?)", (pid, name))
        for c in doc.get("comps") or []:
            if not isinstance(c, dict):
                continue
            cid = db.execute("INSERT INTO compositions(project_id, ae_id, name, width, height, fps, duration) VALUES (?,?,?,?,?,?,?)",
                             (pid, to_int(c.get("id")), s(c.get("name")), to_int(c.get("width")), to_int(c.get("height")),
                              c.get("frameRate") if isinstance(c.get("frameRate"), (int, float)) else None,
                              c.get("duration") if isinstance(c.get("duration"), (int, float)) else None)).lastrowid
            for l in c.get("layers") or []:
                if not isinstance(l, dict):
                    continue
                lid = db.execute("INSERT INTO layers(comp_id, idx, name, type, source_ae_id, source_name, source_path, font) VALUES (?,?,?,?,?,?,?,?)",
                                 (cid, to_int(l.get("index")), s(l.get("name")), s(l.get("type")), to_int(l.get("sourceId")),
                                  s(l.get("sourceName")), s(l.get("sourcePath")), s(l.get("font")))).lastrowid
                for fx in l.get("effects") or []:
                    if isinstance(fx, dict) and s(fx.get("matchName")):
                        db.execute("INSERT INTO plugins(project_id, comp_id, layer_id, match_name, name) VALUES (?,?,?,?,?)",
                                   (pid, cid, lid, s(fx.get("matchName")), s(fx.get("name"))))
    return True

def put_doc(db, path, sha, schema, title, entries):
    """Replace one document's entries atomically."""
    with db:
        row = db.execute("SELECT id FROM docs WHERE path = ?", (path,)).fetchone()
        if row:
            db.execute("DELETE FROM entries WHERE doc_id = ?", (row[0],))
            db.execute("UPDATE docs SET sha256 = ?, schema = ?, title = ?, indexed_at = ? WHERE id = ?",
                       (sha, schema, title, now_iso(), row[0]))
            doc_id = row[0]
        else:
            doc_id = db.execute("INSERT INTO docs(path, sha256, schema, title, indexed_at) VALUES (?,?,?,?,?)",
                                (path, sha, schema, title, now_iso())).lastrowid
        db.executemany("INSERT INTO entries(doc_id, kind, name, detail) VALUES (?,?,?,?)",
                       [(doc_id, k, n, d) for k, n, d in entries[:MAX_ENTRIES_PER_DOC]])

def s(v):
    return "" if v is None else str(v)

def extract(doc):
    """(title, [(kind, name, detail)]) for a supported receipt."""
    schema, out = doc.get("schema"), []
    if schema == "MJ_PROJECT_SCRAPE_1":
        title = s(doc.get("projectName"))
        out.append(("project", title, "AE %s %s" % (s(doc.get("aeVersion")), s(doc.get("projectPath")))))
        effects = {}
        for c in doc.get("comps") or []:
            if not isinstance(c, dict):
                continue
            cname = s(c.get("name"))
            out.append(("comp", cname, "%sx%s %sfps %ss" % (s(c.get("width")), s(c.get("height")), s(c.get("frameRate")), s(c.get("duration")))))
            for l in c.get("layers") or []:
                if not isinstance(l, dict):
                    continue
                out.append(("layer", s(l.get("name")), "%s / %s / %s" % (cname, s(l.get("type")), s(l.get("sourceName")))))
                for fx in l.get("effects") or []:
                    if isinstance(fx, dict):
                        effects[s(fx.get("matchName"))] = s(fx.get("name"))
                for ex in l.get("expressions") or []:
                    if isinstance(ex, dict):
                        out.append(("expression", s(ex.get("propertyPath")), "%s / %s: %s" % (cname, s(l.get("name")), s(ex.get("expression"))[:300])))
        out += [("effect", n, m) for m, n in sorted(effects.items())]
        out += [("font", s(f), title) for f in doc.get("fonts") or []]
        out += [("footage", s(f.get("name")), s(f.get("path"))) for f in doc.get("footage") or [] if isinstance(f, dict)]
    elif schema == "MJ_PROJECT_SNAPSHOT_1":
        title = os.path.basename(s(doc.get("sourcePath")))
        out.append(("snapshot", title, "%s %s" % (s(doc.get("createdAt")), s(doc.get("snapshotPath")))))
    elif schema == "MJ_GOLDEN_1":
        title = s(doc.get("label"))
        out.append(("golden", title, "%d frames %s" % (len(doc.get("frames") or []), s(doc.get("sourceDir")))))
    else:  # MJ_HANDOFF_1
        title = s(doc.get("label"))
        proj = doc.get("project") or {}
        out.append(("handoff", title, "%s %s" % (s(doc.get("createdAt")), s(proj.get("source")))))
        out += [("font", s(f), title) for f in doc.get("fonts") or []]
        out += [("file", s(f.get("packaged")), s(f.get("source"))) for f in doc.get("files") or [] if isinstance(f, dict)]
    return title, out

PRESET_KINDS = {".ffx": "ae-animation-preset", ".aet": "ae-template", ".aep": "ae-project", ".mogrt": "mogrt",
                ".jsx": "script", ".js": "expression", ".txt": "expression", ".c4d": "c4d-scene",
                ".lib4d": "c4d-library", ".rsmat": "redshift-material"}

def preset_blob(store, sha):
    return os.path.join(store, "presets", sha)
PY_LIBRARY

library_store_dir() {
  printf '%s' "${MJ_STORE_DIR:-${HOME:-}/Library/Application Support/MographJailed}"
}

# Resolve and (when allowed) create the local store. Sets MJ_STORE.
library_require_store() {
  local _create="$1" _dir=""
  MJ_STORE=""
  _dir=$(library_store_dir)
  is_absolute_path "$_dir" || { set_error "STORE_UNAVAILABLE" "Store directory must be absolute."; return 73; }
  cap_available python3 || { set_error "UNSUPPORTED" "The library store requires python3."; return 69; }
  if [ ! -d "$_dir" ]; then
    [ "$_create" = create ] || { set_error "STORE_EMPTY" "Nothing has been indexed yet; run index.add or preset.add first."; return 66; }
    [ -d "$(parent_path "$_dir")" ] || { set_error "STORE_UNAVAILABLE" "Store parent directory does not exist."; return 73; }
    /bin/mkdir -m 700 "$_dir" 2>/dev/null || { set_error "STORE_UNAVAILABLE" "Could not create the store directory."; return 73; }
  fi
  [ -w "$_dir" ] || { set_error "STORE_UNAVAILABLE" "Store directory is not writable."; return 73; }
  mj_require_local_existing_path "$_dir" || return 73
  MJ_STORE=$(canonical_existing_dir "$_dir")
}

library_python() {
  local _main=""
  IFS= read -r -d '' _main || true
  printf '%s\n%s\n%s' "$MJ_PY_PROTECT_LIB" "$MJ_PY_LIBRARY" "$_main" | /usr/bin/python3 - 2>/dev/null
}

library_label_ok() {
  case "$1" in .*|*[!A-Za-z0-9._-]*) set_error "INVALID_ARGUMENT" "label may contain only letters, digits, dot, dash and underscore."; return 1 ;; esac
  [ ${#1} -le 64 ] || { set_error "INVALID_ARGUMENT" "label must be at most 64 characters."; return 1; }
}

handle_index_add() {
  local _rc=0 _path="" _out=""
  require_arg path || { emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  _path="$MJ_REQUIRED_ARG_VALUE"
  is_absolute_path "$_path" || { set_error "INVALID_PATH" "Path must be absolute."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  [ -f "$_path" ] || [ -d "$_path" ] || { set_error "INVALID_TARGET" "Path must be a receipt file or a directory of receipts."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  [ -r "$_path" ] || { set_error "PERMISSION_DENIED" "Path is not readable."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 77; }
  mj_require_local_existing_path "$_path" || { emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 73; }
  library_require_store create || { _rc=$?; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return $_rc; }

  _out=$(MJ_PATH="$_path" MJ_STORE="$MJ_STORE" library_python <<'PY_INDEX_ADD'
MAX_FILES, MAX_BYTES = 5000, 8388608
root = os.path.realpath(os.environ["MJ_PATH"])
candidates = []
if os.path.isfile(root):
    candidates = [root]
else:
    for d, dirs, files in os.walk(root):
        dirs[:] = sorted(x for x in dirs if not x.startswith(".") and storage_class(os.path.join(d, x)) == "local")
        candidates += [os.path.join(d, f) for f in sorted(files) if f.lower().endswith(".json") and not f.startswith(".")]
        if len(candidates) > MAX_FILES:
            err("TOO_MANY_FILES", "More than %d JSON files under this path; index a narrower folder." % MAX_FILES)
ids0 = {p: tree_id(p) for p in candidates}
db = open_db(os.environ["MJ_STORE"], create=True)
counts = {"added": 0, "updated": 0, "unchanged": 0, "skipped": 0}
by_schema, problems = {}, []
for p in candidates:
    try:
        if os.path.islink(p) or os.path.getsize(p) > MAX_BYTES:
            counts["skipped"] += 1; continue
        sha = sha256_file(p)
        with open(p, encoding="utf-8") as f:
            doc = json.load(f)
        schema = doc.get("schema") if isinstance(doc, dict) else None
        if schema not in SUPPORTED:
            counts["skipped"] += 1; continue
        row = db.execute("SELECT sha256 FROM docs WHERE path = ?", (p,)).fetchone()
        if row and row[0] == sha:
            counts["unchanged"] += 1; continue
        title, entries = extract(doc)
        put_doc(db, p, sha, schema, title, entries)
        if schema == "MJ_PROJECT_SCRAPE_1":
            put_project(db, doc, p, sha)
        counts["updated" if row else "added"] += 1
        by_schema[schema] = by_schema.get(schema, 0) + 1
    except Exception as e:
        counts["skipped"] += 1
        if len(problems) < 20:
            problems.append({"path": p, "reason": str(e)[:120]})
print(json.dumps({"ok": True, "data": dict(counts, **{
    "schema": "MJ_INDEX_ADD_1", "path": root, "store": os.environ["MJ_STORE"],
    "filesExamined": len(candidates), "indexedBySchema": by_schema, "problems": problems,
    "sourceUnchanged": all(tree_id(p) == v for p, v in ids0.items()),
    "_warnings": ([{"code": "FILES_UNREADABLE", "message": "Files that could not be indexed: %d (see problems)." % len(problems)}] if problems else []),
})}))
PY_INDEX_ADD
) || true
  frames_emit_python_result "$_out"
}

handle_index_search() {
  local _rc=0 _query="" _max="" _out=""
  require_arg target || { emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  _query="$MJ_REQUIRED_ARG_VALUE"
  frames_uint_arg maxResults 20 1 200 || { emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  _max="$MJ_FRAMES_UINT"
  library_require_store existing || { _rc=$?; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return $_rc; }

  _out=$(MJ_QUERY="$_query" MJ_MAX="$_max" MJ_STORE="$MJ_STORE" library_python <<'PY_INDEX_SEARCH'
query = os.environ["MJ_QUERY"]
# Words only, each as a quoted prefix term, all required. FTS operators in the
# query are never interpreted.
words = re.findall(r"\w+", query, re.UNICODE)[:12]
if not words:
    err("INVALID_ARGUMENT", "Search needs at least one word.")
match = " ".join('"%s"*' % w for w in words)
db = open_db(os.environ["MJ_STORE"])
rows = db.execute("""SELECT entries.kind, entries.name, entries.detail, docs.path, docs.schema, docs.title,
                            bm25(entries) AS rank
                     FROM entries JOIN docs ON docs.id = entries.doc_id
                     WHERE entries MATCH ? ORDER BY rank LIMIT ?""", (match, int(os.environ["MJ_MAX"]))).fetchall()
print(json.dumps({"ok": True, "data": {
    "schema": "MJ_INDEX_SEARCH_1", "query": query, "terms": words,
    "results": [{"kind": k, "name": n, "detail": d, "source": p, "sourceSchema": sc, "sourceTitle": t,
                 "score": round(-r, 4)} for k, n, d, p, sc, t, r in rows],
    "_warnings": ([{"code": "RESULTS_TRUNCATED", "message": "Only the first %d results are shown; raise maxResults to see more." % len(rows)}] if len(rows) >= int(os.environ["MJ_MAX"]) else []),
}}))
PY_INDEX_SEARCH
) || true
  frames_emit_python_result "$_out"
}

handle_index_verify() {
  local _rc=0 _out=""
  library_require_store existing || { _rc=$?; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return $_rc; }
  _out=$(MJ_STORE="$MJ_STORE" library_python <<'PY_INDEX_VERIFY'
store = os.environ["MJ_STORE"]
db = open_db(store)
integrity = db.execute("PRAGMA integrity_check").fetchone()[0]
try:
    db.execute("INSERT INTO entries(entries) VALUES('integrity-check')")
    fts_ok = True
except sqlite3.DatabaseError:
    fts_ok = False
stale = []
for (path,) in db.execute("SELECT path FROM docs WHERE schema != 'MJ_PRESET_1'"):
    if storage_class(path) == "local" and not os.path.isfile(path):
        stale.append(path)
corrupt = []
blobs = db.execute("SELECT DISTINCT sha256 FROM presets").fetchall()
for (sha,) in blobs:
    b = preset_blob(store, sha)
    if not os.path.isfile(b) or sha256_file(b) != sha:
        corrupt.append(sha)
count = lambda q: db.execute(q).fetchone()[0]
print(json.dumps({"ok": True, "data": {
    "schema": "MJ_INDEX_VERIFY_1", "store": store,
    "healthy": integrity == "ok" and fts_ok and not corrupt,
    "sqliteIntegrity": integrity, "ftsIntegrity": fts_ok,
    "schemaVersion": db.execute("PRAGMA user_version").fetchone()[0],
    "docs": count("SELECT count(*) FROM docs"), "entries": count("SELECT count(*) FROM entries"),
    "projects": count("SELECT count(*) FROM projects"),
    "presetVersions": count("SELECT count(*) FROM presets"), "presetBlobs": len(blobs),
    "staleDocs": stale[:100], "corruptPresetBlobs": corrupt,
    "_warnings": ([{"code": "STALE_RECEIPTS", "message": "Indexed receipts that no longer exist on disk: %d." % len(stale)}] if stale else [])
                 + ([{"code": "PRESET_BLOB_CORRUPT", "message": "Stored presets that failed their hash check: %d." % len(corrupt)}] if corrupt else []),
}}))
PY_INDEX_VERIFY
) || true
  frames_emit_python_result "$_out"
}

handle_preset_add() {
  local _rc=0 _path="" _label="" _out=""
  require_arg path || { emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  _path="$MJ_REQUIRED_ARG_VALUE"
  require_arg label || { emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  _label="$MJ_REQUIRED_ARG_VALUE"
  library_label_ok "$_label" || { emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  is_absolute_path "$_path" || { set_error "INVALID_PATH" "Preset path must be absolute."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  [ -f "$_path" ] && [ ! -L "$_path" ] || { set_error "INVALID_TARGET" "Preset must be a regular file."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  [ -r "$_path" ] || { set_error "PERMISSION_DENIED" "Preset is not readable."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 77; }
  mj_require_local_existing_path "$_path" || { emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 73; }
  library_require_store create || { _rc=$?; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return $_rc; }

  _out=$(MJ_PATH="$_path" MJ_LABEL="$_label" MJ_STORE="$MJ_STORE" library_python <<'PY_PRESET_ADD'
src, label, store = os.environ["MJ_PATH"], os.environ["MJ_LABEL"], os.environ["MJ_STORE"]
id0 = tree_id(src)
size = os.path.getsize(src)
if size > 536870912:
    err("PRESET_TOO_LARGE", "Presets are limited to 512 MB.")
sha = sha256_file(src)
name = os.path.basename(src)
kind = PRESET_KINDS.get(os.path.splitext(name)[1].lower(), "file")
db = open_db(store, create=True)
latest = db.execute("SELECT version, sha256 FROM presets WHERE label = ? ORDER BY version DESC LIMIT 1", (label,)).fetchone()
if latest and latest[1] == sha:
    print(json.dumps({"ok": True, "data": {"schema": "MJ_PRESET_1", "label": label, "version": latest[0],
        "sha256": sha, "created": False, "reason": "unchanged", "sourceUnchanged": tree_id(src) == id0}}))
    sys.exit(0)
blob = preset_blob(store, sha)
os.makedirs(os.path.dirname(blob), mode=0o700, exist_ok=True)
if not os.path.isfile(blob):
    tmp = blob + ".partial-%d" % os.getpid()
    try:
        clone_copy(src, tmp)
        if sha256_file(tmp) != sha:
            err("PRESET_FAILED", "Stored copy did not verify.")
        os.replace(tmp, blob)    # content-addressed: same name means same bytes
    finally:
        if os.path.exists(tmp):
            os.unlink(tmp)
version = (latest[0] if latest else 0) + 1
try:
    with db:
        db.execute("INSERT INTO presets(label, version, sha256, kind, original_name, bytes, added_at) VALUES (?,?,?,?,?,?,?)",
                   (label, version, sha, kind, name, size, now_iso()))
except sqlite3.IntegrityError:
    err("CONFLICT", "Another writer added this label version at the same time; retry.")
put_doc(db, "preset:%s@v%d" % (label, version), sha, "MJ_PRESET_1", label,
        [("preset", label, "v%d %s %s" % (version, kind, name))])
print(json.dumps({"ok": True, "data": {"schema": "MJ_PRESET_1", "label": label, "version": version,
    "sha256": sha, "kind": kind, "originalName": name, "bytes": size, "created": True, "sourceUnchanged": tree_id(src) == id0}}))
PY_PRESET_ADD
) || true
  frames_emit_python_result "$_out"
}

handle_preset_get() {
  local _rc=0 _label="" _outdir="" _version="0" _out=""
  require_arg label || { emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  _label="$MJ_REQUIRED_ARG_VALUE"
  library_label_ok "$_label" || { emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  require_arg output || { emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  _outdir="$MJ_REQUIRED_ARG_VALUE"
  frames_uint_arg version 0 1 1000000 || { emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  _version="$MJ_FRAMES_UINT"
  protect_require_output_dir "$_outdir" || { _rc=$?; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return $_rc; }
  library_require_store existing || { _rc=$?; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return $_rc; }

  _out=$(MJ_LABEL="$_label" MJ_VERSION="$_version" MJ_OUTDIR="$(canonical_existing_dir "$_outdir")" MJ_STORE="$MJ_STORE" library_python <<'PY_PRESET_GET'
label, want, store, outdir = os.environ["MJ_LABEL"], int(os.environ["MJ_VERSION"]), os.environ["MJ_STORE"], os.environ["MJ_OUTDIR"]
db = open_db(store)
if want:
    row = db.execute("SELECT version, sha256, original_name FROM presets WHERE label = ? AND version = ?", (label, want)).fetchone()
else:
    row = db.execute("SELECT version, sha256, original_name FROM presets WHERE label = ? ORDER BY version DESC LIMIT 1", (label,)).fetchone()
if not row:
    err("NOT_FOUND", "No such preset label/version.")
version, sha, name = row
blob = preset_blob(store, sha)
if not os.path.isfile(blob) or sha256_file(blob) != sha:
    err("PRESET_CORRUPT", "Stored preset bytes do not match their hash.")
stem, ext = os.path.splitext(os.path.basename(name))
dest = None
for candidate in (name, "%s-v%d%s" % (stem, version, ext)):
    path = os.path.join(outdir, os.path.basename(candidate))
    tmp = path + ".partial-%d" % os.getpid()
    try:
        clone_copy(blob, tmp)
        os.link(tmp, path)           # never overwrites
        dest = path
        break
    except FileExistsError:
        continue
    finally:
        if os.path.exists(tmp):
            os.unlink(tmp)
if not dest:
    err("OUTPUT_EXISTS", "Refusing to overwrite existing files in the output directory.")
print(json.dumps({"ok": True, "data": {"schema": "MJ_PRESET_GET_1", "label": label, "version": version,
    "sha256": sha, "outputPath": dest}}))
PY_PRESET_GET
) || true
  frames_emit_python_result "$_out"
}

# --- exact audit queries over the normalized tables (store schema v2) ---

IFS= read -r -d '' MJ_PY_TRACE <<'PY_TRACE' || true
MAX_PATHS = 20
MAX_DEPTH = 32

def project_graph(db, pid):
    comps = {r[0]: {"id": r[0], "ae_id": r[1], "name": r[2]} for r in
             db.execute("SELECT id, ae_id, name FROM compositions WHERE project_id = ?", (pid,))}
    by_ae = {c["ae_id"]: c for c in comps.values() if c["ae_id"]}
    by_name = {}
    for c in comps.values():
        by_name.setdefault(c["name"], []).append(c)
    layers = {}
    parents = {}      # child comp id -> [(parent comp id, layer idx, layer name)]
    for lid, cid, idx, name, typ, sid, sname, spath, font in db.execute(
            "SELECT l.id, l.comp_id, l.idx, l.name, l.type, l.source_ae_id, l.source_name, l.source_path, l.font "
            "FROM layers l JOIN compositions c ON c.id = l.comp_id WHERE c.project_id = ?", (pid,)):
        layers[lid] = {"id": lid, "comp": cid, "idx": idx, "name": name, "type": typ, "sid": sid,
                       "sname": sname, "spath": spath, "font": font}
        child = by_ae.get(sid) if sid else None
        if child is None and not sid and not spath and sname and len(by_name.get(sname, [])) == 1:
            child = by_name[sname][0]     # older scrapes without sourceId: unique name only
        if child is not None:
            parents.setdefault(child["id"], []).append((cid, idx, name))
    return comps, layers, parents

def comp_paths(comps, parents, cid):
    """Every root-to-comp chain of comp names, nearest-to-root first. Bounded; cycle safe."""
    out = []
    def walk(cur, chain):
        if len(out) >= MAX_PATHS or len(chain) > MAX_DEPTH:
            return
        ups = [p for p in parents.get(cur, []) if p[0] not in chain]
        if not ups:
            out.append(list(reversed([comps[c]["name"] for c in chain])))
            return
        for pcid, _, _ in ups:
            walk(pcid, chain + [pcid])
    walk(cid, [cid])
    return out

def describe_uses(comps, layers, parents, layer_ids):
    uses = []
    for lid in layer_ids[:200]:
        l = layers[lid]
        paths = comp_paths(comps, parents, l["comp"])
        uses.append({"comp": comps[l["comp"]]["name"], "layer": l["name"], "layerIndex": l["idx"],
                     "paths": [" > ".join(p) for p in paths], "pathsTruncated": len(paths) >= MAX_PATHS})
    return uses
PY_TRACE

handle_trace_asset() {
  local _rc=0 _target="" _kind="asset" _proj="" _out=""
  request_arg_present format && _kind=$(request_arg_get format)
  case "$_kind" in asset|font|missing) ;; *) set_error "INVALID_ARGUMENT" "format must be asset, font or missing."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65 ;; esac
  if [ "$_kind" != missing ]; then
    require_arg target || { emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
    _target="$MJ_REQUIRED_ARG_VALUE"
  fi
  request_arg_present path && _proj=$(request_arg_get path)
  [ -z "$_proj" ] || is_absolute_path "$_proj" || { set_error "INVALID_PATH" "Project path must be absolute."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  frames_uint_arg maxResults 50 1 500 || { emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  library_require_store existing || { _rc=$?; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return $_rc; }

  _out=$(MJ_KIND="$_kind" MJ_TARGET="$_target" MJ_PROJ="$_proj" MJ_MAX="$MJ_FRAMES_UINT" MJ_STORE="$MJ_STORE" trace_python <<'PY_TRACE_ASSET'
kind, target, proj_filter, limit = os.environ["MJ_KIND"], os.environ["MJ_TARGET"], os.environ["MJ_PROJ"], int(os.environ["MJ_MAX"])
db = open_db(os.environ["MJ_STORE"])
if db.execute("SELECT count(*) FROM projects").fetchone()[0] == 0:
    err("STORE_EMPTY", "No project scrapes are indexed yet; run index.add on scrape receipts first.")
rows = db.execute("SELECT id, project_path, name, scraped_at FROM projects" + (" WHERE project_path = ?" if proj_filter else "") +
                  " ORDER BY project_path", (proj_filter,) if proj_filter else ()).fetchall()
if proj_filter and not rows:
    err("NOT_FOUND", "That project path is not indexed.")
results, total = [], 0
for pid, ppath, pname, scraped in rows:
    comps, layers, parents = project_graph(db, pid)
    matches = []
    if kind == "font":
        lids = [l["id"] for l in layers.values() if l["font"].lower() == target.lower()]
        known = db.execute("SELECT count(*) FROM fonts WHERE project_id = ? AND name = ? COLLATE NOCASE", (pid, target)).fetchone()[0] > 0
        if lids or known:
            matches.append({"kind": "font", "name": target, "missing": None,
                            "uses": describe_uses(comps, layers, parents, lids)})
    else:
        if kind == "missing":
            assets = db.execute("SELECT ae_id, name, path, missing FROM assets WHERE project_id = ? AND missing = 1 ORDER BY path, name", (pid,)).fetchall()
        else:
            assets = db.execute("SELECT ae_id, name, path, missing FROM assets WHERE project_id = ? AND (name = ? OR path = ?) ORDER BY path, name",
                                (pid, target, target)).fetchall()
        for ae_id, name, path, missing in assets:
            lids = [l["id"] for l in layers.values()
                    if (ae_id and l["sid"] == ae_id) or (path and l["spath"] == path)]
            matches.append({"kind": "asset", "name": name, "path": path, "missing": bool(missing),
                            "uses": describe_uses(comps, layers, parents, lids)})
    if matches:
        results.append({"projectPath": ppath, "projectName": pname, "scrapedAt": scraped, "matches": matches})
        total += len(matches)
    if total >= limit:
        break
print(json.dumps({"ok": True, "data": {
    "schema": "MJ_TRACE_1", "query": {"format": kind, "target": target or None, "project": proj_filter or None},
    "projects": results, "matchCount": total, "truncated": total >= limit,
    "note": "Paths run from a root composition down to the composition that holds the layer; a missing-footage layer in a precomp reports every comp chain that nests it.",
    "_warnings": ([{"code": "RESULTS_TRUNCATED", "message": "Stopped after %d matches; raise maxResults or narrow with path." % total}] if total >= limit else []),
}}))
PY_TRACE_ASSET
) || true
  frames_emit_python_result "$_out"
}

trace_python() {
  local _main=""
  IFS= read -r -d '' _main || true
  printf '%s\n%s\n%s\n%s' "$MJ_PY_PROTECT_LIB" "$MJ_PY_LIBRARY" "$MJ_PY_TRACE" "$_main" | /usr/bin/python3 - 2>/dev/null
}

handle_audit_plugins() {
  local _rc=0 _target="" _out=""
  request_arg_present target && _target=$(request_arg_get target)
  frames_uint_arg maxResults 100 1 1000 || { emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  library_require_store existing || { _rc=$?; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return $_rc; }

  _out=$(MJ_TARGET="$_target" MJ_MAX="$MJ_FRAMES_UINT" MJ_STORE="$MJ_STORE" trace_python <<'PY_AUDIT_PLUGINS'
target, limit = os.environ["MJ_TARGET"], int(os.environ["MJ_MAX"])
db = open_db(os.environ["MJ_STORE"])
if db.execute("SELECT count(*) FROM projects").fetchone()[0] == 0:
    err("STORE_EMPTY", "No project scrapes are indexed yet; run index.add on scrape receipts first.")
if target:
    rows = db.execute("""SELECT p.project_path, p.name, p.scraped_at, count(*) AS uses,
                                count(DISTINCT pl.comp_id) AS comps, min(pl.name) AS fx_name
                         FROM plugins pl JOIN projects p ON p.id = pl.project_id
                         WHERE pl.match_name = ? GROUP BY p.id ORDER BY p.project_path LIMIT ?""", (target, limit)).fetchall()
    print(json.dumps({"ok": True, "data": {
        "schema": "MJ_PLUGIN_USAGE_1", "matchName": target, "projectCount": len(rows), "truncated": len(rows) >= limit,
        "projects": [{"projectPath": r[0], "projectName": r[1], "scrapedAt": r[2], "layerUses": r[3],
                      "compositions": r[4], "effectName": r[5]} for r in rows],
        "note": "Each project's newest indexed scrape is used; projects never scraped are not covered.",
        "_warnings": ([{"code": "RESULTS_TRUNCATED", "message": "Only the first %d projects are listed." % len(rows)}] if len(rows) >= limit else []),
    }}))
else:
    rows = db.execute("""SELECT pl.match_name, min(pl.name), count(DISTINCT pl.project_id), count(*)
                         FROM plugins pl GROUP BY pl.match_name ORDER BY 3 DESC, 1 LIMIT ?""", (limit,)).fetchall()
    print(json.dumps({"ok": True, "data": {
        "schema": "MJ_PLUGIN_INVENTORY_1", "distinctEffects": len(rows), "truncated": len(rows) >= limit,
        "effects": [{"matchName": r[0], "effectName": r[1], "projects": r[2], "layerUses": r[3]} for r in rows],
        "projectsIndexed": db.execute("SELECT count(*) FROM projects").fetchone()[0],
        "_warnings": ([{"code": "RESULTS_TRUNCATED", "message": "Only the first %d effects are listed." % len(rows)}] if len(rows) >= limit else []),
    }}))
PY_AUDIT_PLUGINS
) || true
  frames_emit_python_result "$_out"
}
