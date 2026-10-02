# Protect work — restore, dependency graph, handoff packaging.
#
# project.restore  — copy a snapshot back out as a NEW .aep (hash-verified; never overwrites)
# deps.graph       — dependency graph + single points of failure from an MJ_PROJECT_SCRAPE_1 receipt; read-only
# handoff.package  — new delivery folder: project, collected local footage, MANIFEST.json, README.txt
#
# Footage paths come from the scrape and may point at network volumes. They are
# classified from the kernel mount table (no I/O to the remote volume); only
# positively local paths are ever stat'ed or copied.

IFS= read -r -d '' MJ_PY_PROTECT_LIB <<'PY_PROTECT_LIB' || true
import hashlib, json, os, re, shutil, subprocess, sys, time

def err(code, message):
    print(json.dumps({"ok": False, "code": code, "message": message}))
    sys.exit(0)

def tree_id(path):
    """Cheap identity (size, mtime) of a file, or of the regular files directly inside a directory.
    Compared before and after an operation to report honestly whether its source changed."""
    try:
        if os.path.isdir(path):
            out = []
            for n in sorted(os.listdir(path)):
                p = os.path.join(path, n)
                if os.path.isfile(p):
                    st = os.stat(p); out.append((n, st.st_size, st.st_mtime_ns))
            return tuple(out)
        st = os.stat(path)
        return (st.st_size, st.st_mtime_ns)
    except OSError:
        return None

def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1048576), b""):
            h.update(chunk)
    return h.hexdigest()

def utc_stamp():
    return time.strftime("%Y%m%dT%H%M%SZ", time.gmtime())

def load_scrape(path, max_bytes=8388608):
    try:
        if os.path.getsize(path) > max_bytes:
            err("SCRAPE_TOO_LARGE", "Scrape file exceeds the byte bound.")
        with open(path, "r", encoding="utf-8") as f:
            doc = json.load(f)
    except Exception as e:
        err("INVALID_JSON", "Scrape file is not valid JSON: %s" % str(e)[:120])
    if not isinstance(doc, dict) or doc.get("schema") != "MJ_PROJECT_SCRAPE_1":
        err("SCHEMA_MISMATCH", "Scrape file must be an MJ_PROJECT_SCRAPE_1 document.")
    for key in ("comps", "fonts", "footage"):
        if not isinstance(doc.get(key), list):
            err("SCHEMA_MISMATCH", "%s must be an array." % key)
    return clean_scrape(doc)

def clean_scrape(doc):
    """Drop nested entries of the wrong shape and coerce names and paths to text, so every consumer can
    trust what it iterates. A scrape is data from outside; the hall of horror test feeds it junk."""
    def lst(v):
        return [x for x in v if isinstance(x, dict)] if isinstance(v, list) else []
    def txt(d, k):
        if k in d and not isinstance(d[k], str):
            d[k] = "" if d[k] is None else str(d[k])
    def num(d, k):
        if k in d and (isinstance(d[k], bool) or not isinstance(d[k], int)):
            d[k] = 0
    doc["comps"] = lst(doc["comps"])
    for c in doc["comps"]:
        txt(c, "name"); txt(c, "folder")
        if not isinstance(c.get("id"), int) or isinstance(c.get("id"), bool):
            c["id"] = None
        c["layers"] = lst(c.get("layers"))
        for l in c["layers"]:
            for k in ("name", "type", "sourceName", "sourcePath", "sourceKind", "font"):
                txt(l, k)
            num(l, "index"); num(l, "sourceId"); num(l, "label")
            l["effects"] = lst(l.get("effects"))
            for e in l["effects"]:
                txt(e, "name"); txt(e, "matchName")
            l["expressions"] = [e for e in lst(l.get("expressions")) if isinstance(e.get("expression"), str)]
            for e in l["expressions"]:
                txt(e, "propertyPath")
    doc["footage"] = lst(doc["footage"])
    for f in doc["footage"]:
        for k in ("name", "path", "kind", "folder"):
            txt(f, k)
        if not isinstance(f.get("id"), int) or isinstance(f.get("id"), bool):
            f["id"] = None
    doc["fonts"] = [x for x in doc["fonts"] if isinstance(x, str)]
    if "missingFonts" in doc and not isinstance(doc["missingFonts"], list):
        doc["missingFonts"] = None
    return doc

