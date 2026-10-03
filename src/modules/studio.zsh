# Studio operations over MJ_PROJECT_SCRAPE_1 receipts.
#
# project.preflight — will this project open cleanly on this Mac? Fonts (After Effects' own missing-font
#                     report plus a scan of this Mac's font folders), footage that is missing or no longer
#                     on disk, and third-party effects to confirm. Read-only.

IFS= read -r -d '' MJ_PY_FONTS <<'PY_FONTS_LIB' || true
import struct

FONT_EXTS = (".ttf", ".otf", ".ttc", ".otc")
FONT_MAX_FILES = 20000

def default_font_dirs():
    home = os.path.expanduser("~")
    dirs = ["/System/Library/Fonts", "/Library/Fonts", home + "/Library/Fonts",
            home + "/Library/Application Support/Adobe/CoreSync/plugins/livetype"]
    try:
        assets = "/System/Library/AssetsV2"
        dirs += sorted(os.path.join(assets, d) for d in os.listdir(assets) if d.startswith("com_apple_MobileAsset_Font"))
    except OSError:
        pass
    return dirs

def _names_at(f, base):
    """PostScript, family, typographic family and full names of the sfnt font at offset base."""
    f.seek(base)
    hdr = f.read(12)
    if len(hdr) < 12:
        return []
    num = struct.unpack(">H", hdr[4:6])[0]
    recs = f.read(16 * num)
    for i in range(num):
        tag, _, off, length = struct.unpack(">4sIII", recs[16 * i:16 * i + 16])
        if tag != b"name":
            continue
        f.seek(off)
        data = f.read(min(length, 1 << 20))
        if len(data) < 6:
            return []
        count, soff = struct.unpack(">HH", data[2:6])
        out = []
        for j in range(count):
            r = data[6 + 12 * j:18 + 12 * j]
            if len(r) < 12:
                break
            plat, enc, lang, nid, ln, o = struct.unpack(">HHHHHH", r)
            if nid not in (1, 4, 6, 16):
                continue
            raw = data[soff + o:soff + o + ln]
            try:
                s = raw.decode("utf-16-be") if plat in (0, 3) else raw.decode("mac_roman")
            except Exception:
                continue
            if s:
                out.append(s)
        return out
    return []

def font_names(path):
    try:
        with open(path, "rb") as f:
            head = f.read(12)
            if head[:4] in (b"ttcf",):
                n = struct.unpack(">I", head[8:12])[0]
                f.seek(12)
                offs = struct.unpack(">%dI" % min(n, 256), f.read(4 * min(n, 256)))
                names = []
                for o in offs:
                    names += _names_at(f, o)
                return names
            if head[:4] in (b"\x00\x01\x00\x00", b"OTTO", b"true"):
                return _names_at(f, 0)
    except (OSError, struct.error):
        pass
    return []

def norm_font(s):
    return "".join(ch for ch in s.lower() if ch.isalnum())

def scan_fonts(dirs, cache_path=""):
    """Set of normalized names from every font file under dirs, plus scan facts. With cache_path, a file
    whose size and modification time are unchanged is not read again (the index lives in the private store)."""
    cache = {}
    if cache_path:
        try:
            with open(cache_path, encoding="utf-8") as f:
                doc = json.load(f)
            if isinstance(doc, dict) and doc.get("v") == 1 and isinstance(doc.get("files"), dict):
                cache = doc["files"]
        except (OSError, ValueError):
            cache = {}
    fresh, names, files, scanned = {}, set(), 0, []
    for d in dirs:
        if not os.path.isdir(d) or storage_class(d) == "network":
            continue
        scanned.append(d)
        for root, subdirs, fnames in os.walk(d):
            for fn in fnames:
                # Adobe Fonts (livetype) stores fonts as extensionless hidden files; read their header too.
                if not fn.lower().endswith(FONT_EXTS) and "livetype" not in root:
                    continue
                files += 1
                if files > FONT_MAX_FILES:
                    return names, files, scanned, True
                p = os.path.join(root, fn)
                try:
                    st = os.stat(p)
                except OSError:
                    continue
                hit = cache.get(p)
                if isinstance(hit, list) and len(hit) == 3 and hit[0] == st.st_size and hit[1] == st.st_mtime_ns and isinstance(hit[2], list):
                    found = hit[2]
                else:
                    found = sorted({norm_font(n) for n in font_names(p)})
                fresh[p] = [st.st_size, st.st_mtime_ns, found]
                names.update(found)
    if cache_path and fresh != cache:
        try:
            tmp = "%s.%d" % (cache_path, os.getpid())
            with open(tmp, "w", encoding="utf-8") as f:
                json.dump({"v": 1, "files": fresh}, f, separators=(",", ":"))
            os.replace(tmp, cache_path)
        except OSError:
            pass
    return names, files, scanned, False
PY_FONTS_LIB

studio_python() {
  local _main=""
  IFS= read -r -d '' _main || true
  printf '%s\n%s\n%s' "$MJ_PY_PROTECT_LIB" "$MJ_PY_FONTS" "$_main" | /usr/bin/python3 - 2>/dev/null
}

