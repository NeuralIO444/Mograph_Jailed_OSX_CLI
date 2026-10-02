#!/usr/bin/python3
# Turn a MographJailed receipt or response into plain language. Read-only; stdlib only.
#
#   mj_explain.py <file | ->        explain a response envelope or a bare receipt
#
# Exit codes: 0 explained, 64 usage, 65 not something this tool understands, 66 file not found.

import json, os, re, sys, textwrap

ROOT = os.environ.get("MOGRAPHJAILED_ROOT") or os.path.join(os.path.expanduser("~"), "Documents", "MographJailed")
HERE = os.path.dirname(os.path.abspath(__file__))
ERRORS_MD = next((p for p in (os.path.join(HERE, "..", "..", "docs", "man", "errors.md"), os.path.join(ROOT, "docs", "man", "errors.md")) if os.path.isfile(p)), None)


def plural(n, one, many=None):
    return "%s %s" % (n, one if n == 1 else (many or one + "s"))


def names(items, limit=5):
    items = [str(i) for i in items]
    out = ", ".join(items[:limit])
    return out + (" and %d more" % (len(items) - limit) if len(items) > limit else "")


def wrap(text, indent="  "):
    return textwrap.fill(text, width=88, initial_indent=indent, subsequent_indent=indent)


def secs(s):
    s = float(s or 0)
    return "%d s" % round(s) if s < 120 else "%.1f min" % (s / 60)


def mb(n):
    n = float(n or 0)
    if n >= 1073741824:
        return "%.1f GB" % (n / 1073741824)
    if n >= 1048576:
        return "%.1f MB" % (n / 1048576)
    return "%d KB" % round(n / 1024) if n >= 1024 else "%d bytes" % n


def error_help(code):
    """(meaning, what to do) for an error code, taken from the error reference."""
    if not ERRORS_MD:
        return None
    for line in open(ERRORS_MD, encoding="utf-8"):
        m = re.match(r"^\| `%s` \| \d+ \| (.+?) \| (.+?) \|$" % re.escape(code), line)
        if m:
            return m.group(1), m.group(2)
    return None


# Failures after which something is deliberately left behind for the user to inspect.
KEPT_ON_ERROR = {
    "RENDER_FAILED": "The render folder, its log and receipt were kept so you can see what happened. Your project was not changed.",
    "RENDER_TIMEOUT": "The render folder, its log and receipt were kept. Your project was not changed.",
    "RENDER_INCOMPLETE": "The frames that were made, the log and receipt were kept. Your project was not changed.",
    "LICENCE_NOT_CONFIGURED": "The log and receipt were kept. Your project was not changed.",
    "STAGE_CLEANUP_REFUSED": "A temporary working folder was left in place on purpose (see the message). Your files were not changed.",
}


def explain_error(env):
    e = env.get("error") or {}
    code = e.get("code", "ERROR")
    out = ["That did not work (%s)." % code, wrap(e.get("message", ""))]
    h = error_help(code)
    if h:
        out += ["", wrap("What it means: " + h[0]), wrap("What to do: " + h[1])]
    out.append("")
    if code in KEPT_ON_ERROR:
        out.append(KEPT_ON_ERROR[code])
    else:
        out.append("Nothing was changed.")
    return out


def scrape_counts(d):
    comps = d.get("comps") or []
    layers = sum(len(c.get("layers") or []) for c in comps if isinstance(c, dict))
    return len(comps), layers


def explain_summary(d):
    out = ["%s (After Effects %s)" % (d.get("projectName", "Project"), d.get("aeVersion", "?")), ""]
    out.append("%s, %s, %s, %s." % (plural(d.get("numComps", 0), "comp"), plural(d.get("numLayers", 0), "layer"),
                                    plural(d.get("numEffects", 0), "effect"), plural(d.get("numFonts", 0), "font")))
    missing = d.get("footageMissing") or []
    unlinked = d.get("footageUnlinked") or []
    out.append("Footage: %s." % plural(d.get("numFootage", 0), "item"))
    out.append(("Missing: %s." % names(missing)) if missing else "No footage is missing.")
    if unlinked:
        out.append("Not linked to a file: %s." % names(unlinked))
    out.append("Expressions: %d." % d.get("numExpressions", 0))
    if d.get("fonts"):
        out.append("Fonts used: %s." % names(d["fonts"], 8))
    return out


