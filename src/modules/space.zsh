# Disk space taken by After Effects, Adobe media and Cinema 4D / Redshift caches.
#
# cache.inspect — list the known cache folders on this Mac with their size, and flag the ones left
#                 over from a host version that is no longer installed. Read-only.
# cache.clean   — empty ONE cache, named by the id cache.inspect gave it (never a path). Without
#                 format=delete it only reports what would be freed. Refuses while the app that owns
#                 the cache is running, and only ever deletes inside the cache folders listed here.

IFS= read -r -d '' MJ_PY_SPACE <<'PY_SPACE_LIB' || true
import glob, plistlib, shutil, subprocess

def installed_versions(apps):
    """{"ae": {"26.5", ...}, "c4d": {"2026", ...}} from the hosts' Info.plist files."""
    out = {"ae": set(), "c4d": set()}
    for p in glob.glob(os.path.join(apps, "Adobe After Effects *", "Adobe After Effects *.app", "Contents", "Info.plist")):
        try:
            v = str(plistlib.load(open(p, "rb")).get("CFBundleShortVersionString", ""))
            out["ae"].add(".".join(v.split(".")[:2]))
        except Exception:
            pass
    for d in glob.glob(os.path.join(apps, "Maxon Cinema 4D *")):
        m = re.search(r"(\d{4})$", d)
        if m:
            out["c4d"].add(m.group(1))
    return out

def ae_pref_cache_folders(home):
    """Disk-cache folders chosen in each After Effects version's preferences (Disk Cache Controls > Folder N)."""
    found = {}
    for p in glob.glob(os.path.join(home, "Library", "Preferences", "Adobe", "After Effects", "*", "Adobe After Effects * Prefs.txt")):
        ver = os.path.basename(os.path.dirname(p))
        try:
            text = open(p, "rb").read(4 << 20).decode("utf-8", "replace").replace("\r", "\n")
        except OSError:
            continue
        sec = text.split('["Disk Cache Controls"]', 1)
        if len(sec) == 2:
            m = re.search(r'"Folder \d+" = "([^"]+)"', sec[1].split("\n[", 1)[0])
            if m and m.group(1).startswith("/"):
                found[ver] = m.group(1)
    return found

def measure(path, limit=500000):
    """(bytes, files, newest mtime) without following symlinks; stops counting after limit entries."""
    total = files = 0
    newest = 0.0
    for root, dirs, names in os.walk(path):
        for n in names:
            try:
                st = os.lstat(os.path.join(root, n))
            except OSError:
                continue
            total += st.st_blocks * 512 if hasattr(st, "st_blocks") else st.st_size
            files += 1
            newest = max(newest, st.st_mtime)
            if files >= limit:
                return total, files, newest
    return total, files, newest

def known_caches(home, apps):
    inst = installed_versions(apps)
    caches = []
    def add(cid, app, kind, path, version=None, cleanable=True, note=""):
        if not os.path.isdir(path) or os.path.islink(path) or storage_class(path) == "network":
            return
        if any(c["id"] == cid for c in caches):          # two folders for one version (a custom cache drive and ~/Library/Caches)
            n = 2
            while any(c["id"] == "%s-%d" % (cid, n) for c in caches):
                n += 1
            cid = "%s-%d" % (cid, n)
        left_over = False
        if version is not None:
            left_over = version not in inst["ae" if app == "After Effects" else "c4d"]
        caches.append({"id": cid, "app": app, "kind": kind, "path": path, "version": version, "leftOver": left_over, "cleanable": cleanable, "note": note})
    roots = {os.path.join(home, "Library", "Caches")}
    roots.update(ae_pref_cache_folders(home).values())
    seen = set()
    for root in sorted(roots):
        for vdir in sorted(glob.glob(os.path.join(root, "Adobe", "After Effects", "*"))):
            ver = os.path.basename(vdir)
            for sub, kind, tag in (("Disk Cache*", "disk cache", "disk"), ("3D Cache*", "3D cache", "3d")):
                for p in sorted(glob.glob(os.path.join(vdir, sub))):
                    rp = os.path.realpath(p)
                    if rp in seen:
                        continue
                    seen.add(rp)
                    add("ae-%s-%s" % (tag, ver), "After Effects", kind, p, ver)
    common = os.path.join(home, "Library", "Application Support", "Adobe", "Common")
    add("adobe-media-cache", "Adobe video apps", "media cache files", os.path.join(common, "Media Cache Files"))
    add("adobe-media-cache-db", "Adobe video apps", "media cache database", os.path.join(common, "Media Cache"))
    add("adobe-peak-files", "Adobe video apps", "audio waveform files", os.path.join(common, "Peak Files"))
    maxon = os.path.join(home, "Library", "Preferences", "Maxon")
    for d in sorted(glob.glob(os.path.join(maxon, "Maxon Cinema 4D *", "Redshift", "Cache"))):
        folder = os.path.basename(os.path.dirname(os.path.dirname(d)))
        m = re.search(r"Cinema 4D (\d{4})", folder)
        add("redshift-" + re.sub(r"[^A-Za-z0-9]+", "-", folder.replace("Maxon Cinema 4D ", "")).strip("-").lower(), "Cinema 4D", "Redshift cache", d, m.group(1) if m else None)
    add("maxon-asset-cache", "Cinema 4D", "Asset Browser cache", os.path.join(maxon, "_assetcache"), cleanable=False,
        note="Cinema 4D manages this itself; empty it from the Asset Browser if needed.")
    return caches

