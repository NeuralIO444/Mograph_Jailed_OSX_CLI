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

SCHEMA_VERSION = 1
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
    return db

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
        counts["updated" if row else "added"] += 1
        by_schema[schema] = by_schema.get(schema, 0) + 1
    except Exception as e:
        counts["skipped"] += 1
        if len(problems) < 20:
            problems.append({"path": p, "reason": str(e)[:120]})
print(json.dumps({"ok": True, "data": dict(counts, **{
    "schema": "MJ_INDEX_ADD_1", "path": root, "store": os.environ["MJ_STORE"],
    "filesExamined": len(candidates), "indexedBySchema": by_schema, "problems": problems,
    "sourceUnchanged": True,
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
    "presetVersions": count("SELECT count(*) FROM presets"), "presetBlobs": len(blobs),
    "staleDocs": stale[:100], "corruptPresetBlobs": corrupt,
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
        "sha256": sha, "created": False, "reason": "unchanged", "sourceUnchanged": True}}))
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
    "sha256": sha, "kind": kind, "originalName": name, "bytes": size, "created": True, "sourceUnchanged": True}}))
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
    "sha256": sha, "outputPath": dest, "sourceUnchanged": True}}))
PY_PRESET_GET
) || true
  frames_emit_python_result "$_out"
}