def explain_lint(d):
    n = d.get("numFindings", 0)
    out = ["Checked %s." % plural(d.get("numExpressions", 0), "expression")]
    if n == 0:
        out.append("No problems found.")
        return out
    out.append("Found %s: %s, %s, %s." % (plural(n, "problem"), plural(d.get("errors", 0), "error"), plural(d.get("warnings", 0), "warning"), plural(d.get("info", 0), "note")))
    teaching = d.get("teaching") or {}
    seen = set()
    for f in d.get("findings", []):
        out.append("")
        sev = {"error": "Error", "warning": "Warning", "info": "Note"}.get(f.get("severity"), "Note")
        out.append("%s in \"%s\" > %s > %s" % (sev, f.get("comp"), f.get("layer"), f.get("propertyPath")))
        out.append(wrap(f.get("message", "")))
        t = f.get("teach") or {}
        if t.get("why"):
            out.append(wrap("Why it matters: " + t["why"]))
            out.append(wrap("Fix: " + t["fix"]))
        ex = teaching.get(f.get("code"))
        if ex and f.get("code") not in seen:
            seen.add(f["code"])
            out.append("  Example, before:  " + ex["before"])
            out.append("  Example, after:   " + ex["after"])
    if d.get("findingsTruncated"):
        out += ["", "More problems exist than are listed here; fix these and run it again."]
    return out


def explain_snapshot(d):
    if d.get("snapshotCreated") is False:
        return ["Nothing to save: %s has not changed since the last snapshot." % os.path.basename(d.get("sourcePath", "the project"))]
    out = ["Saved a verified copy of %s." % os.path.basename(d.get("sourcePath", "the project")), "  %s" % d.get("snapshotPath", "")]
    out.append("  %s copied%s; the copy and the original were checked and match." % (mb(d.get("bytesCopied")), " instantly (copy-on-write)" if d.get("cloneUsed") else ""))
    return out


def explain_render(d):
    host = {"afterEffects": "After Effects", "cinema4d": "Cinema 4D"}.get(d.get("host"), d.get("host", "Host"))
    fr = d.get("frames") or {}
    exp = fr.get("expected")
    out = ["%s render finished: %s." % (host, d.get("status", "?"))]
    out.append("%s%s in %s." % (plural(fr.get("count", 0), "frame"), (" of %s expected" % exp) if exp else "", secs(d.get("seconds"))))
    out.append("Saved in %s" % d.get("outputDir", ""))
    src = d.get("source") or {}
    out.append("The original file was left untouched." if src.get("unchanged", True) else "Warning: the original file changed while it rendered.")
    return out


def explain_golden(d):
    out = []
    if d.get("passed"):
        out.append("Golden check passed: all %s match the record%s." % (plural(d.get("framesRecorded", 0), "frame"), " (%s)" % d.get("label") if d.get("label") else ""))
    else:
        out.append("Golden check failed: %d of %d frames no longer match." % (d.get("framesFailed", 0), d.get("framesRecorded", 0)))
        bad = [f for f in d.get("frames", []) if f.get("status") in ("changed", "missing")]
        for f in bad[:8]:
            out.append("  %s: %s%s" % (f["name"], f["status"], (" (similarity %.2f)" % f["score"]) if f.get("score") is not None else ""))
    if d.get("worstScore") is not None:
        out.append("Lowest similarity: %.2f (needs %.2f)." % (d["worstScore"], d.get("threshold", 0)))
    if d.get("extraFrames"):
        out.append("Not in the record, so not checked: %s." % names(d["extraFrames"]))
    return out


def explain_loop(d):
    out = ["Looked at %s for a seamless loop." % plural(d.get("frameCount", 0), "frame")]
    for c in d.get("candidates", [])[:5]:
        out.append("  #%d: play frames %d to %d (%s long), match %d%%" % (c["rank"], c["startFrame"], c["endFrame"] - 1, plural(c["lengthFrames"], "frame"), round(c["score"] * 100)))
    if d.get("candidates"):
        out.append("A higher match means the last frame looks more like the first.")
    return out