LOCAL_FS = {"apfs", "hfs", "hfs+", "exfat", "msdos", "vfat", "ext2", "ext3", "ext4", "xfs",
            "overlay", "overlayfs", "tmpfs", "btrfs"}
NETWORK_FS = {"smbfs", "nfs", "webdav", "afpfs", "cifs", "nfs4"}
_MOUNTS = None

def parse_mounts(text):
    """mount(8) output -> [(mount point, fs type)], longest mount point first.
    macOS: "dev on /path (apfs, local, ...)"; Linux: "dev on /path type ext4 (rw,...)"."""
    table = []
    for line in text.splitlines():
        m = re.match(r"^.+? on (.+?) type (\S+)", line) or re.match(r"^.+? on (.+?) \(([^,)]+)", line)
        if m:
            table.append((m.group(1), m.group(2).lower()))
    table.sort(key=lambda t: -len(t[0]))
    return table

def _mount_table():
    global _MOUNTS
    if _MOUNTS is None:
        exe = "/sbin/mount" if os.path.exists("/sbin/mount") else "/bin/mount"
        try:
            out = subprocess.run([exe], capture_output=True, text=True, timeout=10).stdout
        except Exception:
            out = ""
        _MOUNTS = parse_mounts(out)
    return _MOUNTS

def storage_class(path):
    """local | network | unknown, by longest mount-point prefix. Never touches the path."""
    for mnt, fstype in _mount_table():
        if path == mnt or path.startswith(mnt.rstrip("/") + "/"):
            if fstype in LOCAL_FS:
                return "local"
            if fstype in NETWORK_FS:
                return "network"
            return "unknown"
    return "unknown"

def clone_copy(src, dst):
    """APFS clone when available, else a plain copy. dst must not exist."""
    if os.path.exists(dst):
        raise FileExistsError(dst)
    if sys.platform == "darwin":
        if subprocess.run(["/bin/cp", "-c", "-n", src, dst], stderr=subprocess.DEVNULL).returncode == 0 and os.path.isfile(dst):
            return True
    shutil.copyfile(src, dst)
    return False
PY_PROTECT_LIB

protect_python() {
  local _main=""
  IFS= read -r -d '' _main || true
  printf '%s\n%s' "$MJ_PY_PROTECT_LIB" "$_main" | /usr/bin/python3 - 2>/dev/null
}

# Validate an absolute, existing, writable, local output directory.
protect_require_output_dir() {
  local _dir="$1"
  is_absolute_path "$_dir" || { set_error "INVALID_PATH" "Output directory must be absolute."; return 65; }
  [ -d "$_dir" ] && [ -w "$_dir" ] || { set_error "OUTPUT_UNAVAILABLE" "Output directory must exist and be writable."; return 73; }
  mj_require_local_existing_path "$_dir" || return 73
}

# A snapshot file to restore from: an .aep or .c4d.
protect_require_snapshot() {
  local _path="$1"
  is_absolute_path "$_path" || { set_error "INVALID_PATH" "Snapshot path must be absolute."; return 65; }
  [ -f "$_path" ] || { set_error "INVALID_TARGET" "Snapshot must be a regular file."; return 65; }
  [ -r "$_path" ] || { set_error "PERMISSION_DENIED" "Snapshot is not readable."; return 77; }
  case "${_path##*/}" in *.[aA][eE][pP]|*.[cC]4[dD]) ;; *) set_error "INVALID_TARGET" "Snapshot must be an After Effects project (.aep) or a Cinema 4D scene (.c4d)."; return 65 ;; esac
  cap_available python3 || { set_error "UNSUPPORTED" "This operation requires python3."; return 69; }
  mj_require_local_existing_path "$_path" || return 73
}