APP_PROCESSES = {
    "After Effects": ("After Effects", "aerender"),
    "Adobe video apps": ("After Effects", "After Effects Render Engine", "aerender", "Adobe Premiere Pro", "Adobe Media Encoder", "Adobe Audition", "Adobe Character Animator", "Adobe Prelude"),
    "Cinema 4D": ("Cinema 4D", "Commandline", "c4dpy", "Redshift", "Team Render Client", "Team Render Server", "Team Render"),
}

def running_processes(ps):
    """Executable names of running processes, or None when they cannot be listed (then nothing is deleted)."""
    try:
        out = subprocess.run([ps, "-axo", "comm="], capture_output=True, text=True, timeout=10, stdin=subprocess.DEVNULL)
    except Exception:
        return None
    if out.returncode != 0:
        return None
    return {os.path.basename(l.strip()) for l in out.stdout.splitlines() if l.strip()}
PY_SPACE_LIB

space_python() {
  local _main=""
  IFS= read -r -d '' _main || true
  printf '%s\n%s\n%s' "$MJ_PY_PROTECT_LIB" "$MJ_PY_SPACE" "$_main" | /usr/bin/python3 - 2>/dev/null
}

handle_cache_inspect() {
  local _out=""
  cap_available python3 || { set_error "UNSUPPORTED" "Cache inspection requires python3."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 69; }
  _out=$(MJ_APPS="$MJ_HOST_APPS_DIR" space_python <<'PY_CACHE_INSPECT'
home = os.path.expanduser("~")
caches = known_caches(home, os.environ["MJ_APPS"])
for c in caches:
    c["bytes"], c["files"], newest = measure(c["path"])
    c["newest"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(newest)) if newest else None
caches.sort(key=lambda c: -c["bytes"])
print(json.dumps({"ok": True, "data": {
    "schema": "MJ_CACHE_INSPECT_1", "caches": caches,
    "totalBytes": sum(c["bytes"] for c in caches),
    "cleanableBytes": sum(c["bytes"] for c in caches if c["cleanable"]),
    "leftOverBytes": sum(c["bytes"] for c in caches if c["cleanable"] and c["leftOver"]),
}}))
PY_CACHE_INSPECT
) || true
  frames_emit_python_result "$_out"
}

handle_cache_clean() {
  local _id="" _fmt="report" _out=""
  require_arg target || { emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  _id="$MJ_REQUIRED_ARG_VALUE"
  case "$_id" in ""|*[!a-z0-9.-]*) set_error "INVALID_ARGUMENT" "target must be a cache id from cache.inspect (for example ae-disk-26.3)."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65 ;; esac
  request_arg_present format && _fmt=$(request_arg_get format)
  case "$_fmt" in report|delete) ;; *) set_error "INVALID_ARGUMENT" "format must be report (default) or delete."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65 ;; esac
  cap_available python3 || { set_error "UNSUPPORTED" "Cache cleaning requires python3."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 69; }
  _out=$(MJ_APPS="$MJ_HOST_APPS_DIR" MJ_ID="$_id" MJ_FMT="$_fmt" MJ_PS="$MJ_PS" space_python <<'PY_CACHE_CLEAN'
home = os.path.expanduser("~")
cid, delete = os.environ["MJ_ID"], os.environ["MJ_FMT"] == "delete"
c = next((x for x in known_caches(home, os.environ["MJ_APPS"]) if x["id"] == cid), None)
if c is None:
    err("NOT_FOUND", "No cache with id %s on this Mac; run cache.inspect for the list." % cid)
if not c["cleanable"]:
    err("POLICY_DENIED", "%s is not emptied by this tool. %s" % (c["kind"], c["note"]))
before, files, _ = measure(c["path"])
removed = 0
problems = []
if delete:
    procs = running_processes(os.environ["MJ_PS"])
    if procs is None:
        err("UNSUPPORTED", "Could not list running apps, so nothing was deleted.")
    # A cache left over from a version that is no longer installed cannot be in use by the installed one.
    # Executables carry the year ("Adobe Media Encoder 2026"), so match a name or "<name> <anything>".
    busy = [] if c["leftOver"] else sorted(p for p in APP_PROCESSES[c["app"]] if any(n == p or n.startswith(p + " ") for n in procs))
    if busy:
        err("HOST_BUSY", "Quit %s first; it may be using this cache." % ", ".join(busy))
    root = os.path.realpath(c["path"])
    # Empty the folder, keep the folder itself (the app expects it). Entries are removed without
    # following symlinks, and each one is re-checked to sit directly inside the cache folder.
    for name in sorted(os.listdir(root)):
        p = os.path.join(root, name)
        if os.path.dirname(os.path.realpath(p) if not os.path.islink(p) else p) != root:
            problems.append(name)
            continue
        try:
            if os.path.isdir(p) and not os.path.islink(p):
                shutil.rmtree(p)
            else:
                os.unlink(p)
            removed += 1
        except OSError:
            problems.append(name)
after = measure(c["path"])[0] if delete else before
warnings = []
if problems:
    warnings.append({"code": "CACHE_PARTLY_CLEANED", "message": "%d entr%s could not be removed." % (len(problems), "y" if len(problems) == 1 else "ies")})
print(json.dumps({"ok": True, "data": {
    "schema": "MJ_CACHE_CLEAN_1", "id": cid, "app": c["app"], "kind": c["kind"], "path": c["path"], "version": c["version"], "leftOver": c["leftOver"],
    "deleted": delete, "bytesBefore": before, "filesBefore": files, "bytesAfter": after, "bytesFreed": max(before - after, 0) if delete else 0,
    "wouldFree": before if not delete else None, "entriesRemoved": removed, "problems": problems[:20],
    "_warnings": warnings,
}}))
PY_CACHE_CLEAN
) || true
  frames_emit_python_result "$_out"
}