def explain_deps(d):
    out = ["%s uses %s." % (d.get("projectName", "The project"), plural(len(d.get("dependencies", [])), "dependency", "dependencies"))]
    if d.get("missingFootage"):
        out.append("Missing: %s." % names([os.path.basename(p) for p in d["missingFootage"]]))
    else:
        out.append("Nothing it uses is missing.")
    if d.get("unverifiedFootage"):
        out.append("%d files are on network or unknown storage and were not checked." % len(d["unverifiedFootage"]))
    for s in d.get("singlePointsOfFailure", [])[:5]:
        out.append("If %s goes missing, %s break (%s)." % (os.path.basename(s["id"]) if s["kind"] == "footage" else s["id"], plural(len(s["impactedComps"]), "comp"), names(s["impactedComps"])))
    return out


def explain_handoff(d):
    out = ["Built the handoff folder: %s" % d.get("handoffPath", ""), "  %s collected (%s)." % (plural(d.get("filesCollected", 0), "file"), mb(d.get("bytesCollected")))]
    if d.get("fonts"):
        out.append("  Fonts to install: %s." % names(d["fonts"], 8))
    if d.get("missingFootage"):
        out.append("  Not included, missing: %s." % names([os.path.basename(p) for p in d["missingFootage"]]))
    if d.get("skippedFootage"):
        out.append("  Not copied (network storage): %d files." % len(d["skippedFootage"]))
    out.append("  A manifest with a checksum for every file is inside.")
    return out


def explain_health(d):
    out = ["%s health: %d out of 100 (%s)." % (d.get("projectName", "Project"), d["score"], d["band"])]
    for c in d.get("components", []):
        if not c.get("measured", True):
            out.append("  %s: not measured (set a versions folder: mj config set versions_dir <folder>)." % c["name"])
        elif c["points"] < c["max"]:
            out.append("  %s: lost %d of %d points. %s" % (c["name"], c["max"] - c["points"], c["max"], c["why"]))
    if d["score"] == 100:
        out.append("  Nothing to fix.")
    if d.get("trend"):
        t = d["trend"]
        out.append("Trend over %s: %s" % (plural(len(t), "recorded score"), "improving" if t[-1] > t[0] else "getting worse" if t[-1] < t[0] else "steady"))
    out.append("Score formula version %s." % d.get("formulaVersion"))
    return out


def explain_diff(d):
    out = ["Comparing %s with %s." % (os.path.basename(d.get("before", {}).get("path", "before")), os.path.basename(d.get("after", {}).get("path", "after")))]
    s = d.get("summary", {})
    if d.get("identical"):
        return out + ["No differences."]
    for key, one, many in (("compsAdded", "comp added", "comps added"), ("compsRemoved", "comp removed", "comps removed"), ("compsChanged", "comp changed", "comps changed"),
                           ("layersAdded", "layer added", "layers added"), ("layersRemoved", "layer removed", "layers removed"), ("layersChanged", "layer changed", "layers changed"),
                           ("layersMoved", "layer moved in the stack", "layers moved in the stack"), ("expressionsChanged", "expression changed", "expressions changed"),
                           ("footageAdded", "footage item added", "footage items added"), ("footageRemoved", "footage item removed", "footage items removed"),
                           ("footageMissingChanged", "footage item went missing or came back", "footage items went missing or came back"), ("footageMoved", "footage file moved", "footage files moved"),
                           ("fontsAdded", "font added", "fonts added"), ("fontsRemoved", "font removed", "fonts removed"),
                           ("effectsAdded", "effect type added", "effect types added"), ("effectsRemoved", "effect type removed", "effect types removed")):
        if s.get(key):
            out.append("  %d %s" % (s[key], one if s[key] == 1 else many))
    for ch in d.get("changes", [])[:12]:
        out.append("  - " + ch["text"])
    if d.get("changesTruncated"):
        out.append("  (more changes than listed)")
    return out


def explain_trace(d):
    out = []
    if not d.get("projects"):
        return ["Nothing matched."]
    for p in d["projects"]:
        out.append(p["projectPath"])
        for m in p["matches"]:
            out.append("  %s%s" % (m["name"], " (missing)" if m.get("missing") else ""))
            for u in m.get("uses", [])[:6]:
                out.append("    used by layer \"%s\" in %s" % (u["layer"], " > ".join(u["paths"][0].split(" > ")) if u.get("paths") else u["comp"]))
            if not m.get("uses"):
                out.append("    not used by any layer")
    return out


