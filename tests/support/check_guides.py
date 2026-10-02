# Fails (exit 1) if a guide names an mj verb or operation that does not exist.
# Usage: check_guides.py <repo root> <ops file> "<verbs>" [markdown files...]
import glob, re, sys
root, opsfile, verbs = sys.argv[1], sys.argv[2], set(sys.argv[3].split())
extra = sys.argv[4:]  # optional: markdown files to check instead of the repo guides
ops = set(open(opsfile).read().split())
files = extra or glob.glob(root + "/docs/guides/*.md") + [root + "/README.md"]
bad = []
for f in files:
    text = open(f, encoding="utf-8").read()
    for block in re.findall(r"```(?:sh|text|bash|zsh)?\n(.*?)```", text, re.S):
        for line in block.splitlines():
            m = re.match(r"^\s*\$?\s*(?:[A-Z_]+=\S+\s+)*mj\s+([A-Za-z0-9_.-]+)", line)
            if m:
                tok = m.group(1)
                if tok not in verbs and tok not in ops:
                    bad.append((f.split("/")[-1], line.strip()))
    for name in set(re.findall(r"`((?:[a-z0-9]+)\.(?:[a-z0-9]+))`", text)):
        # dotted names that look like operations (not file names like mj-config.zsh or schema ids)
        if name.split(".")[0] in {"project", "expression", "plugin", "loop", "golden", "audit", "index", "preset", "host", "ae", "c4d", "trace", "bridge", "image", "media", "file", "asset", "storage", "volume", "temp", "search", "report", "package", "system", "runtime", "deps", "handoff"} and name not in ops:
            bad.append((f.split("/")[-1], "operation `%s` does not exist" % name))
if bad:
    for b in bad: print("UNKNOWN:", b)
    sys.exit(1)