handle_project_preflight() {
  local _rc=0 _path="" _out=""
  require_arg path || { emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  _path="$MJ_REQUIRED_ARG_VALUE"
  project_require_scrape_file "$_path" || { _rc=$?; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return $_rc; }
  local _fc=""; library_store_dir_ready && _fc="$(library_store_dir)/fonts.json"
  _out=$(MJ_SCRAPE="$_path" MJ_FONT_CACHE="$_fc" MJ_FONT_DIRS="${MJ_FONT_DIRS:-}" MJ_FONT_DIRS_ONLY="${MJ_FONT_DIRS_ONLY:-}" studio_python <<'PY_PREFLIGHT'
id0 = tree_id(os.environ["MJ_SCRAPE"])
d = load_scrape(os.environ["MJ_SCRAPE"])
extra = [p for p in os.environ.get("MJ_FONT_DIRS", "").split(":") if p.startswith("/")]
dirs = extra if os.environ.get("MJ_FONT_DIRS_ONLY") == "1" else extra + default_font_dirs()
installed, nfiles, scanned, capped = scan_fonts(dirs, os.environ.get("MJ_FONT_CACHE", ""))

# Which layers use each font, so a problem can be traced.
uses = {}
for c in d["comps"]:
    if not isinstance(c, dict):
        continue
    for l in c.get("layers") or []:
        if isinstance(l, dict) and l.get("font"):
            uses.setdefault(l["font"], []).append({"comp": c.get("name", ""), "layer": l.get("name", "")})
ae_missing = d.get("missingFonts")
ae_missing = set(ae_missing) if isinstance(ae_missing, list) else None
fonts = []
for name in sorted(set(x for x in d["fonts"] if isinstance(x, str)) | set(uses)):
    here = norm_font(name) in installed
    if ae_missing is not None and name in ae_missing:
        state = "missing"            # After Effects said so when the project was scraped
    elif here:
        state = "installed"
    else:
        state = "notFound"           # not in any scanned font folder (a font manager may still provide it)
    fonts.append({"name": name, "state": state, "foundOnThisMac": here, "uses": uses.get(name, [])[:20]})

footage = []
for f in d["footage"]:
    if not isinstance(f, dict) or f.get("kind") in ("solid", "placeholder"):
        continue
    p = f.get("path") or ""
    reported = bool(f.get("missing"))
    if not p:
        if reported:
            footage.append({"name": f.get("name", ""), "path": "", "state": "missing", "storage": "none"})
        continue
    cls = storage_class(p)
    if cls != "local":
        if reported:
            footage.append({"name": f.get("name", ""), "path": p, "state": "missing", "storage": cls})
        continue                     # network volumes are never touched
    gone = not os.path.exists(p)
    if reported or gone:
        footage.append({"name": f.get("name", ""), "path": p, "state": "missing" if reported else "goneSinceScrape", "storage": cls})

FIRST_PARTY = ("ADBE ", "CC ", "APC ", "Mettle", "VISINF", "Keylight", "ISL ", "CS ", "PEDG")
fx = {}
for c in d["comps"]:
    if not isinstance(c, dict):
        continue
    for l in c.get("layers") or []:
        if not isinstance(l, dict):
            continue
        for e in l.get("effects") or []:
            mn = (e or {}).get("matchName", "") if isinstance(e, dict) else ""
            if mn and not mn.startswith(FIRST_PARTY):
                rec = fx.setdefault(mn, {"matchName": mn, "name": e.get("name", ""), "layers": 0})
                rec["layers"] += 1
third = sorted(fx.values(), key=lambda r: r["matchName"])

bad_fonts = [f for f in fonts if f["state"] != "installed"]
problems = len(bad_fonts) + len(footage)
warnings = []
if ae_missing is None:
    warnings.append({"code": "FONT_REPORT_UNAVAILABLE", "message": "This scrape has no After Effects missing-font report (scraper older than 1.1 or After Effects older than 24.0); font status comes from scanning this Mac's font folders only."})
if capped:
    warnings.append({"code": "FONT_SCAN_CAPPED", "message": "Stopped after %d font files; some installed fonts may not have been seen." % FONT_MAX_FILES})
print(json.dumps({"ok": True, "data": {
    "schema": "MJ_PREFLIGHT_1", "projectName": d.get("projectName"), "projectPath": d.get("projectPath"), "scrapedAt": d.get("scrapedAt"),
    "ready": problems == 0, "problems": problems,
    "fonts": fonts, "fontsMissing": len(bad_fonts),
    "fontScan": {"dirs": scanned, "files": nfiles, "names": len(installed)},
    "footage": footage, "footageMissing": len(footage),
    "thirdPartyEffects": third,
    "sourceUnchanged": tree_id(os.environ["MJ_SCRAPE"]) == id0,
    "_warnings": warnings,
}}))
PY_PREFLIGHT
) || true
  frames_emit_python_result "$_out"
}