def explain_plugins(d):
    if d.get("schema") == "MJ_PLUGIN_USAGE_1":
        out = ["%s is used in %s." % (d["matchName"], plural(d["projectCount"], "project"))]
        out += ["  " + p["projectPath"] for p in d.get("projects", [])[:15]]
        return out
    out = ["%s across %s." % (plural(d.get("distinctEffects", 0), "effect type"), plural(d.get("projectsIndexed", 0), "project"))]
    out += ["  %s: %s" % (e["matchName"], plural(e["projects"], "project")) for e in d.get("effects", [])[:12]]
    return out


def explain_audit(d):
    if d.get("valid"):
        return ["No edits, insertions or deletions found in the request log (%s checked)." % plural(d.get("entriesVerified", 0), "entry", "entries"),
                "A log cut short at the end, or rebuilt from scratch, cannot be detected from the log alone; keep a copy of the head hash (%s) elsewhere to check." % (d.get("headHash") or "")[:12]]
    return ["The request log has been tampered with: it breaks at line %s (%s)." % (d.get("firstBrokenLine"), d.get("reason"))]


def explain_hosts(d):
    out = []
    for h in d.get("afterEffects", []):
        out.append("After Effects %s: %s" % (h["year"], "ready" if h["supported"] else "not usable (%s)" % ("older than 2024" if h["complete"] else "incomplete install")))
    for h in d.get("cinema4d", []):
        out.append("Cinema 4D %s: %s%s" % (h["year"], "ready" if h["supported"] else "not usable", ", Redshift installed" if h.get("redshift") else ""))
    if not out:
        out.append("Neither After Effects nor Cinema 4D (2024 or newer) was found.")
    return out


def explain_doctor(d):
    ops = d.get("operations") or {}
    g = d.get("guidance") or []
    mac = d.get("isMacOS", True)
    head = [] if mac else ["This is not a Mac, so some features are unavailable here.", ""]
    if not g:
        return head + (["This Mac is ready. All %s operations can run." % ops.get("total", "")] if mac else ["No tools are missing."])
    out = head + ["This %s can run %d of %d operations. %d are blocked by missing tools:" % ("Mac" if mac else "machine", ops.get("total", 0) - ops.get("unavailable", 0), ops.get("total", 0), ops.get("unavailable", 0))]
    for item in g:
        out += ["", "%s is missing and blocks %s: %s." % (item["capability"], plural(len(item["unlocks"]), "operation"), names(item["unlocks"], 6)), wrap("What to do: " + item["hint"])]
    return out


def explain_c4d_summary(d):
    out = ["%s (Cinema 4D %s, %s renderer)" % (d["sceneName"], d["c4dVersion"], d["renderer"]), "",
           "%d x %d at %s fps, frames %d to %d (%s, %.2f seconds)." % (d["width"], d["height"], d["fps"], d["startFrame"], d["endFrame"], plural(d["frames"], "frame"), d["seconds"])]
    out.append("Output: %s" % (d["outputPath"] or "none set"))
    if d.get("passes"):
        out.append("Passes: %s." % names(d["passes"], 8))
    out.append("%s%s." % (plural(d["cameras"], "camera"), (" (active: %s)" % d["activeCamera"]) if d.get("activeCamera") else ""))
    m = d["materials"]
    out.append("%s%s." % (plural(m["total"], "material"), (": " + ", ".join("%d %s" % (v, k) for k, v in sorted(m["byType"].items()))) if m["byType"] else ""))
    t = d["textures"]
    out.append("%s; %s." % (plural(t["total"], "texture"), ("%d missing (%s)" % (len(t["missing"]), names(t["missing"]))) if t["missing"] else "none missing"))
    if t["absolute"]:
        out.append("Absolute paths: %s." % names(t["absolute"]))
    return out


