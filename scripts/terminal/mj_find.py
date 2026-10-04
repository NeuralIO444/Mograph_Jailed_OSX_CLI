#!/usr/bin/python3
# Find the scrape reports of one project. Read-only; stdlib only; one process however many reports exist.
#
#   mj_find.py <folder> name <text> [count]    reports whose project name matches (exact, else prefix, ignoring case and .aep)
#   mj_find.py <folder> path <aep path> [count] reports made from exactly that project file
#   mj_find.py <folder> proj <name>              projects (.aep / .c4d) under <folder> by name (exact, else prefix)
#   mj_find.py <folder> versions <name> [exact]  saved versions in <folder> whose project name contains <name> (or equals it)
#   mj_find.py <report> comp <name>              the id of the comp called <name> in a report
#
# Prints the newest `count` (default 1) report paths, newest first. Exit: 0 found, 65 more than one project
# matches (the names go to stderr), 66 none.
import glob, json, os, re, sys, unicodedata


def nfc(s):
    """How names are compared: composed Unicode, ignoring case. macOS stores 'é' as e + a combining accent
    while a keyboard types one character; they look identical and must match."""
    return unicodedata.normalize("NFC", s).casefold()


PROJECT_EXTS = (".aep", ".c4d")


def find_projects(folder, query, maxdepth=3):
    """-> (exact_matches, prefix_matches), each a sorted list of paths."""
    q = nfc(query)
    for ext in PROJECT_EXTS:
        if q.endswith(ext):
            q = q[: -len(ext)]
            break
    exact, prefix = [], []
    base_depth = folder.rstrip("/").count("/")
    for root, dirs, files in os.walk(folder):
        if root.rstrip("/").count("/") - base_depth >= maxdepth - 1:
            dirs[:] = []
        for fn in files:
            low = fn.lower()
            if not low.endswith(PROJECT_EXTS):
                continue
            stem = nfc(os.path.splitext(fn)[0])
            if stem == q:
                exact.append(os.path.join(root, fn))
            elif stem.startswith(q):
                prefix.append(os.path.join(root, fn))
    return sorted(exact), sorted(prefix)


VERSION_RE = re.compile(r"^(.*)\.(\d{8}T\d{6}Z)\.([0-9a-f]{12})\.(aep|c4d)$")


def find_versions(folder, name, exact=False):
    q = nfc(name) if name else ""
    rows = []
    for fn in os.listdir(folder):
        m = VERSION_RE.match(fn)
        if not m or not os.path.isfile(os.path.join(folder, fn)):
            continue
        stem = m.group(1) + (".c4d" if m.group(4) == "c4d" else "")
        n = nfc(stem)
        if q and not (n == q or (not exact and q in n)):
            continue
        rows.append((os.path.getmtime(os.path.join(folder, fn)), os.path.join(folder, fn), stem, m.group(2), m.group(3)))
    rows.sort(key=lambda r: (-r[0], r[1]))
    return rows


def main(argv):
    if len(argv) >= 4 and argv[2] == "proj":
        exact, prefix = find_projects(argv[1], argv[3])
        if len(exact) == 1:
            print(exact[0]); return 0
        if len(prefix) == 1 and not exact:
            print(prefix[0]); return 0
        allhits = exact + prefix
        if not allhits:
            return 66
        print("\n".join(allhits)); return 65
    if len(argv) >= 4 and argv[2] == "versions":
        for mt, path, stem, ts, h in find_versions(argv[1], argv[3], len(argv) > 4 and argv[4] == "exact"):
            print("\t".join((path, stem, ts, h)))
        return 0
    if len(argv) >= 4 and argv[2] == "comp":
        try:
            doc = json.load(open(argv[1], encoding="utf-8"))
        except (OSError, ValueError):
            return 66
        want = nfc(argv[3])
        ids = [c.get("id") for c in doc.get("comps", []) if isinstance(c, dict) and isinstance(c.get("name"), str) and nfc(c["name"]) == want]
        if len(ids) == 1:
            print(ids[0]); return 0
        if len(ids) > 1:
            print("\n".join("#%s" % i for i in ids)); return 65
        print("\n".join(c["name"] for c in doc.get("comps", []) if isinstance(c, dict) and isinstance(c.get("name"), str)))
        return 66
    if len(argv) < 4 or argv[2] not in ("name", "path"):
        print("usage: mj_find.py <folder> name|path <query> [count]", file=sys.stderr)
        return 64
    folder, mode, query = argv[1], argv[2], argv[3]
    count = int(argv[4]) if len(argv) > 4 and argv[4].isdigit() else 1
    files = sorted(glob.glob(os.path.join(folder, "*.scrape.json")), key=lambda p: (-os.path.getmtime(p), p))[:2000]
    want = os.path.realpath(query) if mode == "path" else None
    stem = nfc(query)
    if stem.endswith(".aep"):
        stem = stem[:-4]
    rows = []                                     # (report, projectPath, projectName) newest first
    for f in files:
        try:
            with open(f, "rb") as fh:
                head = json.loads(fh.read(8 << 20).decode("utf-8", "replace"))
        except (OSError, ValueError):
            continue
        if isinstance(head, dict) and isinstance(head.get("projectName"), str):
            rows.append((f, str(head.get("projectPath") or ""), head["projectName"]))
    if mode == "path":
        hit = [r[0] for r in rows if r[1] and os.path.realpath(r[1]) == want]
    else:
        def name_of(r):
            n = nfc(r[2])
            return n[:-4] if n.endswith(".aep") else n
        hit_rows = [r for r in rows if name_of(r) == stem] or [r for r in rows if name_of(r).startswith(stem)]
        projects = {}
        for r in hit_rows:
            projects.setdefault(r[1] or r[2], r[2])
        if len(projects) > 1:
            print("\n".join("  %s" % n for n in sorted(set(projects.values()), key=str.lower)), file=sys.stderr)
            return 65
        hit = [r[0] for r in hit_rows]
    if not hit:
        return 66
    print("\n".join(hit[:count]))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