protect_require_aep() {
  local _path="$1"
  is_absolute_path "$_path" || { set_error "INVALID_PATH" "Project path must be absolute."; return 65; }
  [ -f "$_path" ] || { set_error "INVALID_TARGET" "Project must be a regular file."; return 65; }
  [ -r "$_path" ] || { set_error "PERMISSION_DENIED" "Project is not readable."; return 77; }
  case "${_path##*/}" in *.[aA][eE][pP]) ;; *) set_error "INVALID_TARGET" "Project must be an After Effects project (.aep)."; return 65 ;; esac
  cap_available python3 || { set_error "UNSUPPORTED" "This operation requires python3."; return 69; }
  mj_require_local_existing_path "$_path" || return 73
}

handle_project_restore() {
  local _rc=0 _path="" _outdir="" _out=""
  require_arg path || { emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  _path="$MJ_REQUIRED_ARG_VALUE"
  require_arg output || { emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  _outdir="$MJ_REQUIRED_ARG_VALUE"
  protect_require_snapshot "$_path" || { _rc=$?; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return $_rc; }
  protect_require_output_dir "$_outdir" || { _rc=$?; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return $_rc; }

  _out=$(MJ_SNAP="$_path" MJ_OUTDIR="$(canonical_existing_dir "$_outdir")" protect_python <<'PY_RESTORE'
snap = os.environ["MJ_SNAP"]
outdir = os.environ["MJ_OUTDIR"]
id0 = tree_id(snap)
sha = sha256_file(snap)
receipt_path = snap + ".snapshot.json"
receipt_verified = False
if os.path.isfile(receipt_path):
    try:
        with open(receipt_path, encoding="utf-8") as f:
            recorded = json.load(f).get("sha256")
    except Exception:
        err("INVALID_RECEIPT", "Snapshot receipt exists but is unreadable.")
    if recorded != sha:
        err("SNAPSHOT_CORRUPT", "Snapshot bytes no longer match its receipt; refusing to restore.")
    receipt_verified = True
ext = os.path.splitext(snap)[1].lower()          # .aep or .c4d
stem = os.path.basename(snap)[:-4]
base = os.path.join(outdir, "%s.restored.%s" % (stem, utc_stamp()))
partial = os.path.join(outdir, ".%s.partial-%d" % (os.path.basename(base), os.getpid()))
dest = None
try:
    clone = clone_copy(snap, partial)
    if sha256_file(partial) != sha:
        err("RESTORE_FAILED", "Restored copy did not verify.")
    for n in range(1, 100):
        candidate = base + (ext if n == 1 else "-%d%s" % (n, ext))
        try:
            os.link(partial, candidate)     # fails if it exists: never overwrites
            dest = candidate
            break
        except FileExistsError:
            continue
    if dest is None:
        err("OUTPUT_EXISTS", "Refusing to overwrite existing restored copies.")
except OSError as e:
    err("RESTORE_FAILED", "Could not write the restored copy: %s" % str(e)[:120])
finally:
    if os.path.exists(partial):
        os.unlink(partial)
print(json.dumps({"ok": True, "data": {
    "schema": "MJ_PROJECT_RESTORE_1",
    "snapshotPath": snap,
    "restoredPath": dest,
    "sha256": sha,
    "receiptVerified": receipt_verified,
    "cloneUsed": clone,
    "sourceUnchanged": tree_id(snap) == id0,
}}))
PY_RESTORE
) || true
  frames_emit_python_result "$_out"
}

handle_deps_graph() {
  local _rc=0 _path="" _out=""
  require_arg path || { emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  _path="$MJ_REQUIRED_ARG_VALUE"
  project_require_scrape_file "$_path" || { _rc=$?; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return $_rc; }

  _out=$(MJ_SCRAPE="$_path" protect_python <<'PY_DEPS'
id0 = tree_id(os.environ["MJ_SCRAPE"])
doc = load_scrape(os.environ["MJ_SCRAPE"])
comps = [c for c in doc["comps"] if isinstance(c, dict)]
comp_names = {str(c.get("name", "")) for c in comps}
reported_missing = {f.get("path") for f in doc["footage"] if isinstance(f, dict) and f.get("missing")}

uses = {}        # comp -> {"footage": set, "precomps": set, "effects": set}
users = {}       # dependency key -> set of comps using it directly
parents = {}     # comp -> comps that use it as a precomp
for c in comps:
    name = str(c.get("name", ""))
    u = uses.setdefault(name, {"footage": set(), "precomps": set(), "effects": set(), "text": False})
    for layer in c.get("layers", []) if isinstance(c.get("layers"), list) else []:
        if not isinstance(layer, dict):
            continue
        src_path = str(layer.get("sourcePath") or "")
        src_name = str(layer.get("sourceName") or "")
        if src_path:
            u["footage"].add(src_path)
            users.setdefault(("footage", src_path), set()).add(name)
        elif src_name in comp_names and src_name != name:
            u["precomps"].add(src_name)
            parents.setdefault(src_name, set()).add(name)
        if layer.get("type") == "TextLayer":
            u["text"] = True
        for fx in layer.get("effects", []) if isinstance(layer.get("effects"), list) else []:
            if isinstance(fx, dict) and fx.get("matchName"):
                key = str(fx["matchName"])
                u["effects"].add(key)
                users.setdefault(("effect", key), set()).add(name)

def impact(direct):
    """Every comp that breaks if these comps break, following precomp nesting upward."""
    seen, stack = set(direct), list(direct)
    while stack:
        for p in parents.get(stack.pop(), ()):
            if p not in seen:
                seen.add(p); stack.append(p)
    return seen

def footage_state(p):
    cls = storage_class(p)
    if cls != "local":
        return cls, None
    return cls, (p in reported_missing) or not os.path.isfile(p)

deps = []
for (kind, key), direct in users.items():
    entry = {"kind": kind, "id": key, "directUsers": sorted(direct), "impactedComps": sorted(impact(direct))}
    if kind == "footage":
        cls, missing = footage_state(key)
        entry["storage"] = cls
        entry["missing"] = missing      # null when not checked (network/unknown storage)
    deps.append(entry)
deps.sort(key=lambda d: (-len(d["impactedComps"]), d["kind"], d["id"]))

missing = [d["id"] for d in deps if d.get("missing")]
unverified = [d["id"] for d in deps if d["kind"] == "footage" and d.get("missing") is None]
spof = [d for d in deps if len(d["impactedComps"]) >= 2][:25]
print(json.dumps({"ok": True, "data": {
    "schema": "MJ_DEPS_GRAPH_1",
    "projectName": doc.get("projectName"),
    "comps": [{"name": n, "footage": sorted(u["footage"]), "precomps": sorted(u["precomps"]),
               "effects": sorted(u["effects"]), "usesText": u["text"]} for n, u in uses.items()],
    "fonts": sorted(str(f) for f in doc["fonts"]),
    "dependencies": deps[:2000],
    "dependenciesTruncated": len(deps) > 2000,
    "missingFootage": missing,
    "unverifiedFootage": unverified,
    "singlePointsOfFailure": spof,
    "note": "Fonts are project-wide in MJ_PROJECT_SCRAPE_1; comps with usesText depend on them. Footage on network or unknown storage is not checked.",
    "sourceUnchanged": tree_id(os.environ["MJ_SCRAPE"]) == id0,
    "_warnings": ([{"code": "MISSING_FOOTAGE", "message": "Missing footage files: %d." % len(missing)}] if missing else [])
                 + ([{"code": "FOOTAGE_UNVERIFIED", "message": "Footage files on network or unknown storage, not checked: %d." % len(unverified)}] if unverified else []),
}}))
PY_DEPS
) || true
  frames_emit_python_result "$_out"
}

handle_handoff_package() {
  local _rc=0 _aep="" _scrape="" _outdir="" _label="" _out=""
  require_arg path || { emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  _aep="$MJ_REQUIRED_ARG_VALUE"
  require_arg input || { emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  _scrape="$MJ_REQUIRED_ARG_VALUE"
  require_arg output || { emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  _outdir="$MJ_REQUIRED_ARG_VALUE"
  require_arg label || { emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  _label="$MJ_REQUIRED_ARG_VALUE"
  case "$_label" in .*|*[!A-Za-z0-9._-]*) set_error "INVALID_ARGUMENT" "label may contain only letters, digits, dot, dash and underscore."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65 ;; esac
  [ ${#_label} -le 64 ] || { set_error "INVALID_ARGUMENT" "label must be at most 64 characters."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  protect_require_aep "$_aep" || { _rc=$?; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return $_rc; }
  project_require_scrape_file "$_scrape" || { _rc=$?; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return $_rc; }
  protect_require_output_dir "$_outdir" || { _rc=$?; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return $_rc; }

  _out=$(MJ_AEP="$_aep" MJ_SCRAPE="$_scrape" MJ_OUTDIR="$(canonical_existing_dir "$_outdir")" MJ_LABEL="$_label" protect_python <<'PY_HANDOFF'
MAX_FILES = 20000
aep, label = os.environ["MJ_AEP"], os.environ["MJ_LABEL"]
doc = load_scrape(os.environ["MJ_SCRAPE"])
dest = os.path.join(os.environ["MJ_OUTDIR"], label + ".handoff")

# Referenced footage: footage items plus layer sources, de-duplicated, in project order.
refs = []
for f in doc["footage"]:
    if isinstance(f, dict) and f.get("path"):
        refs.append(str(f["path"]))
for c in doc["comps"]:
    for layer in (c.get("layers") or []) if isinstance(c, dict) else []:
        if isinstance(layer, dict) and layer.get("sourcePath"):
            refs.append(str(layer["sourcePath"]))
refs = list(dict.fromkeys(refs))

SEQ = re.compile(r"^(.*?)(\d{3,})(\.[A-Za-z0-9]+)$")
plan, missing, skipped = [], [], []   # plan: (source, relative destination)
used_names = set()
for ref in refs:
    cls = storage_class(ref)
    if cls != "local":
        skipped.append({"path": ref, "storage": cls}); continue
    if not os.path.isfile(ref):
        missing.append(ref); continue
    folder, name = os.path.split(ref)
    m = SEQ.match(name)
    members = [name]
    if m:   # image sequence: AE references the first frame; collect the whole run
        pat = re.compile("^" + re.escape(m.group(1)) + r"\d{%d}" % len(m.group(2)) + re.escape(m.group(3)) + "$")
        members = sorted(n for n in os.listdir(folder) if pat.match(n) and os.path.isfile(os.path.join(folder, n)))
    base = (m.group(1).rstrip("._- ") or "sequence") if m and len(members) > 1 else name
    unique, i = base, 1
    while unique in used_names:
        i += 1; unique = "%d_%s" % (i, base)
    used_names.add(unique)
    if m and len(members) > 1:
        plan += [(os.path.join(folder, n), os.path.join("footage", unique, n)) for n in members]
    else:
        plan.append((ref, os.path.join("footage", unique)))
if len(plan) > MAX_FILES:
    err("TOO_MANY_FILES", "Handoff would collect more than %d files." % MAX_FILES)

ids0 = {p: tree_id(p) for p in [aep] + [src for src, _ in plan]}
need = os.path.getsize(aep) + sum(os.path.getsize(s) for s, _ in plan) + 67108864
if shutil.disk_usage(os.environ["MJ_OUTDIR"]).free < need:
    err("INSUFFICIENT_SPACE", "Not enough free space for the handoff (%d bytes needed)." % need)

try:
    os.mkdir(dest)               # atomic reservation: never overwrites
except FileExistsError:
    err("OUTPUT_EXISTS", "Refusing to overwrite an existing handoff folder.")
try:
    marker = os.path.join(dest, ".incomplete")
    open(marker, "w").close()
    os.mkdir(os.path.join(dest, "project"))
    proj_rel = os.path.join("project", os.path.basename(aep))
    clone_copy(aep, os.path.join(dest, proj_rel))
    files = []
    for src, rel in plan:
        out = os.path.join(dest, rel)
        os.makedirs(os.path.dirname(out), exist_ok=True)
        clone_copy(src, out)
        files.append({"source": src, "packaged": rel, "bytes": os.path.getsize(out), "sha256": sha256_file(out)})
    effects = {}
    for c in doc["comps"]:
        for layer in (c.get("layers") or []) if isinstance(c, dict) else []:
            for fx in (layer.get("effects") or []) if isinstance(layer, dict) else []:
                if isinstance(fx, dict) and fx.get("matchName"):
                    effects[str(fx["matchName"])] = str(fx.get("name", ""))
    manifest = {
        "schema": "MJ_HANDOFF_1",
        "label": label,
        "createdAt": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "project": {"source": aep, "packaged": proj_rel, "sha256": sha256_file(os.path.join(dest, proj_rel)),
                    "bytes": os.path.getsize(aep), "aeVersion": doc.get("aeVersion"),
                    "scrapeProjectName": doc.get("projectName"),
                    "matchesScrape": doc.get("projectName") == os.path.basename(aep)},
        "fonts": sorted(str(f) for f in doc["fonts"]),
        "effects": [{"matchName": k, "name": v} for k, v in sorted(effects.items())],
        "files": files,
        "missingFootage": missing,
        "skippedFootage": skipped,
    }
    with open(os.path.join(dest, "MANIFEST.json"), "w", encoding="utf-8") as f:
        json.dump(manifest, f, indent=1, sort_keys=True); f.write("\n")
    lines = ["Handoff: %s" % label, "Created: %s" % manifest["createdAt"], "",
             "project/   %s (After Effects %s)" % (os.path.basename(aep), doc.get("aeVersion")),
             "footage/   %d collected files" % len(files), "",
             "Fonts to install:"] + ["  - " + f for f in manifest["fonts"]] + ["", "Effects / plug-ins used:"] + \
            ["  - %s (%s)" % (e["name"], e["matchName"]) for e in manifest["effects"]]
    if missing:
        lines += ["", "MISSING footage (not included):"] + ["  - " + p for p in missing]
    if skipped:
        lines += ["", "Footage on network or unknown storage (not collected):"] + ["  - " + s["path"] for s in skipped]
    lines += ["", "The project still points at the original footage locations. After opening it,",
              "relink with File > Replace Footage, pointing at the footage/ folder here.",
              "MANIFEST.json lists every file with its SHA-256."]
    with open(os.path.join(dest, "README.txt"), "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")
    os.unlink(marker)
except Exception as e:
    shutil.rmtree(dest, ignore_errors=True)
    err("HANDOFF_FAILED", "Could not build the handoff: %s" % str(e)[:160])
print(json.dumps({"ok": True, "data": {
    "schema": "MJ_HANDOFF_1",
    "handoffPath": dest,
    "manifestPath": os.path.join(dest, "MANIFEST.json"),
    "filesCollected": len(files),
    "bytesCollected": sum(f["bytes"] for f in files),
    "missingFootage": missing,
    "skippedFootage": skipped,
    "fonts": manifest["fonts"],
    "effectCount": len(manifest["effects"]),
    "projectMatchesScrape": manifest["project"]["matchesScrape"],
    "sourceUnchanged": all(tree_id(p) == v for p, v in ids0.items()),
    "_warnings": ([{"code": "MISSING_FOOTAGE", "message": "Missing footage files, not included: %d." % len(missing)}] if missing else [])
                 + ([{"code": "FOOTAGE_NOT_COLLECTED", "message": "Footage files on network or unknown storage, not copied: %d." % len(skipped)}] if skipped else [])
                 + ([{"code": "PROJECT_SCRAPE_MISMATCH", "message": "The scrape was taken from a different project name than the .aep being packaged."}] if not manifest["project"]["matchesScrape"] else []),
}}))
PY_HANDOFF
) || true
  frames_emit_python_result "$_out"
}