def explain_c4d_lint(d):
    n = d["numFindings"]
    out = ["Checked %s (%s renderer)." % (d["sceneName"], d["renderer"])]
    if not n:
        return out + ["No problems found."]
    out.append("Found %s: %s, %s, %s." % (plural(n, "problem"), plural(d["errors"], "error"), plural(d["warnings"], "warning"), plural(d["info"], "note")))
    seen = set()
    for f in d["findings"]:
        out += ["", {"error": "Error", "warning": "Warning", "info": "Note"}[f["severity"]] + ": " + f["message"], wrap("Why it matters: " + f["teach"]["why"]), wrap("Fix: " + f["teach"]["fix"])]
        ex = (d.get("teaching") or {}).get(f["code"])
        if ex and f["code"] not in seen:
            seen.add(f["code"]); out += ["  Example, before:  " + ex["before"], "  Example, after:   " + ex["after"]]
    return out


def explain_bridge(d):
    s = d["scene"]
    out = ["%s against %s: %s used in After Effects." % (d["sceneName"], d.get("projectName") or "the project", plural(d["matched"], "layer"))]
    if not d["matched"]:
        return out + ["Nothing was compared."]
    out.append("The scene is %d x %d at %s fps, %s (%.2f seconds), %s." % (s["width"], s["height"], s["fps"], plural(s["frames"], "frame"), s["seconds"], s["renderer"]))
    if d["consistent"]:
        return out + ["Everything matches."]
    for f in d["findings"]:
        out += ["", {"error": "Error", "warning": "Warning", "info": "Note"}[f["severity"]] + ": " + f["message"], wrap("Why it matters: " + f["teach"]["why"]), wrap("Fix: " + f["teach"]["fix"])]
    return out


def explain_scrape(d):
    c, l = scrape_counts(d)
    miss = [f.get("name") for f in d.get("footage", []) if isinstance(f, dict) and f.get("missing")]
    out = ["Scrape of %s taken %s." % (d.get("projectName", "a project"), d.get("scrapedAt", "")), "%s and %s." % (plural(c, "comp"), plural(l, "layer"))]
    out.append(("Missing footage: %s." % names(miss)) if miss else "No footage is missing.")
    return out


FONT_STATE = {"missing": "missing (After Effects reported it)", "notFound": "not found on this Mac"}


def explain_preflight(d):
    out = ["%s: %s." % (d.get("projectName", "Project"), "ready to open on this Mac" if d.get("ready") else "%s before it opens cleanly" % plural(d["problems"], "thing to fix", "things to fix"))]
    for f in d.get("fonts", []):
        if f["state"] != "installed":
            where = f["uses"][0] if f.get("uses") else None
            out.append('  Font %s is %s%s.' % (f["name"], FONT_STATE.get(f["state"], f["state"]), ' (used by "%s" in %s)' % (where["layer"], where["comp"]) if where else ""))
    for f in d.get("footage", []):
        out.append("  Footage %s is %s." % (f["name"], "missing" if f["state"] == "missing" else "no longer on disk (it was there when the project was scraped)"))
    if d.get("thirdPartyEffects"):
        out.append("  Third-party effects to confirm are installed: %s." % names(["%s (%s)" % (e["name"], e["matchName"]) if e.get("name") and e["name"] != e["matchName"] else e["matchName"] for e in d["thirdPartyEffects"]]))
    return out


def explain_check(lint, health, pre):
    """mj check: one verdict from expression.lint, project.health and project.preflight data."""
    errs, warns = lint.get("errors", 0), lint.get("warnings", 0)
    fix = errs + pre.get("problems", 0)
    name = pre.get("projectName") or health.get("projectName") or "Project"
    verdict = "ready" if fix == 0 and warns == 0 else ("ready, with %s to look at" % plural(warns, "warning")) if fix == 0 else plural(fix, "thing to fix", "things to fix")
    out = ["%s: %s." % (name, verdict), ""]
    mark = lambda ok: "  ok " if ok else "  !! "
    out.append(mark(errs == 0) + "Expressions: %s, %s." % (plural(errs, "error"), plural(warns, "warning")))
    out.append(mark(health.get("score", 0) >= 90) + "Health: %d out of 100 (%s)." % (health.get("score", 0), health.get("band", "?")))
    bad_fonts = [f["name"] for f in pre.get("fonts", []) if f["state"] != "installed"]
    out.append(mark(not bad_fonts) + ("Fonts: all %d found." % len(pre.get("fonts", [])) if not bad_fonts else "Fonts: %s missing (%s)." % (len(bad_fonts), names(bad_fonts))))
    gone = [f["name"] for f in pre.get("footage", [])]
    out.append(mark(not gone) + ("Footage: nothing missing." if not gone else "Footage: %s missing (%s)." % (len(gone), names(gone))))
    tp = pre.get("thirdPartyEffects", [])
    if tp:
        out.append("  ?? Third-party effects to confirm: %s." % names([e["matchName"] for e in tp]))
    if fix or warns:
        out += ["", "Details: mj lint, mj health, mj explain on the preflight (or mj check --details)."]
    return out, fix == 0


