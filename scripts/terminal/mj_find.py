#!/usr/bin/python3
# Find the scrape reports of one project. Read-only; stdlib only; one process however many reports exist.
#
#   mj_find.py <folder> name <text> [count]    reports whose project name matches (exact, else prefix, ignoring case and .aep)
#   mj_find.py <folder> path <aep path> [count] reports made from exactly that project file
#
# Prints the newest `count` (default 1) report paths, newest first. Exit: 0 found, 65 more than one project
# matches (the names go to stderr), 66 none.
import glob, json, os, sys


def main(argv):
    if len(argv) < 4 or argv[2] not in ("name", "path"):
        print("usage: mj_find.py <folder> name|path <query> [count]", file=sys.stderr)
        return 64
    folder, mode, query = argv[1], argv[2], argv[3]
    count = int(argv[4]) if len(argv) > 4 and argv[4].isdigit() else 1
    files = sorted(glob.glob(os.path.join(folder, "*.scrape.json")), key=lambda p: (-os.path.getmtime(p), p))[:2000]
    want = os.path.realpath(query) if mode == "path" else None
    stem = query.lower()
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
            n = r[2].lower()
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