def explain_timeline(folder):
    """mj timeline: folder holds NN.scrape (path), NN.health.json, NN.diff.json and snapshots.txt."""
    rows = []
    i = 0
    while os.path.exists(os.path.join(folder, "%03d.scrape" % i)):
        base = os.path.join(folder, "%03d" % i)
        scrape = json.load(open(base + ".scrape", encoding="utf-8"))
        health = json.load(open(base + ".health.json", encoding="utf-8")).get("data") or {}
        diff = None
        if os.path.exists(base + ".diff.json"):
            diff = json.load(open(base + ".diff.json", encoding="utf-8")).get("data") or {}
        if diff is None:
            what = "first scrape"
        elif diff.get("identical"):
            what = "no changes"
        else:
            what = "; ".join(ch["text"] for ch in diff.get("changes", [])[:3])
            more = len(diff.get("changes", [])) - 3
            if more > 0:
                what += "; and %d more" % more
        rows.append((scrape["at"], "  %s   health %3s   %s" % (scrape["at"].replace("T", " ")[:16], health.get("score", "?"), what), scrape))
        i += 1
    snaps = os.path.join(folder, "snapshots.txt")
    if os.path.exists(snaps):
        for line in open(snaps, encoding="utf-8"):
            m = re.match(r"^(.*)\.(\d{4})(\d\d)(\d\d)T(\d\d)(\d\d)(\d\d)Z\.([0-9a-f]{12})\.(aep|c4d)$", os.path.basename(line.strip()))
            if m:
                at = "%s-%s-%sT%s:%s:%sZ" % m.group(2, 3, 4, 5, 6, 7)
                rows.append((at, "  %s   snapshot   %s" % (at.replace("T", " ")[:16], m.group(8)), None))
    rows.sort(key=lambda r: r[0])
    if not rows:
        return ["Nothing recorded for this project yet."]
    name = next((r[2]["name"] for r in rows if r[2]), "Project")
    n = sum(1 for r in rows if r[2])
    out = ["%s: %s and %s, oldest first (times are UTC)." % (name, plural(n, "scrape"), plural(len(rows) - n, "snapshot"))]
    out += [r[1] for r in rows]
    if len(rows) - n:
        out += ["", "Get a version back as a new file:  mj project.restore path=<snapshot> output=<folder>"]
    return out


def cache_title(c):
    who = c["app"] + (" " + c["version"] if c.get("version") and c["app"] != "Cinema 4D" else "")
    if c["app"] == "Cinema 4D" and c.get("version"):
        who = "Cinema 4D %s" % c["version"]
    return "%s %s" % (who, c["kind"])


def explain_cache_inspect(d):
    shown = [c for c in d["caches"] if c["bytes"] > 0]
    out = ["Caches on this Mac: %s (%s can be emptied safely; %s is left over from versions that are no longer installed)." % (mb(d["totalBytes"]), mb(d["cleanableBytes"]), mb(d["leftOverBytes"]))]
    if not shown:
        return ["No cache folders with anything in them were found."]
    for c in shown:
        tag = "left over, not installed" if c["leftOver"] and c["cleanable"] else ("managed by the app" if not c["cleanable"] else "")
        out.append("  %9s  %-42s %-26s %s" % (mb(c["bytes"]), cache_title(c), tag, c["id"] if c["cleanable"] else ""))
    out += ["", "See what one would free:   mj space clean <id>", "Empty it (app must be closed):   mj space clean <id> --yes"]
    if d["leftOverBytes"]:
        out.append("Empty everything left over from old versions:   mj space clean leftovers --yes")
    return out


def explain_cache_clean(d):
    title = cache_title(d)
    if not d["deleted"]:
        return ["Emptying the %s would free %s (%s)." % (title, mb(d["wouldFree"]), plural(d["filesBefore"], "file")), "  " + d["path"],
                "Nothing was deleted. To empty it%s, run:  mj space clean %s --yes" % ("" if d.get("leftOver") else " (quit %s first)" % d["app"], d["id"])]
    out = ["Emptied the %s: freed %s." % (title, mb(d["bytesFreed"]))]
    if d.get("problems"):
        out.append("  Could not remove: %s." % names(d["problems"]))
    return out


EXPLAINERS = {
    "MJ_PROJECT_SUMMARY_1": explain_summary, "MJ_EXPRESSION_LINT_1": explain_lint, "MJ_PROJECT_SNAPSHOT_1": explain_snapshot,
    "MJ_RENDER_1": explain_render, "MJ_GOLDEN_CHECK_1": explain_golden, "MJ_LOOP_SEAMS_1": explain_loop, "MJ_DEPS_GRAPH_1": explain_deps,
    "MJ_HANDOFF_1": explain_handoff, "MJ_PROJECT_HEALTH_1": explain_health, "MJ_DIFF_1": explain_diff, "MJ_TRACE_1": explain_trace,
    "MJ_PLUGIN_USAGE_1": explain_plugins, "MJ_PLUGIN_INVENTORY_1": explain_plugins, "MJ_AUDIT_VERIFY_1": explain_audit,
    "MJ_HOST_DETECT_1": explain_hosts, "MJ_PROJECT_SCRAPE_1": explain_scrape,
    "MJ_C4D_SUMMARY_1": explain_c4d_summary, "MJ_C4D_LINT_1": explain_c4d_lint, "MJ_BRIDGE_CHECK_1": explain_bridge,
    "MJ_PREFLIGHT_1": explain_preflight, "MJ_CACHE_INSPECT_1": explain_cache_inspect, "MJ_CACHE_CLEAN_1": explain_cache_clean,
}


def explain(doc):
    """Returns (lines, ok)."""
    if not isinstance(doc, dict):
        return ["This is not a MographJailed receipt."], False
    warnings = []
    command = None
    if "protocol" in doc and "ok" in doc:            # a response envelope
        if not doc["ok"]:
            return explain_error(doc), True
        warnings = doc.get("warnings") or []
        command = doc.get("command")
        doc = doc.get("data") or {}
    fn = EXPLAINERS.get(doc.get("schema"))
    if not fn and command == "system.doctor":
        fn = explain_doctor
    if not fn:
        return ["I do not recognise this file (schema: %s)." % doc.get("schema", "none")], False
    lines = fn(doc)
    if warnings:
        lines += ["", "Heads up:"] + [textwrap.fill(w["message"], width=88, initial_indent="  - ", subsequent_indent="    ") for w in warnings]
    return lines, True


def main(argv):
    if len(argv) == 5 and argv[1] == "--check":
        try:
            docs = [json.load(open(a, encoding="utf-8")) for a in argv[2:]]
        except (OSError, ValueError):
            print("mj: cannot read the check results", file=sys.stderr)
            return 66
        for doc in docs:
            if not doc.get("ok"):
                print("\n".join(explain_error(doc)))
                return 65
        lines, ok = explain_check(*[doc["data"] for doc in docs])
        print("\n".join(lines))
        return 0 if ok else 1
    if len(argv) == 3 and argv[1] == "--timeline":
        print("\n".join(explain_timeline(argv[2])))
        return 0
    if len(argv) != 2:
        print("usage: mj_explain.py <file | ->", file=sys.stderr)
        return 64
    try:
        raw = sys.stdin.read() if argv[1] == "-" else open(argv[1], encoding="utf-8").read()
    except OSError:
        print("mj: cannot read %s" % argv[1], file=sys.stderr)
        return 66
    try:
        doc = json.loads(raw)
    except ValueError:
        print("This is not a receipt: it is not valid JSON.", file=sys.stderr)
        return 65
    lines, ok = explain(doc)
    print("\n".join(lines))
    return 0 if ok else 65


if __name__ == "__main__":
    sys.exit(main(sys.argv))
