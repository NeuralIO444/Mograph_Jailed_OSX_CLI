#!/usr/bin/env python3
"""Persona tests: scripted people use the production build the way they would, and we judge what they saw.

  python3 tests/personas/run_personas.py [--only K,M,D] [--ids K03,N08] [--ledger FILE] [--list]

Each scenario runs in its own scratch HOME with the real dist/mograph-jailed.zsh and the real mj front end (zsh -f).
A scenario returns normally to PASS, or calls self.fail(severity, what_they_saw). It is judged on four questions:
safe (nothing outside the sandbox or in an original project changed), plain (words, not JSON/traceback/codes),
recoverable (a next step is named and works), fast (time budget). See docs/PLAN_PERSONA_TESTS.md.
Stdlib only. Needs a Mac for the media and sandbox-exec scenarios; the rest runs anywhere.
"""
import argparse, hashlib, json, os, re, shutil, signal, subprocess, sys, tempfile, time, unicodedata, zipfile

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
CLI = os.path.join(ROOT, "dist", "mograph-jailed.zsh")
MJSH = os.path.join(ROOT, "scripts", "shell", "mj-cli.zsh")
FIX = os.path.join(ROOT, "tests", "support", "make_tutorial_fixtures.py")
ESC = re.compile(r"\x1b|‮|‭|⁦|⁧|⁨|​|\x07|\x9b")
JSONISH = re.compile(r'^\s*\{"protocol":')
SEV = ["blocker", "high", "medium", "low"]
SCENARIOS = []


def sc(sid, persona, title):
    def deco(fn):
        SCENARIOS.append((sid, persona, title, fn))
        return fn
    return deco


class R:
    def __init__(self, out, err, rc, secs, timed_out=False):
        self.out, self.err, self.rc, self.secs, self.timed_out = out, err, rc, secs, timed_out
        self.text = out + err

    def short(self, n=420):
        t = self.text.strip().replace("\n", " | ")
        return (t[:n] + "...") if len(t) > n else t


class Fail(Exception):
    def __init__(self, sev, msg):
        self.sev, self.msg = sev, msg


class Box:
    """A scratch Mac: HOME, config, store, projects, fixtures. Nothing outside it is touched."""
    def __init__(self, base):
        self.tmp = tempfile.mkdtemp(prefix="mj-persona.")
        self.tmp = os.path.realpath(self.tmp)
        self.home = os.path.join(self.tmp, "home")
        shutil.copytree(base, self.home, symlinks=True)
        old = os.path.realpath(base)
        for d in ("AE_Receipts", os.path.join("AE", "receipts")):          # reports and settings were written for the base folder; point them here
            dd = os.path.join(self.home, d)
            for f in os.listdir(dd):
                fp = os.path.join(dd, f)
                txt = open(fp, encoding="utf-8").read()
                open(fp, "w", encoding="utf-8").write(txt.replace(old, self.home))
        cfgp = os.path.join(self.home, ".config/mograph-jailed/config")
        open(cfgp, "w").write("watch_dir=%s/AE/projects\nreceipts_dir=%s/AE_Receipts\nversions_dir=%s/AE_Versions\n" % (self.home, self.home, self.home))
        self.ae = os.path.join(self.home, "AE")
        self.env = {"HOME": self.home, "PATH": "/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin", "LANG": "en_US.UTF-8", "TERM": "xterm-256color",
                    "MJ_CONFIG": os.path.join(self.home, ".config/mograph-jailed/config"), "MJ_STORE_DIR": os.path.join(self.home, "Library/Application Support/MographJailed"),
                    "MJ_CLI": CLI, "MOGRAPHJAILED_ROOT": ROOT, "MJ_AUDIT_DIR": os.path.join(self.tmp, "noaudit"), "TMPDIR": os.path.join(self.tmp, "tmp") + "/"}
        os.makedirs(os.path.join(self.tmp, "tmp"), exist_ok=True)

    def path(self, *p):
        return os.path.join(self.home, *p)

    def run(self, argv, env=None, stdin=None, timeout=60, cwd=None, tty=False):
        e = dict(self.env); e.update(env or {})
        t0 = time.time()
        p = subprocess.Popen(argv, env=e, stdin=subprocess.PIPE if stdin is not None else subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                             cwd=cwd or self.home, start_new_session=True)
        try:
            out, err = p.communicate(stdin.encode() if isinstance(stdin, str) else stdin, timeout=timeout)
            to = False
        except subprocess.TimeoutExpired:
            os.killpg(p.pid, signal.SIGKILL); out, err = p.communicate(); to = True
        return R(out.decode("utf-8", "replace"), err.decode("utf-8", "replace"), p.returncode, time.time() - t0, to)

    def mj(self, line, **kw):
        """Run a line the way a person types it after `mj` (shell word splitting included)."""
        return self.run(["/bin/zsh", "-f", "-c", 'source "%s"; mj %s' % (MJSH, line)], **kw)

    def op(self, command, timeout=60, env=None, **args):
        req = "MOGRAPHJAILED_REQUEST 1\nrequestId=persona\ncommand=%s\n" % command
        for k, v in args.items():
            import base64
            req += "arg.%s=%s\n" % (k, base64.b64encode(str(v).encode()).decode())
        r = self.run(["/bin/zsh", "-f", CLI, "--request", "-"], stdin=req, timeout=timeout, env=env)
        try:
            r.j = json.loads(r.out.strip().splitlines()[-1]) if r.out.strip() else None
        except ValueError:
            r.j = None
        return r

    def setup(self):
        r = self.mj("setup --yes")
        return r

    def hash_tree(self, *paths):
        h = {}
        for p in paths:
            if os.path.isfile(p):
                h[p] = hashlib.sha256(open(p, "rb").read()).hexdigest()
            for d, _, fs in os.walk(p):
                for f in fs:
                    fp = os.path.join(d, f)
                    try:
                        h[fp] = hashlib.sha256(open(fp, "rb").read()).hexdigest()
                    except OSError:
                        h[fp] = "unreadable"
        return h

    def cleanup(self):
        subprocess.run(["chmod", "-R", "u+rwx", self.tmp], capture_output=True)
        shutil.rmtree(self.tmp, ignore_errors=True)


class T:
    """Assertions with the vocabulary of the four questions."""
    def __init__(self, box):
        self.box = box

    def fail(self, sev, msg):
        raise Fail(sev, msg)

    def plain(self, r, what, sev="medium"):
        if JSONISH.search(r.out) or JSONISH.search(r.err):
            self.fail(sev, "%s: showed a raw JSON envelope instead of words: %s" % (what, r.short(200)))
        if "Traceback" in r.text or "command not found" in r.text and "_mj" in r.text:
            self.fail("high", "%s: internal error text reached the person: %s" % (what, r.short(300)))
        if re.search(r"\b(ENGINE_FAILED|INGEST_FAILED|LINT_FAILED)\b", r.text):
            self.fail("high", "%s: internal error code reached the person: %s" % (what, r.short(200)))
        if not r.text.strip():
            self.fail("medium", "%s: silence (no output at all, rc=%s)" % (what, r.rc))

    def next_step(self, r, what, sev="medium"):
        if not re.search(r"\bmj [a-z]+|Did you mean|Fix:|Try|run |Run ", r.text):
            self.fail(sev, "%s: no next step is named: %s" % (what, r.short(260)))

    def fast(self, r, limit, what):
        if r.timed_out:
            self.fail("high", "%s: HUNG (killed after %ss)" % (what, int(r.secs)))
        if r.secs > limit:
            self.fail("low", "%s: took %.1fs (budget %ss)" % (what, r.secs, limit))

    def no_escapes(self, r, what, sev="medium"):
        m = ESC.search(r.text)
        if m:
            self.fail(sev, "%s: raw control/bidi character %r reached the screen: %s" % (what, m.group(0), repr(r.text[max(0, m.start() - 30):m.start() + 40])))

    def unchanged(self, before, after, what):
        d = [p for p in before if before[p] != after.get(p)] + [p for p in after if p not in before]
        if d:
            self.fail("blocker", "%s: files changed that must not have: %s" % (what, ", ".join(os.path.basename(x) for x in d[:5])))

    def ok(self, cond, sev, msg):
        if not cond:
            self.fail(sev, msg)


# --------------------------------------------------------------------------------------------------- fixtures
def layer(i, name, typ="AVLayer", **kw):
    d = {"index": i, "name": name, "type": typ, "enabled": True, "solo": False, "locked": False, "hasVideo": True, "hasAudio": False, "sourceName": "", "sourcePath": "",
         "sourceId": 0, "sourceKind": "", "label": 1, "adjustment": False, "effects": [], "markers": 0, "numProperties": 3, "numKeyframedProperties": 0, "expressions": []}
    d.update(kw); return d


def comp(cid, name, layers, **kw):
    d = {"id": cid, "name": name, "label": 15, "folder": "", "width": 1920, "height": 1080, "pixelAspect": 1, "frameRate": 24, "duration": 10, "numLayers": len(layers), "layers": layers}
    d.update(kw); return d


def scrape(path, comps, footage=(), fonts=(), **kw):
    d = {"schema": "MJ_PROJECT_SCRAPE_1", "scraperVersion": "1.1", "projectPath": path, "projectName": os.path.basename(path), "scrapedAt": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
         "aeVersion": "26.5.0", "numItems": len(comps) + len(footage), "fonts": list(fonts), "missingFonts": [], "comps": list(comps), "footage": list(footage)}
    d.update(kw); return d


def make_src(box, name="src"):
    """An unpacked release folder: every tracked file plus a SHA256SUMS over them."""
    d = os.path.join(box.tmp, name)
    for f in subprocess.check_output(["git", "-C", ROOT, "ls-files"], text=True).splitlines():
        if f == "SHA256SUMS" or not os.path.isfile(os.path.join(ROOT, f)):
            continue
        os.makedirs(os.path.dirname(os.path.join(d, f)), exist_ok=True)
        shutil.copy2(os.path.join(ROOT, f), os.path.join(d, f))
    write_sums(d)
    return d


def write_sums(d):
    lines = []
    for dp, _, fs in os.walk(d):
        for f in fs:
            fp = os.path.join(dp, f)
            rel = os.path.relpath(fp, d)
            if rel in ("SHA256SUMS",) or os.path.islink(fp) or not os.path.isfile(fp):
                continue
            try:
                lines.append("%s  %s\n" % (hashlib.sha256(open(fp, "rb").read()).hexdigest(), rel))
            except OSError:
                pass
    open(os.path.join(d, "SHA256SUMS"), "w").write("".join(sorted(lines, key=lambda x: x.split("  ", 1)[1])))


def put(path, data=b"x"):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    mode = "wb" if isinstance(data, bytes) else "w"
    with open(path, mode) as f:
        f.write(data)
    return path


def report(box, name, doc, when=None):
    p = os.path.join(box.home, "AE_Receipts", "%s.%s.scrape.json" % (name, when or time.strftime("%Y%m%dT%H%M%SZ", time.gmtime())))
    put(p, json.dumps(doc))
    return p


# --------------------------------------------------------------------------------------------------- P1 Kiki
@sc("K02", "Kiki", "installed, skipped setup, runs mj check")
def k02(t):
    b = t.box
    shutil.rmtree(b.path("AE_Receipts"), ignore_errors=True); shutil.rmtree(b.path("AE_Versions"), ignore_errors=True)
    os.remove(b.env["MJ_CONFIG"]) if os.path.exists(b.env["MJ_CONFIG"]) else None
    for line in ('check "My Project"', "snapshot Spring", "versions", "lint last", "timeline Spring"):
        r = b.mj(line)
        t.plain(r, "mj " + line)
        if "mj setup" not in r.text:
            t.fail("high", "mj %s before setup does not point at `mj setup`: %s" % (line, r.short(240)))


@sc("K03", "Kiki", "pastes commands with curly quotes and an em dash")
def k03(t):
    b = t.box; b.setup()
    r = b.mj("snapshot “Spring Promo”")
    t.plain(r, "curly-quoted snapshot")
    if "Saved a verified copy" not in r.text and "Nothing to save" not in r.text:
        t.fail("medium", "pasted curly quotes (“Spring Promo”) are not understood and the message does not say why: %s" % r.short(260))
    r = b.mj("conform Spring —apply")
    t.plain(r, "em-dash conform")
    if "—apply" in r.text and "--apply" not in r.text:
        t.fail("low", "an em dash typed for -- (— apply) is silently treated as part of a name: %s" % r.short(240))


@sc("K04", "Kiki", "capital letters, abbreviations")
def k04(t):
    b = t.box; b.setup()
    for line, want in (("Check spring", None), ("CHECK spring", None), ("check SPRING", "Spring Promo"), ("snapshot spr", "Spring")):
        r = b.mj(line)
        t.plain(r, "mj " + line)
        if want and want not in r.text and r.rc != 0:
            t.fail("medium", "mj %s: %s" % (line, r.short(200)))
        if line.startswith(("Check", "CHECK")) and "not a command" in r.text and "check" not in r.text.lower().split("did you mean")[-1]:
            t.fail("low", "a capitalised verb (%s) is rejected without the obvious suggestion: %s" % (line, r.short(180)))


@sc("K05", "Kiki", "tries verbs that sound right")
def k05(t):
    b = t.box; b.setup()
    bad = []
    for line in ("help me", "--help", "-h", "version", "--version", "update", "install", "uninstall", "fix", "how", "info", "list", "projects", "about", "open", "run", "start", "undo", "restore"):
        r = b.mj(line)
        useful = r.rc == 0 or re.search(r"Did you mean|mj help|mj [a-z]+", r.text)
        if JSONISH.search(r.out) or not r.text.strip() or not useful or "Traceback" in r.text:
            bad.append("%s -> %s" % (line, r.short(110)))
    if bad:
        t.fail("low", "%d natural verbs get no useful answer: %s" % (len(bad), "; ".join(bad[:6])))


@sc("K06", "Kiki", "asks which version she has")
def k06(t):
    b = t.box; b.setup()
    for line in ("version", "--version", "-V", "-v"):
        r = b.mj(line)
        if r.rc != 0 or not re.search(r"\d+\.\d+\.\d+", r.text):
            t.fail("low", "`mj %s` does not print a version (support will ask for it): %s" % (line, r.short(140)))


@sc("K07", "Kiki", "dumb terminal and a narrow window")
def k07(t):
    b = t.box; b.setup()
    for line in ("help", "doctor", "", "check spring"):
        r = b.mj(line, env={"TERM": "dumb", "COLUMNS": "38", "NO_COLOR": "1"})
        t.plain(r, "mj %s on a dumb terminal" % line)
        t.no_escapes(r, "mj %s on a dumb terminal" % line)
        if "\x1b[" in r.out:
            t.fail("medium", "mj %s sends colour codes to a dumb terminal" % line)


@sc("K09", "Kiki", "drags the install folder to the Trash, opens a new Terminal")
def k09(t):
    b = t.box
    rc = b.path(".zshrc")
    put(rc, '# >>> MographJailed (added by the installer; the uninstaller removes exactly this block) >>>\nexport MOGRAPHJAILED_ROOT="%s/Documents/GoneFolder"\n'
        '[ -r "$MOGRAPHJAILED_ROOT/scripts/shell/mj-init.zsh" ] && source "$MOGRAPHJAILED_ROOT/scripts/shell/mj-init.zsh"\n# <<< MographJailed <<<\n' % b.home)
    r = b.run(["/bin/zsh", "-i", "-c", "echo opened"], env={"ZDOTDIR": b.home})
    if r.err.strip():
        t.fail("medium", "every new Terminal window prints an error once the folder is gone: %s" % r.err.strip()[:200])


# --------------------------------------------------------------------------------------------------- P2 Marcus
@sc("M01", "Marcus", "empty (cloud placeholder) project file")
def m01(t):
    b = t.box; b.setup()
    p = put(b.path("AE/projects/Cloud/Cloud.aep"), b"")
    r = b.mj('snapshot "Cloud"')
    t.plain(r, "snapshot of a zero-byte project")
    if "Saved a verified copy" in r.text:
        t.fail("high", "a 0-byte project (typical of a not-yet-downloaded Dropbox/iCloud file) was 'verified': %s" % r.short(200))


@sc("M04", "Marcus", "awkward names, typed composed (NFC) while disk has decomposed (NFD)")
def m04(t):
    b = t.box; b.setup()
    nfd = unicodedata.normalize("NFD", "Café Promo")
    nfc = unicodedata.normalize("NFC", "Café Promo")
    put(b.path("AE/projects/x/%s.aep" % nfd), b"cafe-promo")
    r = b.mj('snapshot "%s"' % nfc)
    t.plain(r, "snapshot with an accented name")
    if "no project found" in r.text:
        t.fail("high", "a name typed with é (composed) cannot find a file saved with e + accent (decomposed), though they look identical: %s" % r.short(160))
    names = ["it's \"quoted\".aep", "100% done & more.aep", "-dash first.aep", "日本語 プロジェクト.aep", "🎬 promo ✨.aep", "x" * 200 + ".aep"]
    for i, n in enumerate(names):
        put(b.path("AE/projects/odd%d/%s" % (i, n)), b"odd-%d" % i)
        r = b.mj('snapshot "%s"' % n.replace('"', '\\"').replace("$", "\\$").replace("`", "\\`")[:300])
        t.plain(r, "snapshot of " + n[:20])
        if "Saved a verified copy" not in r.text and "Nothing to save" not in r.text:
            t.fail("medium", "name %r is not handled: %s" % (n[:30], r.short(180)))


@sc("M11", "Marcus", "a real studio folder tree: Client/Job/Year/Project/Projects/file.aep")
def m11(t):
    b = t.box; b.setup()
    deep = b.path("AE/projects/Acme Corp/2026_Q3_Spring_Campaign/03_Motion/AE/Projects/Spot_30s_v07.aep")
    put(deep, b"deep project")
    r = b.mj("snapshot Spot_30s_v07")
    t.plain(r, "snapshot of a project 7 folders deep")
    if "no project found" in r.text:
        t.fail("high", "a project 7 folders below the projects folder is not found by name (the search stops at 3 levels), which is how most client trees look: %s" % r.short(170))


@sc("M05", "Marcus", "two clients each have a Main.aep")
def m05(t):
    b = t.box; b.setup()
    put(b.path("AE/projects/ClientA/Main.aep"), b"a"); put(b.path("AE/projects/ClientB/Main.aep"), b"b")
    r = b.mj("snapshot Main")
    t.plain(r, "ambiguous snapshot")
    if "more than one" not in r.text:
        t.fail("high", "two projects named Main: it did not ask which: %s" % r.short(200))
    if os.listdir(b.path("AE_Versions")):
        t.fail("blocker", "it saved a version of one of two ambiguous projects without asking")


@sc("M06", "Marcus", "project moved after scraping, then conform")
def m06(t):
    b = t.box; b.setup()
    src = b.path("AE/projects/Spring Promo/Spring Promo.aep"); dst = b.path("AE/projects/Archive/Spring Promo.aep")
    os.makedirs(os.path.dirname(dst)); shutil.move(src, dst)
    r = b.mj('conform "Spring Promo"')
    t.plain(r, "conform after a move")
    r2 = b.mj('extract "Archive/Spring Promo" Main')
    t.plain(r2, "extract after a move")


@sc("M07", "Marcus", "kill -9 in the middle of a snapshot, then carry on")
def m07(t):
    b = t.box; b.setup()
    big = b.path("AE/projects/Big/Big.aep"); os.makedirs(os.path.dirname(big))
    with open(big, "wb") as f:
        f.write(os.urandom(1 << 20) * 300)
    env = dict(b.env); t0 = time.time()
    p = subprocess.Popen(["/bin/zsh", "-f", "-c", 'source "%s"; mj snapshot Big' % MJSH], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
    time.sleep(0.6)
    try:
        os.killpg(p.pid, signal.SIGKILL)
    except OSError:
        pass
    p.wait()
    leftovers = [f for f in os.listdir(b.path("AE_Versions"))]
    r = b.mj("snapshot Big", timeout=120)
    t.plain(r, "snapshot after a kill")
    if "Saved a verified copy" not in r.text and "Nothing to save" not in r.text:
        t.fail("high", "after a killed snapshot the next one does not work: %s (leftovers: %s)" % (r.short(160), leftovers[:3]))
    stray = [f for f in os.listdir(b.path("AE_Versions")) if f.startswith(".") or ".partial" in f or f.endswith(".lock")]
    if stray:
        t.fail("low", "a killed snapshot leaves clutter behind forever: %s" % stray[:3])
    v = [f for f in os.listdir(b.path("AE_Versions")) if f.endswith(".aep")]
    if v and hashlib.sha256(open(os.path.join(b.path("AE_Versions"), v[0]), "rb").read()).hexdigest() != hashlib.sha256(open(big, "rb").read()).hexdigest():
        t.fail("blocker", "a version file does not match its source after a kill")


@sc("M08", "Marcus", "stale lock from a dead process")
def m08(t):
    b = t.box; b.setup()
    r = b.mj('snapshot "Spring Promo"')
    lock = b.path("AE_Versions/.Spring Promo.latest.json.lock"); os.makedirs(lock); open(os.path.join(lock, "pid"), "w").write("99999999")
    put(b.path("AE/projects/Spring Promo/Spring Promo.aep"), b"changed after the lock was left")
    r = b.mj('snapshot "Spring Promo"', timeout=90)
    t.plain(r, "snapshot with a stale lock")
    t.fast(r, 20, "snapshot with a stale lock")
    if "Saved a verified copy" not in r.text:
        t.fail("high", "a stale lock from a dead process blocks snapshots: %s" % r.short(200))
    # a lock whose owner is alive but wedged: bounded wait with a clear message
    os.makedirs(lock + "x", exist_ok=True)


@sc("M09", "Marcus", "clock and time zone games")
def m09(t):
    b = t.box; b.setup()
    for tz in ("Pacific/Kiritimati", "Etc/GMT+12", "UTC"):
        r = b.mj("timeline Spring", env={"TZ": tz})
        t.plain(r, "timeline in " + tz)
        if "Spring Promo" not in r.text:
            t.fail("medium", "timeline broken in TZ=%s: %s" % (tz, r.short(160)))
    when = "29990101T000000Z"
    d = json.load(open(b.path("AE_Receipts/spring.20261001T163000Z.scrape.json"))); d["scrapedAt"] = "2999-01-01T00:00:00Z"
    report(b, "spring", d, when)
    r = b.mj("timeline Spring")
    t.plain(r, "timeline with a report from the year 2999")
    r = b.mj("health Spring --record")
    t.plain(r, "health with a future date")


# --------------------------------------------------------------------------------------------------- P3 Dana
@sc("D01", "Dana", "'ready' must mean ready")
def d01(t):
    b = t.box; b.setup()
    ok_proj = b.path("AE/projects/Clean/Clean.aep"); put(ok_proj, b"clean")
    media = put(b.path("AE/media/real.mov"), b"real")
    d = scrape(ok_proj, [comp(1, "Main", [layer(1, "Title", "TextLayer", font="Helvetica")])], footage=[{"id": 9, "name": "real.mov", "kind": "footage", "path": media, "missing": False, "hasVideo": True, "hasAudio": False, "label": 1, "folder": ""}],
               fonts=["Helvetica"])
    report(b, "clean", d)
    r = b.mj("check Clean"); t.plain(r, "check of a clean project")
    if "ready" not in r.text.lower():
        t.fail("low", "a clean project is not called ready: %s" % r.short(200))
    for what, mutate in (("a missing font", lambda x: x["comps"][0]["layers"][0].update(font="TotallyNotInstalled-Bold") or x["fonts"].append("TotallyNotInstalled-Bold")),
                         ("footage deleted since the report", lambda x: os.remove(media)),
                         ("an expression error", lambda x: x["comps"][0]["layers"][0].update(expressions=[{"propertyPath": "Transform/Position", "expression": 'thisComp.layer("Ghost").transform.position'}])),
                         ("proxy-only footage", lambda x: x["footage"][0].update(missing=True))):
        d2 = json.loads(json.dumps(d)); put(media, b"real"); mutate(d2)
        shutil.rmtree(b.path("AE_Receipts"), ignore_errors=True); os.makedirs(b.path("AE_Receipts"))
        report(b, "clean", d2)
        r = b.mj("check Clean"); t.plain(r, "check with " + what)
        if re.search(r"Clean\.aep: ready\.", r.text) or r.rc == 0:
            t.fail("blocker", "FALSE REASSURANCE: mj check says ready (rc=%s) with %s: %s" % (r.rc, what, r.short(220)))


@sc("D08", "Dana", "the verdict and the bullet points must tell the same story")
def d08(t):
    b = t.box; b.setup()
    p = b.path("AE/projects/Tidy/Tidy.aep"); put(p, b"tidy")
    d = scrape(p, [comp(1, "Main", [layer(1, "Title", "TextLayer")])]); report(b, "tidy", d)
    r = b.mj("check Tidy"); t.plain(r, "check of a tidy project with no saved versions")
    if re.search(r"Tidy\.aep: ready\.", r.text) and "!!" in r.text:
        t.fail("medium", "the headline says ready but a line is flagged !! (%s)" % re.sub(r"\s+", " ", r.text)[:240])
    r2 = b.mj("health Tidy")
    if re.search(r"needs a look", r2.text) and re.search(r"Tidy\.aep: ready\.", r.text) and "mj snapshot" not in r.text:
        t.fail("medium", "mj check says ready while mj health says needs a look, and does not say why or what to do: %s | %s" % (r.short(160), r2.short(120)))


@sc("D02", "Dana", "project saved again after the report was made")
def d02(t):
    b = t.box; b.setup()
    p = b.path("AE/projects/Fresh/Fresh.aep"); put(p, b"v1")
    d = scrape(p, [comp(1, "Main", [layer(1, "Title", "TextLayer")])]); d["scrapedAt"] = "2026-10-01T00:00:00Z"
    report(b, "fresh", d)
    time.sleep(1.1); put(p, b"v2 - edited after the report")
    r = b.mj("check Fresh"); t.plain(r, "check of a stale report")
    if not re.search(r"older|stale|saved since|changed since|out of date|run the .* again|scrape", r.text, re.I):
        t.fail("high", "report is older than the project file, yet mj check says nothing about it (it may be judging yesterday's project): %s" % r.short(200))


def ffmpeg_ok():
    return shutil.which("ffmpeg") is not None and os.path.exists("/usr/bin/avmediainfo")


def make_media(b, name, args, ext="mov", codec=None):
    out = b.path("media", name + "." + ext)
    os.makedirs(os.path.dirname(out), exist_ok=True)
    cmd = ["ffmpeg", "-loglevel", "error", "-y"] + args + [out]
    subprocess.run(cmd, capture_output=True, timeout=120)
    return out


@sc("D03", "Dana", "one master, many deliveries, against four specs")
def d03(t):
    if not ffmpeg_ok():
        raise Fail("skip", "needs ffmpeg and avmediainfo")
    b = t.box; b.setup()
    v = ["-f", "lavfi", "-i", "testsrc2=size=1920x1080:rate=24000/1001:duration=3"]
    a = lambda f: ["-f", "lavfi", "-i", f]
    sine = "sine=frequency=1000:sample_rate=48000:duration=3"
    cases = {
        "good_prores": (["-f", "lavfi", "-i", "testsrc2=size=1920x1080:rate=24000/1001:duration=3"] + a(sine) + ["-af", "volume=-2.9dB", "-vf", "setparams=color_primaries=bt709:color_trc=bt709:colorspace=bt709", "-c:v", "prores_ks", "-profile:v", "3", "-movflags", "+write_colr", "-c:a", "pcm_s24le", "-ac", "2"], "mov", "broadcast-us"),
        "h264_for_broadcast": (v + a(sine) + ["-c:v", "libx264", "-pix_fmt", "yuv420p", "-c:a", "aac"], "mp4", "broadcast-us"),
        "vertical_ok": (["-f", "lavfi", "-i", "testsrc2=size=1080x1920:rate=30:duration=3"] + a(sine) + ["-c:v", "libx264", "-pix_fmt", "yuv420p", "-c:a", "aac", "-af", "volume=-12dB"], "mp4", "social-vertical"),
        "silent": (v + a("anullsrc=r=48000:cl=stereo") + ["-t", "3", "-c:v", "prores_ks", "-c:a", "pcm_s24le"], "mov", "broadcast-us"),
        "one_channel_dead": (v + a("sine=frequency=1000:sample_rate=48000:duration=3") + ["-af", "pan=stereo|c0=c0|c1=0*c0", "-c:v", "prores_ks", "-c:a", "pcm_s24le"], "mov", "broadcast-us"),
        "out_of_phase": (v + a("sine=frequency=500:sample_rate=48000:duration=3") + ["-af", "pan=stereo|c0=c0|c1=-1*c0", "-c:v", "prores_ks", "-c:a", "pcm_s24le"], "mov", "broadcast-us"),
        "clipping": (v + a(sine) + ["-af", "volume=+20dB", "-c:v", "prores_ks", "-c:a", "pcm_f32le"], "mov", "broadcast-us"),
        "one_second": (["-f", "lavfi", "-i", "testsrc2=size=1920x1080:rate=24000/1001:duration=1"] + a("sine=frequency=1000:sample_rate=48000:duration=1") + ["-c:v", "prores_ks", "-c:a", "pcm_s24le"], "mov", "broadcast-us"),
        "mono_44k": (v + a("sine=frequency=1000:sample_rate=44100:duration=3") + ["-ac", "1", "-c:v", "prores_ks", "-c:a", "pcm_s16le"], "mov", "broadcast-us"),
        "five_one": (v + a("anoisesrc=color=white:amplitude=0.1:duration=3:sample_rate=48000") + ["-af", "aformat=channel_layouts=5.1", "-c:v", "prores_ks", "-c:a", "pcm_s24le"], "mov", "broadcast-us"),
    }
    findings = []
    for name, (args, ext, spec) in cases.items():
        p = make_media(b, name, args, ext)
        if not os.path.exists(p):
            continue
        r = b.mj('qc "%s" %s' % (p, spec), timeout=120)
        t.plain(r, "qc of " + name)
        passed = "passes for" in r.text
        if name == "good_prores" and r.rc != 0:
            findings.append("a good ProRes master (-24 sine) did not pass: %s" % r.short(200))
        if name == "h264_for_broadcast" and passed:
            findings.append("H.264 .mp4 passed a ProRes .mov broadcast spec")
        if name in ("silent",) and passed:
            findings.append("a SILENT file passed the broadcast spec")
        if name == "clipping" and passed:
            findings.append("a file clipping at over 0 dBFS passed")
        if name == "one_channel_dead" and passed:
            findings.append("one dead audio channel passed (loudness reads on the other channel only)")
        if name == "out_of_phase" and passed:
            findings.append("out-of-phase stereo (silent in mono) passed")
        if name == "mono_44k" and passed:
            findings.append("mono 44.1 kHz passed a stereo 48 kHz spec")
        if name == "one_second" and r.rc == 0 and "not measured" not in r.text and "too short" not in r.text:
            findings.append("a 1 s clip: loudness reading is reported without the short-clip caveat")
    if findings:
        t.fail("high", "; ".join(findings))


@sc("D05", "Dana", "files that lie or are broken")
def d05(t):
    if not ffmpeg_ok():
        raise Fail("skip", "needs ffmpeg and avmediainfo")
    b = t.box; b.setup()
    good = make_media(b, "g", ["-f", "lavfi", "-i", "testsrc2=size=1920x1080:rate=24:duration=3", "-f", "lavfi", "-i", "sine=frequency=1000:sample_rate=48000:duration=3", "-c:v", "prores_ks", "-c:a", "pcm_s24le"], "mov")
    data = open(good, "rb").read()
    put(b.path("media/truncated.mov"), data[: len(data) // 3])
    put(b.path("media/zero.mov"), b"")
    put(b.path("media/text.mov"), "this is not a movie " * 100)
    shutil.copy(good, b.path("media/prores_named_mp4.mp4"))
    os.symlink("/etc/hosts", b.path("media/link.mov"))
    os.mkfifo(b.path("media/fifo.mov"))
    bad = []
    for n in ("truncated.mov", "zero.mov", "text.mov", "prores_named_mp4.mp4", "link.mov", "fifo.mov"):
        r = b.mj('qc "%s" broadcast-us' % b.path("media", n), timeout=60)
        if r.timed_out:
            bad.append("%s HUNG" % n); continue
        if JSONISH.search(r.out) or "Traceback" in r.text or not r.text.strip():
            bad.append("%s -> %s" % (n, r.short(100)))
        if n in ("zero.mov", "text.mov", "link.mov", "fifo.mov") and "passes for" in r.text:
            bad.append("%s PASSED" % n)
        if n == "prores_named_mp4.mp4" and "passes for" in r.text:
            bad.append("a ProRes file named .mp4 passed a .mov spec (container judged by file name only)")
    if bad:
        t.fail("high", "; ".join(bad))


@sc("D06", "Dana", "a client spec typed in TextEdit")
def d06(t):
    b = t.box; b.setup()
    media = None
    if ffmpeg_ok():
        media = make_media(b, "m", ["-f", "lavfi", "-i", "testsrc2=size=1920x1080:rate=24:duration=2", "-f", "lavfi", "-i", "sine=f=1000:sample_rate=48000:duration=2", "-c:v", "prores_ks", "-c:a", "pcm_s24le"], "mov")
    else:
        media = put(b.path("media/m.mov"), b"x")
    cases = {"rich text": '{\\rtf1\\ansi codec = prores}', "colon": "codec: prores\nloudness: -24\n", "smart quotes": "name = “Client X”\ncodec = prores\n",
             "bom+crlf": "﻿codec = prores\r\naudio = required\r\n", "tabs": "codec\t=\tprores\n", "equals in value": "name = a=b\ncodec = prores\n", "units": "loudness = -24 LUFS\n", "empty": "", "only comments": "# nothing\n"}
    bad = []
    for name, body in cases.items():
        sp = put(b.path("spec_%s.mjspec" % name.replace(" ", "_").replace("+", "_")), body.encode("utf-8"))
        r = b.mj('qc "%s" "%s"' % (media, sp), timeout=60)
        if r.timed_out or JSONISH.search(r.out) or "Traceback" in r.text:
            bad.append("%s: %s" % (name, r.short(100))); continue
        if name in ("colon", "rich text", "units", "empty", "only comments", "smart quotes") and r.rc == 0 and "passes" in r.text and name != "smart quotes":
            bad.append("%s: an unparseable spec 'passes'" % name)
        if name in ("colon", "rich text", "units") and not re.search(r"line \d|which line|key = value", r.text):
            bad.append("%s: error does not say what to change (%s)" % (name, r.short(90)))
    if bad:
        t.fail("medium", "; ".join(bad))


@sc("D07", "Dana", "re-runs everything twenty times")
def d07(t):
    b = t.box; b.setup()
    sizes = []
    for i in range(20):
        r = b.mj("check Spring"); b.mj("health Spring --record"); b.mj("timeline Spring")
        if i in (0, 19):
            sizes.append(sum(os.path.getsize(os.path.join(d, f)) for d, _, fs in os.walk(b.home) for f in fs))
    files = sum(len(fs) for _, _, fs in os.walk(b.home))
    if sizes[1] - sizes[0] > 2_000_000:
        t.fail("low", "20 repeat runs grew disk use by %d KB" % ((sizes[1] - sizes[0]) // 1024))
    r = b.mj("health Spring --record")
    if "Trend over" in r.text and re.search(r"Trend over (\d+)", r.text) and int(re.search(r"Trend over (\d+)", r.text).group(1)) > 3:
        t.fail("medium", "recording the same unchanged report 20 times makes a 'trend' of %s points (identical reports should count once): %s" % (re.search(r"Trend over (\d+)", r.text).group(1), r.short(160)))


# --------------------------------------------------------------------------------------------------- P4 Sol
def conform_plan(b, doc, spec=None):
    p = report(b, "conf", doc, "20261002T100000Z")
    args = 'conform "%s"' % os.path.basename(doc["projectPath"])
    if spec:
        args += ' --spec "%s"' % spec
    return b.mj(args)


@sc("S01", "Sol", "expressions in the wild")
def s01(t):
    b = t.box; b.setup()
    p = b.path("AE/projects/Wild/Wild.aep"); put(p, b"wild")
    E = lambda path, e: {"propertyPath": path, "expression": e}
    exprs = [
        'thisComp.layer(index+1).transform.position',
        'var c = comp("CTRL"); c.layer("Color").transform.opacity',
        'comp("CTRL")\n  .layer("Color").transform.scale',
        'n = "Col" + "or"; thisComp.layer(n).transform.rotation',
        'thisComp.layer("Color").effect("Slider")("Slider")',
        "// thisComp.layer(\"Color\") is an old name\nvalue",
        'eval("thisComp.layer(\\"Color\\")")',
        'thisComp.layer(\'Color\').transform.position + [`x`.length, 0]',
        'thisLayer.name == "Color" ? 1 : 0',
        'comp(thisComp.name).layer("Color").position',
        'footage("clip.mov").sourceText',
        'thisComp.layer("Color").transform.opacity; thisComp.layer("Color 2").transform.opacity',
    ]
    layers = [layer(1, "Color", "NullLayer"), layer(2, "Color 2", "TextLayer", expressions=[E("Transform/Position", e) for e in exprs])]
    d = scrape(p, [comp(1, "Main", layers), comp(2, "CTRL", [layer(1, "Color", "NullLayer")])])
    r = conform_plan(b, d)
    t.plain(r, "conform plan of tricky expressions")
    out = r.text
    if "Traceback" in out:
        t.fail("high", out[:200])
    plan = b.op("project.conform", input=b.path("AE_Receipts/conf.20261002T100000Z.scrape.json"))
    if not plan.j or not plan.j.get("ok"):
        t.fail("high", "conform plan failed: %s" % plan.short())
    changed = {e["from"]: e["to"] for e in plan.j["data"]["plan"]["expressions"]}
    bad = []
    for src, want_changed in ((exprs[2], True), (exprs[1], False), (exprs[3], False), (exprs[6], False), (exprs[5], False), (exprs[8], False)):
        if (src in changed) != want_changed:
            bad.append(("rewritten" if src in changed else "left alone") + ": " + src[:50].replace("\n", " "))
    if plan.j["data"]["plan"]["dynamicReferences"] == 0 and (exprs[3] or exprs[6]):
        bad.append("computed/eval'd references are not flagged (dynamicReferences=0)")
    if "//" in exprs[5] and exprs[5] in changed and "// thisComp" in changed[exprs[5]] and "TXT_" in changed[exprs[5]]:
        bad.append("a COMMENT was rewritten")
    if bad:
        t.fail("high", "; ".join(bad))


@sc("S03", "Sol", "conform twice, then with another spec")
def s03(t):
    b = t.box; b.setup()
    p = b.path("AE/projects/Idem/Idem.aep"); put(p, b"idem")
    layers = [layer(1, "Title", "TextLayer"), layer(2, "Logo Mark", "AVLayer"), layer(3, "bg", "NullLayer")]
    d = scrape(p, [comp(1, "Main Comp", layers + [layer(4, "Lower Third", "AVLayer", sourceId=2, sourceKind="comp")]), comp(2, "Lower Third", [layer(1, "Name", "TextLayer")])])
    report(b, "idem", d, "20261002T100000Z")
    r1 = b.op("project.conform", input=b.path("AE_Receipts/idem.20261002T100000Z.scrape.json"))
    plan = r1.j["data"]["plan"]
    ren = {(x["compId"], x["index"]): x["to"] for x in plan["layerRenames"]}; cren = {x["id"]: x["to"] for x in plan["itemRenames"]}
    d2 = json.loads(json.dumps(d))
    for c in d2["comps"]:
        c["name"] = cren.get(c["id"], c["name"])
        for l in c["layers"]:
            l["name"] = ren.get((c["id"], l["index"]), l["name"])
    report(b, "idem", d2, "20261002T110000Z")
    r2 = b.op("project.conform", input=b.path("AE_Receipts/idem.20261002T110000Z.scrape.json"))
    p2 = r2.j["data"]
    if p2["counts"]["layerRenames"] or p2["counts"]["itemRenames"]:
        t.fail("high", "conform is not idempotent: a second run still wants %s renames: %s" % (p2["counts"]["layerRenames"] + p2["counts"]["itemRenames"], json.dumps(p2["plan"]["layerRenames"][:3] + p2["plan"]["itemRenames"][:3])[:200]))


@sc("S04", "Sol", "name collisions and look-alikes")
def s04(t):
    b = t.box; b.setup()
    p = b.path("AE/projects/Col/Col.aep"); put(p, b"col")
    names = ["A", "A_2", "TXT_A", "Text A", "a", "A ", " A", "A ", unicodedata.normalize("NFD", "É"), unicodedata.normalize("NFC", "É"), "🎬", "🎬 ", "TXT_", ""]
    layers = [layer(i + 1, n, "TextLayer") for i, n in enumerate(names)]
    d = scrape(p, [comp(1, "Main", layers), comp(2, "main", [layer(1, "x")]), comp(3, "Main ", [layer(1, "x")])])
    report(b, "col", d, "20261002T100000Z")
    r = b.op("project.conform", input=b.path("AE_Receipts/col.20261002T100000Z.scrape.json"))
    if not r.j or not r.j.get("ok"):
        t.fail("high", "conform failed on look-alike names: %s" % r.short())
    plan = r.j["data"]["plan"]
    for kind, group in (("layer", [(x["compId"], x["to"]) for x in plan["layerRenames"]]), ("comp", [x["to"] for x in plan["itemRenames"]])):
        if len(set(group)) != len(group):
            t.fail("blocker", "conform plans two %ss with the same new name: %s" % (kind, group[:5]))
    after = [x["to"] for x in plan["layerRenames"] if x["compId"] == 1] + [n for i, n in enumerate(names) if not any(x["compId"] == 1 and x["index"] == i + 1 for x in plan["layerRenames"])]
    if len(set(after)) != len(after):
        t.fail("blocker", "after conform, two layers in one comp would share a name: duplicates %s" % sorted({x for x in after if after.count(x) > 1})[:5])


@sc("S05", "Sol", "hostile house specs")
def s05(t):
    b = t.box; b.setup()
    p = b.path("AE/projects/Sp/Sp.aep"); put(p, b"sp")
    d = scrape(p, [comp(1, "Main", [layer(1, "Title", "TextLayer")])]); report(b, "sp", d, "20261002T100000Z")
    cases = {"bom": ("﻿name = House\nlayerPrefix.text = T_\n", "ok"), "crlf": ("name = House\r\nlayerPrefix.text = T_\r\n", "ok"), "tabs": ("layerPrefix.text\t=\tT_\n", "ok"),
             "dup keys": ("layerPrefix.text = A_\nlayerPrefix.text = B_\n", "any"), "space prefix": ("layerPrefix.text = my text \n", "any"), "slash prefix": ("layerPrefix.text = a/b_\n", "any"),
             "percent": ("layerPrefix.text = %s%d_\n", "any"), "long": ("layerPrefix.text = " + "x" * 64 + "\n", "any"), "too long": ("layerPrefix.text = " + "x" * 65 + "\n", "err"),
             "label 16": ("label.text = 16\n", "ok"), "label 17": ("label.text = 17\n", "err"), "unicode prefix": ("layerPrefix.text = 🎬_\n", "any"), "dollar": ("layerPrefix.text = $(x)_\n", "any"),
             "no equals": ("layerPrefix.text T_\n", "err")}
    bad = []
    for n, (body, want) in cases.items():
        sp = put(b.path("spec_%s.mjstudio" % n.replace(" ", "_")), body.encode("utf-8"))
        r = b.mj('conform Sp --spec "%s"' % sp)
        if r.timed_out or "Traceback" in r.text or JSONISH.search(r.out):
            bad.append("%s: %s" % (n, r.short(100))); continue
        okrun = "against" in r.text or "Nothing to change" in r.text
        if want == "ok" and not okrun:
            bad.append("%s should be accepted: %s" % (n, r.short(100)))
        if want == "err" and okrun:
            bad.append("%s should be refused but was accepted" % n)
        if want == "err" and not okrun and not re.search(r"line \d", r.text):
            bad.append("%s: refusal does not name the line (%s)" % (n, r.short(80)))
    if bad:
        t.fail("medium", "; ".join(bad))


@sc("S10", "Sol", "a big project: 400 comps, 3,000 layers")
def s10(t):
    b = t.box; b.setup()
    p = b.path("AE/projects/Huge/Huge.aep"); put(p, b"huge")
    comps = []
    for c in range(400):
        ls = [layer(i + 1, "Layer %d" % i, "TextLayer", expressions=[{"propertyPath": "Transform/Position", "expression": 'thisComp.layer("Layer %d").transform.position' % ((i + 1) % 8)}]) for i in range(8)]
        comps.append(comp(c + 1, "Comp %d" % c, ls))
    d = scrape(p, comps)
    report(b, "huge", d, "20261002T100000Z")
    for line in ('check Huge', 'conform Huge', 'timeline Huge', 'lint Huge'):
        r = b.mj(line, timeout=90)
        t.plain(r, "mj " + line)
        t.fast(r, 10, "mj %s on 3,200 layers" % line)


# --------------------------------------------------------------------------------------------------- P5 Ines
@sc("I02", "Ines", "textures on a share that never answers, and 20,000 textures")
def i02(t):
    b = t.box; b.setup()
    tex = [{"path": "/Volumes/NAS-Projects/tex/t%d.png" % i, "resolved": "/Volumes/NAS-Projects/tex/t%d.png" % i, "missing": i % 3 == 0, "absolute": True} for i in range(20000)]
    c4d = {"schema": "MJ_C4D_SCRAPE_1", "scraperVersion": "1.0", "scenePath": b.path("AE/projects/Big/Big.c4d"), "sceneName": "Big.c4d", "scrapedAt": "2026-10-02T10:00:00Z", "c4dVersion": "2026.3",
           "fps": 24, "startFrame": 0, "endFrame": 99, "width": 1920, "height": 1080, "renderer": "redshift", "outputPath": "", "textures": tex, "materials": [{"name": "m%d" % i, "type": "redshift"} for i in range(500)]}
    put(b.path("AE_Receipts/big.20261002T100000Z.c4dscrape.json"), json.dumps(c4d))
    for line in ("scene last", "scene last --summary", "bridge last last"):
        r = b.mj(line, timeout=90)
        t.plain(r, "mj " + line)
        t.fast(r, 8, "mj %s with 20,000 textures" % line)
        if "Traceback" in r.text:
            t.fail("high", r.short(200))


@sc("I06", "Ines", ".aep and .c4d with the same name in one folder")
def i06(t):
    b = t.box; b.setup()
    put(b.path("AE/projects/Logo/Logo.aep"), b"ae-logo"); put(b.path("AE/projects/Logo/Logo.c4d"), b"c4d-logo")
    r = b.mj("snapshot Logo")
    t.plain(r, "snapshot of Logo (two kinds)")
    if "more than one" not in r.text and "Saved" in r.text:
        t.fail("medium", "`mj snapshot Logo` silently chose one of Logo.aep / Logo.c4d: %s" % r.short(160))
    b.mj("snapshot Logo.aep"); b.mj("snapshot Logo.c4d")
    v = os.listdir(b.path("AE_Versions"))
    latest = sorted(f for f in v if f.endswith("latest.json"))
    if len(latest) != 2:
        t.fail("high", "aep and c4d of the same name share a latest pointer: %s" % latest)


# --------------------------------------------------------------------------------------------------- P6 Theo
@sc("T02", "Theo", "10,000 reports")
def t02(t):
    b = t.box; b.setup()
    d0 = json.load(open(b.path("AE_Receipts/spring.20261001T163000Z.scrape.json")))
    for i in range(10000):
        d = dict(d0); d["projectName"] = "Proj%05d.aep" % (i % 500); d["projectPath"] = "/p/%d/%s" % (i % 500, d["projectName"]); d["scrapedAt"] = "2026-10-01T%02d:%02d:00Z" % (i // 600 % 24, i % 60)
        put(b.path("AE_Receipts/p%05d.%05d.scrape.json" % (i % 500, i)), json.dumps(d))
    for line, lim in (("check Proj00042", 8), ("timeline Proj00042", 20), ("check last", 8), ("lint last", 8), ("diff last", 8)):
        r = b.mj(line, timeout=120)
        t.fast(r, lim, "mj %s with 10,000 reports" % line)
    r = b.op("index.add", path=b.path("AE_Receipts"), timeout=300)
    if r.timed_out:
        t.fail("high", "index.add of 10,000 reports did not finish in 5 minutes")
    elif r.secs > 120:
        t.fail("low", "index.add of 10,000 reports took %ds" % r.secs)
    q = b.op("index.search", target="Proj00042 AND (", timeout=60)
    if q.j is None or q.timed_out:
        t.fail("medium", "a search with odd punctuation crashed or hung: %s" % q.short(120))


@sc("T03", "Theo", "32 mixed commands at once on one store")
def t03(t):
    b = t.box; b.setup()
    procs = []
    lines = ["snapshot Spring", "health Spring --record", "check Spring", "timeline Spring", "space", "index.add path=%s" % b.path("AE_Receipts"), "conform Spring", "lint Spring"] * 4
    for ln in lines:
        procs.append(subprocess.Popen(["/bin/zsh", "-f", "-c", 'source "%s"; mj %s' % (MJSH, ln)], env=b.env, cwd=b.home, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, start_new_session=True))
    t0 = time.time(); outs = []
    for p in procs:
        try:
            o, _ = p.communicate(timeout=180)
        except subprocess.TimeoutExpired:
            os.killpg(p.pid, signal.SIGKILL); o, _ = p.communicate(); o = b"HUNG"
        outs.append((p.returncode, o.decode("utf-8", "replace")))
    bad = [(lines[i], o[:100]) for i, (rc, o) in enumerate(outs) if o == "HUNG" or (JSONISH.search(o) and '"ok":false' in o) or "Traceback" in o or "CONFLICT" in o or "database is locked" in o or "ENGINE_FAILED" in o]
    if bad:
        t.fail("high", "%d of 32 parallel commands failed ugly: %s" % (len(bad), bad[:3]))
    v = b.op("index.verify")
    if not (v.j and v.j.get("ok")):
        t.fail("blocker", "the store is damaged after 32 parallel commands: %s" % v.short(160))


@sc("T04", "Theo", "cron-style environments")
def t04(t):
    b = t.box; b.setup()
    bad = []
    env_cases = {"no HOME": {"HOME": ""}, "PATH=/usr/bin:/bin only": {"PATH": "/usr/bin:/bin"}, "LANG=C": {"LANG": "C", "LC_ALL": "C"}, "unwritable TMPDIR": {"TMPDIR": "/nonexistent/"}, "TERM unset": {"TERM": ""}}
    for name, e in env_cases.items():
        r = b.run(["/bin/zsh", "-f", "-c", 'source "%s"; mj check Spring' % MJSH], env=e, timeout=60)
        if r.timed_out or "Traceback" in r.text or (name != "no HOME" and "command not found" in r.text):
            bad.append("%s: %s" % (name, r.short(120)))
    # stdout closed early (head -1): no hang
    r = b.run(["/bin/zsh", "-f", "-c", 'source "%s"; mj help | head -1; mj ops | head -2; mj timeline Spring | head -1' % MJSH], timeout=60)
    if r.timed_out:
        bad.append("closing stdout early hangs")
    # read-only HOME
    os.system("chmod -R a-w '%s'" % b.path("AE_Versions"))
    r = b.mj("snapshot Summer", timeout=30)
    os.system("chmod -R u+w '%s'" % b.path("AE_Versions"))
    if JSONISH.search(r.out) or "Traceback" in r.text or r.timed_out or ("Saved" in r.text and r.rc == 0 and False):
        bad.append("read-only versions folder: %s" % r.short(120))
    if "permission" not in r.text.lower() and "writable" not in r.text.lower() and "Saved" not in r.text:
        bad.append("read-only versions folder: message does not say why (%s)" % r.short(100))
    if bad:
        t.fail("medium", "; ".join(bad))


@sc("T05", "Theo", "recipes that misbehave")
def t05(t):
    b = t.box; b.setup()
    cases = {"missing param": "project.ingest path={{p}}\n", "unknown op": "nope.nope path=/x\n", "bad arg": "project.ingest bogus=1\n",
             "empty": "", "comments only": "# hi\n", "braces": "project.ingest path={{{{x}}}}\n", "1000 steps": "system.probe\n" * 1000, "crlf": "system.probe\r\nsystem.probe\r\n",
             "tab sep": "system.probe\t\n", "step fails midway": "system.probe\nproject.ingest path=/nonexistent/x.json\nsystem.probe\n"}
    bad = []
    for n, body in cases.items():
        rp = put(b.path("r_%s.mjrecipe" % n.replace(" ", "_")), body)
        r = b.mj('recipe "%s"' % rp, timeout=180)
        if r.timed_out or "Traceback" in r.text:
            bad.append("%s: %s" % (n, "HUNG" if r.timed_out else r.short(100)))
        elif n in ("missing param", "unknown op", "bad arg", "empty") and r.rc == 0:
            bad.append("%s: exit 0 for a broken recipe" % n)
        elif n == "1000 steps" and r.secs > 120:
            bad.append("1000 steps took %ds" % r.secs)
    if bad:
        t.fail("medium", "; ".join(bad))


@sc("T08", "Theo", "version skew in reports")
def t08(t):
    b = t.box; b.setup()
    base = json.load(open(b.path("AE_Receipts/spring.20261001T163000Z.scrape.json")))
    variants = {}
    v = json.loads(json.dumps(base)); v["extraTopLevel"] = {"anything": [1, 2]}; v["comps"][0]["newField"] = "x"; v["comps"][0]["layers"][0]["future"] = {"a": 1}; variants["extra keys"] = v
    v = json.loads(json.dumps(base)); v["comps"][0]["frameRate"] = "24"; v["comps"][0]["width"] = "1920"; v["comps"][0]["duration"] = "10"; variants["numbers as strings"] = v
    v = json.loads(json.dumps(base)); v["scraperVersion"] = "9.9"; v["schema"] = "MJ_PROJECT_SCRAPE_1"; variants["future scraper"] = v
    v = json.loads(json.dumps(base)); [c.pop("layers") for c in v["comps"]]; variants["no layers key"] = v
    v = json.loads(json.dumps(base)); v["comps"][0]["layers"][0]["label"] = 99; v["comps"][0]["layers"][0]["index"] = 0; variants["odd values"] = v
    v = json.loads(json.dumps(base)); v["scrapedAt"] = "yesterday"; variants["bad date"] = v
    v = json.loads(json.dumps(base)); del v["scrapedAt"]; variants["no date"] = v
    bad = []
    for n, d in variants.items():
        shutil.rmtree(b.path("AE_Receipts")); os.makedirs(b.path("AE_Receipts"))
        report(b, "skew", d, "20261002T100000Z")
        for line in ("check skew", "lint skew", "timeline skew", "conform skew", "diff last"):
            r = b.mj(line, timeout=60)
            if r.timed_out or "Traceback" in r.text or JSONISH.search(r.out) or re.search(r"ENGINE_FAILED|INGEST_FAILED|LINT_FAILED", r.text):
                bad.append("%s / mj %s: %s" % (n, line, r.short(110)))
    if bad:
        t.fail("high", "; ".join(bad[:6]) + (" ... (%d total)" % len(bad) if len(bad) > 6 else ""))


@sc("T09", "Theo", "upgrade over an existing install with data")
def t09(t):
    b = t.box; b.setup()
    b.mj("health Spring --record"); b.mj('snapshot "Spring Promo"'); b.op("index.add", path=b.path("AE_Receipts"))
    old_store = b.path("Library/Application Support/MographJailed")
    stale = os.path.join(old_store, "describe-1-1.json"); put(stale, '{"stale":true}')
    src = make_src(b)
    inst = b.path("Documents/MographJailed")
    rr = b.run(["/bin/zsh", "-f", os.path.join(ROOT, "tools/install-local.zsh"), src, inst], env={"MJ_YES": "1", "MJ_INSTALL_ALLOW_NONMAC": "1"}, timeout=120)
    rr2 = b.run(["/bin/zsh", "-f", os.path.join(ROOT, "tools/install-local.zsh"), src, inst], env={"MJ_YES": "1", "MJ_INSTALL_ALLOW_NONMAC": "1"}, timeout=120)
    if rr.rc != 0 or rr2.rc != 0:
        t.fail("high", "install over an existing install failed: %s" % (rr2.short(200) if rr2.rc else rr.short(200)))
    v = b.op("index.verify")
    if not (v.j and v.j.get("ok")):
        t.fail("high", "store unusable after upgrade: %s" % v.short(120))
    cfg = open(b.env["MJ_CONFIG"]).read()
    if "receipts_dir" not in cfg:
        t.fail("high", "settings lost on upgrade")
    r = b.run(["/bin/zsh", "-f", "-c", 'source "%s/scripts/shell/mj-cli.zsh"; mj ops | head -3' % inst], env={"MJ_CLI": inst + "/dist/mograph-jailed.zsh"}, timeout=60)
    if "project" not in r.text and "system" not in r.text:
        t.fail("medium", "mj ops after upgrade: %s (a stale cached operation list may be in use)" % r.short(150))


# --------------------------------------------------------------------------------------------------- P7 Neo
@sc("N01", "Neo", "poisoned installers")
def n01(t):
    b = t.box
    src = make_src(b)
    sums = write_sums
    marker = b.path("OUTSIDE_MARKER")
    bad = []
    def attempt(name, mutate, expect_refuse=False):
        d = os.path.join(b.tmp, "p_" + name.replace(" ", "_")); shutil.copytree(src, d, symlinks=True)
        mutate(d); sums(d) if name != "bad sums" else None
        inst = b.path("inst_" + name.replace(" ", "_"))
        r = b.run(["/bin/zsh", "-f", os.path.join(ROOT, "tools/install-local.zsh"), d, inst], env={"MJ_YES": "1", "MJ_INSTALL_ALLOW_NONMAC": "1", "MJ_ZSHRC": b.path(".zshrc-" + name.replace(" ", "_"))}, timeout=120)
        if os.path.exists(marker):
            bad.append("%s: WROTE OUTSIDE the install folder" % name); os.remove(marker)
        links = []
        if os.path.isdir(inst):
            for dp, dn, fn in os.walk(inst):
                for x in fn + dn:
                    fp = os.path.join(dp, x)
                    if os.path.islink(fp):
                        links.append(os.path.relpath(fp, inst) + " -> " + os.readlink(fp))
        return r, inst, links
    r, inst, links = attempt("symlink out", lambda d: os.symlink("/etc", os.path.join(d, "docs", "etc-link")))
    if links:
        bad.append("a symlink in the download is installed as a symlink pointing outside (%s)" % links[0])
    r, inst, links = attempt("setuid", lambda d: os.chmod(os.path.join(d, "tools", "uninstall-local.zsh"), 0o4755))
    if os.path.exists(os.path.join(inst, "tools", "uninstall-local.zsh")) and os.stat(os.path.join(inst, "tools", "uninstall-local.zsh")).st_mode & 0o6000:
        bad.append("setuid/setgid bit survives into the install")
    r, inst, links = attempt("world writable", lambda d: os.chmod(os.path.join(d, "dist", "mograph-jailed.zsh"), 0o777))
    if os.path.exists(os.path.join(inst, "dist", "mograph-jailed.zsh")) and os.stat(os.path.join(inst, "dist", "mograph-jailed.zsh")).st_mode & 0o022:
        bad.append("a group/world-writable runtime is installed as-is")
    def trav(d):
        s = open(os.path.join(d, "SHA256SUMS")).read(); open(os.path.join(d, "SHA256SUMS"), "w").write(s + "0" * 64 + "  ../OUTSIDE_MARKER\n")
    d = os.path.join(b.tmp, "p_trav"); shutil.copytree(src, d, symlinks=True); trav(d)
    r = b.run(["/bin/zsh", "-f", os.path.join(ROOT, "tools/install-local.zsh"), d, b.path("inst_trav")], env={"MJ_YES": "1", "MJ_INSTALL_ALLOW_NONMAC": "1"}, timeout=60)
    if r.rc == 0:
        bad.append("a checksum list naming ../OUTSIDE_MARKER was accepted")
    r, inst, links = attempt("devnode", lambda d: os.mkfifo(os.path.join(d, "docs", "pipe")))
    if r.timed_out:
        bad.append("a FIFO inside the download hangs the installer")
    if bad:
        t.fail("high", "; ".join(bad))


@sc("N03", "Neo", ".zshrc is not what we expect")
def n03(t):
    b = t.box
    src = make_src(b)
    B = "# >>> MographJailed (added by the installer; the uninstaller removes exactly this block) >>>"
    E = "# <<< MographJailed <<<"
    bad = []
    def inst(name, setup):
        rc = b.path("zshrc_" + name.replace(" ", "_")); setup(rc)
        before = open(rc, "rb").read() if os.path.isfile(rc) and not os.path.islink(rc) else None
        r = b.run(["/bin/zsh", "-f", os.path.join(ROOT, "tools/install-local.zsh"), src, b.path("i_" + name.replace(" ", "_"))], env={"MJ_YES": "1", "MJ_INSTALL_ZSHRC": "1", "MJ_INSTALL_ALLOW_NONMAC": "1", "MJ_ZSHRC": rc}, timeout=120)
        return rc, before, r
    precious = put(b.path("precious_target"), b"DO NOT TOUCH")
    def mk_symlink(rc): os.symlink(precious, rc)
    rc, before, r = inst("symlink", mk_symlink)
    # Dotfile managers symlink ~/.zshrc to a repo: writing through the link is what they want; replacing the link is the bug.
    if not os.path.islink(rc) or "DO NOT TOUCH" not in open(precious).read():
        bad.append("~/.zshrc as a symlink: the link was replaced or the file it points to was damaged")
    def only_open(rc): put(rc, "export A=1\n%s\nexport KEEP=1\n" % B)
    rc, before, r = inst("only opening marker", only_open)
    out = open(rc).read() if os.path.isfile(rc) else ""
    if "export KEEP=1" not in out and r.rc == 0:
        bad.append("an unclosed marker made the installer DELETE the user's lines that followed it")
    def ro(rc): put(rc, "export A=1\n"); os.chmod(rc, 0o444)
    rc, before, r = inst("read only", ro)
    if r.rc == 0 and open(rc).read() != "export A=1\n" and "MographJailed" not in open(rc).read():
        bad.append("read-only .zshrc: file damaged")
    def isdir(rc): os.makedirs(rc)
    rc, before, r = inst("directory", isdir)
    if r.timed_out or "Traceback" in r.text:
        bad.append("~/.zshrc being a directory: %s" % r.short(100))
    def crlf(rc): put(rc, "export A=1\r\nexport B=2\r\n")
    rc, before, r = inst("crlf", crlf)
    if "export B=2" not in open(rc).read():
        bad.append("CRLF .zshrc: lines lost")
    def huge(rc): put(rc, "export X=1\n" * 500000)
    rc, before, r = inst("huge", huge)
    if r.secs > 30:
        bad.append("500k-line .zshrc took %ds" % r.secs)
    if bad:
        t.fail("high", "; ".join(bad))


@sc("N04", "Neo", "path arguments that are symlinks, FIFOs and devices")
def n04(t):
    b = t.box; b.setup()
    os.symlink("/etc", b.path("etc_link")); os.symlink("/etc/hosts", b.path("hosts_link.json")); os.mkfifo(b.path("p.json")); os.makedirs(b.path("d.json"))
    bad = []
    for cmd, args in (("project.ingest", {"path": b.path("hosts_link.json")}), ("project.ingest", {"path": b.path("p.json")}), ("project.ingest", {"path": "/dev/zero"}), ("project.preflight", {"path": b.path("d.json")}),
                      ("file.hash", {"path": "/dev/zero"}), ("file.hash", {"path": b.path("p.json")}), ("file.inspect", {"path": b.path("etc_link")}), ("media.qc", {"path": "/dev/zero", "format": "web"}),
                      ("project.snapshot", {"path": b.path("hosts_link.json"), "output": b.path("AE_Versions")}), ("cache.clean", {"target": "../../etc"}), ("storage.preflight", {"path": "/dev/zero"})):
        r = b.op(cmd, timeout=30, **args)
        if r.timed_out:
            bad.append("%s %s HUNG" % (cmd, list(args.values())[0][-14:]))
        elif r.j is None:
            bad.append("%s: no JSON (%s)" % (cmd, r.short(80)))
    r = b.op("project.snapshot", path=b.path("hosts_link.json"), output=b.path("AE_Versions"))
    if r.j and r.j.get("ok") and r.j["data"].get("snapshotCreated"):
        bad.append("project.snapshot follows a symlink named *.json to /etc/hosts and copies it")
    if bad:
        t.fail("high", "; ".join(bad))


@sc("N07", "Neo", "resource exhaustion and catastrophic regex")
def n07(t):
    b = t.box; b.setup()
    p = b.path("AE/projects/Bomb/Bomb.aep"); put(p, b"bomb")
    nasty = ['thisComp.layer("' + "A" * 60000, 'comp("' + "A" * 60000 + '").layer("x").y', "thisComp.layer(" + "(" * 20000, "(" * 5000 + ")" * 5000, 'thisComp.layer("a")' * 3000, "\\" * 100000, 'comp("' + 'a\\"' * 20000 + '")', "a" * 2_000_000]
    layers = [layer(i + 1, "L%d" % i, "TextLayer", expressions=[{"propertyPath": "Transform/Position", "expression": e[:2000]}]) for i, e in enumerate(nasty)]
    layers.append(layer(99, "X" * 1_000_000, "TextLayer"))
    d = scrape(p, [comp(1, "Main", layers)], fonts=["F" * 100000])
    d["comps"][0]["name"] = "N" * 100000
    report(b, "bomb", d, "20261002T100000Z")
    bad = []
    for line in ("check Bomb", "lint Bomb", "conform Bomb", "timeline Bomb", "health Bomb"):
        r = b.mj(line, timeout=40)
        if r.timed_out:
            bad.append("mj %s HUNG (catastrophic backtracking or unbounded work)" % line)
        elif r.secs > 5:
            bad.append("mj %s took %.0fs" % (line, r.secs))
        elif "Traceback" in r.text:
            bad.append("mj %s: traceback" % line)
        elif len(r.out) > 200_000:
            bad.append("mj %s printed %d KB (a 1 MB layer name flooded the terminal)" % (line, len(r.out) // 1024))
    big = json.dumps(d); put(b.path("AE_Receipts/bomb.20261002T110000Z.scrape.json"), big)
    # a real catastrophic pattern for the regexes in lint / conform
    ex = 'thisComp.layer("' + "a\\" * 5000 + '")'
    d2 = scrape(p, [comp(1, "Main", [layer(1, "L", "TextLayer", expressions=[{"propertyPath": "T", "expression": ex}])])]); report(b, "bomb", d2, "20261002T120000Z")
    r = b.mj("lint Bomb", timeout=40)
    if r.timed_out:
        bad.append("lint hung on a backslash-heavy expression")
    if bad:
        t.fail("high", "; ".join(bad))


@sc("N08", "Neo", "escape sequences and bidi tricks in names")
def n08(t):
    b = t.box; b.setup()
    p = b.path("AE/projects/Evil/Evil.aep"); put(p, b"evil")
    nasty = {"esc color": "\x1b[31mRED\x1b[0m", "osc8 link": "\x1b]8;;http://evil.example\x1b\\click me\x1b]8;;\x1b\\", "title change": "\x1b]0;PWNED\x07", "bidi": "invoice‮gpj.exe", "cr overwrite": "good\rEVIL", "zero width": "a​b",
             "bell": "ding\x07", "clear screen": "\x1b[2J\x1b[H", "csi cursor": "\x1b[1A\x1b[2Kgone"}
    layers = [layer(i + 1, v, "TextLayer", expressions=[{"propertyPath": "Transform/Position", "expression": 'thisComp.layer("%s").x' % "Ghost"}]) for i, v in enumerate(nasty.values())]
    d = scrape(p, [comp(1, "Main \x1b[31mcomp\x1b[0m", layers)], footage=[{"id": 5, "name": "clip\x1b[41m.mov", "kind": "footage", "path": "/nonexistent/clip\x1b[41m.mov", "missing": True, "hasVideo": True, "hasAudio": False, "label": 1, "folder": ""}],
               fonts=["Font\x1b[31m"])
    d["projectName"] = "Evil.aep"
    report(b, "evil", d, "20261002T100000Z")
    bad = []
    for line in ("check Evil", "lint Evil", "conform Evil", "timeline Evil", "health Evil", "scene last", "versions"):
        r = b.mj(line)
        m = ESC.search(r.text)
        if m:
            bad.append("mj %s emits %r" % (line, m.group(0)))
    r = b.mj("lint Evil", env={"TERM": "xterm-256color"})
    r = b.mj("explain %s" % b.path("AE_Receipts/evil.20261002T100000Z.scrape.json"))
    if ESC.search(r.text):
        bad.append("mj explain emits control characters")
    if bad:
        t.fail("medium", "; ".join(bad) + " (a hostile project name can rewrite what the person sees: fake output, clipboard/title tricks, bidi spoofing)")


@sc("N10", "Neo", "tampering with the audit log")
def n10(t):
    b = t.box; b.setup()
    ad = b.path("audit"); os.makedirs(ad)
    env = {"MJ_AUDIT_DIR": ad}
    for i in range(6):
        b.run(["/bin/zsh", "-f", CLI, "--request", "-"], stdin="MOGRAPHJAILED_REQUEST 1\nrequestId=a%d\ncommand=system.probe\n" % i, env=env)
    log = os.path.join(ad, "audit.jsonl")
    if not os.path.exists(log):
        t.fail("medium", "audit log was not written when MJ_AUDIT_DIR is set");
    lines = open(log).read().splitlines()
    def intact(path):
        v = b.op("audit.verify", path=path, env=env)
        return bool(v.j and v.j.get("ok") and v.j["data"].get("firstBrokenLine") is None and v.j["data"].get("entriesVerified", 0) > 0), v
    ok0, v0 = intact(log)
    if not ok0:
        t.fail("high", "audit.verify rejects an untouched log: %s" % v0.short(150))
    bad = []
    # Dropping the last line(s) cannot be seen by a hash chain alone (it needs the head hash kept elsewhere): a known, documented limit.
    muts = {"edit": lambda L: L[:2] + [L[2].replace("system.probe", "file.hash")] + L[3:], "delete middle": lambda L: L[:2] + L[3:], "reorder": lambda L: L[:2] + [L[3], L[2]] + L[4:],
            "duplicate": lambda L: L[:3] + [L[2]] + L[3:], "append forged": lambda L: L + [L[-1].replace("a5", "a6")], "garbage line": lambda L: L[:3] + ["not json"] + L[3:]}
    for n, m in muts.items():
        open(log, "w").write("\n".join(m(lines)) + "\n")
        ok_, v = intact(log)
        if ok_:
            bad.append("'%s' went undetected" % n)
    open(log, "w").write("\n".join(lines) + "\n")
    if bad:
        sev = "high" if any(x.startswith(("'edit", "'delete", "'reorder", "'duplicate")) for x in bad) else "medium"
        t.fail(sev, "audit.verify misses: " + "; ".join(bad) + " (truncating the tail / appending are inherent limits of a plain hash chain unless the head hash is kept elsewhere)")


@sc("N12", "Neo", "the 'local only' promise: run common operations with the network denied")
def n12(t):
    if not os.path.exists("/usr/bin/sandbox-exec"):
        raise Fail("skip", "needs macOS sandbox-exec")
    b = t.box; b.setup()
    prof = '(version 1)(allow default)(deny network*)'
    bad = []
    for line in ("doctor", "check spring", "snapshot Spring", "lint spring", "timeline spring", "space", "conform spring", "extract spring Main", "ops"):
        r = b.run(["/usr/bin/sandbox-exec", "-p", prof, "/bin/zsh", "-f", "-c", 'source "%s"; mj %s' % (MJ_SH, line)], timeout=90) if False else b.run(["/usr/bin/sandbox-exec", "-p", prof, "/bin/zsh", "-f", "-c", 'source "%s"; mj %s' % (MJSH, line)], timeout=90)
        if "Operation not permitted" in r.text or "network" in r.text.lower() and "denied" in r.text.lower():
            bad.append("mj %s needs the network: %s" % (line, r.short(100)))
        if r.timed_out:
            bad.append("mj %s hangs without network" % line)
    if bad:
        t.fail("high", "; ".join(bad))


# --------------------------------------------------------------------------------------------------- P8 chaos
@sc("H01", "Hello Kitty", "the cat: garbage and held-down keys into every prompt")
def h01(t):
    b = t.box
    bad = []
    for stdin in ("\n" * 200, "asdf;lkj\x00\x01\x1b[A\x1b[B" * 40, "y\n" * 50, "😺" * 500 + "\n", "\x04"):
        r = b.run(["/bin/zsh", "-f", "-c", 'source "%s"; mj setup' % MJSH], stdin=stdin, timeout=40)
        if r.timed_out:
            bad.append("mj setup hangs on garbage input")
        if "Traceback" in r.text:
            bad.append("traceback on garbage input")
    cfg = b.env["MJ_CONFIG"]
    if os.path.exists(cfg):
        txt = open(cfg, errors="replace").read()
        if any(ord(c) < 32 and c not in "\n" for c in txt):
            bad.append("control characters from the cat got written to the settings file")
    if bad:
        t.fail("medium", "; ".join(sorted(set(bad))))


@sc("H02", "Hello Kitty", "the disk is full while a project is copied")
def h02(t):
    if sys.platform != "darwin":
        raise Fail("skip", "disk image test needs macOS")
    b = t.box; b.setup()
    img = os.path.join(b.tmp, "tiny.dmg")
    r = subprocess.run(["hdiutil", "create", "-size", "6m", "-fs", "APFS", "-volname", "TINY", "-attach", "-nobrowse", img], capture_output=True, text=True)
    mnt = "/Volumes/TINY"
    if r.returncode != 0 or not os.path.isdir(mnt):
        raise Fail("skip", "could not make a small disk image")
    try:
        put(b.path("AE/projects/Fat/Fat.aep"), os.urandom(1 << 20) * 12)
        b.mj("config set versions_dir %s/vers" % mnt) if os.makedirs(mnt + "/vers", exist_ok=True) is None else None
        r = b.mj("snapshot Fat", timeout=60)
        t.plain(r, "snapshot onto a full disk")
        if "Saved a verified copy" in r.text:
            t.fail("blocker", "claims a verified copy was saved onto a 6 MB disk from a 12 MB project")
        left = os.listdir(mnt + "/vers")
        if left:
            t.fail("medium", "a failed snapshot left files on the full disk: %s" % left[:3])
        if not re.search(r"space|full|room|free", r.text, re.I):
            t.fail("medium", "the message does not say the disk is full: %s" % r.short(160))
    finally:
        subprocess.run(["hdiutil", "detach", mnt, "-force"], capture_output=True)


@sc("H03", "Hello Kitty", "file descriptors and memory are scarce")
def h03(t):
    b = t.box; b.setup()
    bad = []
    r = b.run(["/bin/zsh", "-f", "-c", 'ulimit -n 24; source "%s"; mj check Spring; mj timeline Spring; mj space' % MJSH], timeout=60)
    if "Traceback" in r.text or JSONISH.search(r.out):
        bad.append("with 24 file descriptors: %s" % r.short(140))
    r = b.run(["/bin/zsh", "-f", "-c", 'ulimit -v 400000 2>/dev/null; source "%s"; mj check Spring; mj conform Spring' % MJSH], timeout=60)
    if r.timed_out:
        bad.append("hangs when memory is limited")
    if bad:
        t.fail("low", "; ".join(bad))


@sc("H04", "Hello Kitty", "two terminals at once: setup and snapshot while the watcher-style loop runs")
def h04(t):
    b = t.box; b.setup()
    ps = [subprocess.Popen(["/bin/zsh", "-f", "-c", 'source "%s"; for i in 1 2 3 4 5 6; do mj snapshot Summer >/dev/null 2>&1; done; mj versions' % MJSH], env=b.env, cwd=b.home, stdout=subprocess.PIPE, stderr=subprocess.STDOUT) for _ in range(4)]
    outs = [p.communicate(timeout=120)[0].decode("utf-8", "replace") for p in ps]
    v = [f for f in os.listdir(b.path("AE_Versions")) if f.startswith("Summer") and f.endswith(".aep")]
    if len(v) != 1:
        t.fail("high", "4 terminals snapshotting an unchanged project made %d versions (expected 1): %s" % (len(v), v))
    if any(("Traceback" in o or "CONFLICT" in o) for o in outs):
        t.fail("high", "ugly error from concurrent terminals: %s" % outs[0][:150])


@sc("H05", "Hello Kitty", "a file is edited while it is being snapshotted")
def h05(t):
    b = t.box; b.setup()
    big = b.path("AE/projects/Live/Live.aep"); os.makedirs(os.path.dirname(big))
    with open(big, "wb") as f:
        f.write(os.urandom(1 << 20) * 200)
    stop = [False]
    import threading
    def scribble():
        while not stop[0]:
            with open(big, "r+b") as f:
                f.seek(5 << 20); f.write(os.urandom(64))
            time.sleep(0.02)
    th = threading.Thread(target=scribble); th.start()
    r = b.mj("snapshot Live", timeout=120)
    stop[0] = True; th.join()
    t.plain(r, "snapshot of a file being saved")
    if "Saved a verified copy" in r.text:
        v = [f for f in os.listdir(b.path("AE_Versions")) if f.endswith(".aep")]
        if v:
            snap = os.path.join(b.path("AE_Versions"), v[0])
            h = hashlib.sha256(open(snap, "rb").read()).hexdigest()
            if h not in r.text and h[:12] not in snap:
                t.fail("blocker", "snapshot of a file changing underneath it was kept and named for a different hash than its bytes")
    elif not re.search(r"changed while|try again|save", r.text, re.I):
        t.fail("medium", "snapshot of a changing file fails without telling her why: %s" % r.short(160))


# --------------------------------------------------------------------------------------------------- main
def make_base():
    base = tempfile.mkdtemp(prefix="mj-persona-base.")
    home = os.path.join(base, "home"); os.makedirs(home)
    subprocess.run([sys.executable, FIX, os.path.join(home, "AE")], check=True, capture_output=True)
    sandboxed = {"HOME": home, "PATH": "/usr/bin:/bin:/opt/homebrew/bin", "MJ_CONFIG": os.path.join(home, ".config/mograph-jailed/config"),
                 "MJ_STORE_DIR": os.path.join(home, "Library/Application Support/MographJailed"), "MJ_CLI": CLI, "MOGRAPHJAILED_ROOT": ROOT}
    os.makedirs(os.path.join(home, "Library/Application Support"), exist_ok=True)
    # a person who finished `mj setup`: folders exist, reports are in the Reports folder
    for d in ("AE_Receipts", "AE_Versions"):
        os.makedirs(os.path.join(home, d))
    for f in os.listdir(os.path.join(home, "AE", "receipts")):
        shutil.copy(os.path.join(home, "AE", "receipts", f), os.path.join(home, "AE_Receipts", f))
    # rewrite projectPath etc. to the sandbox (the fixture builder already uses its root argument)
    subprocess.run(["/bin/zsh", "-f", "-c", 'source "%s"; mj config set watch_dir "%s/AE/projects" >/dev/null; mj config set receipts_dir "%s/AE_Receipts" >/dev/null; mj config set versions_dir "%s/AE_Versions" >/dev/null' % (MJSH, home, home, home)],
                   env=sandboxed, check=True, capture_output=True)
    return base


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only"); ap.add_argument("--ids"); ap.add_argument("--ledger"); ap.add_argument("--list", action="store_true"); ap.add_argument("--json")
    a = ap.parse_args()
    if a.list:
        for sid, per, title, _ in SCENARIOS:
            print("%-4s %-12s %s" % (sid, per, title))
        return 0
    if not os.path.isfile(CLI):
        print("run `sh scripts/build.zsh` first"); return 2
    only = set(x.strip().upper() for x in a.only.split(",")) if a.only else None
    ids = set(x.strip().upper() for x in a.ids.split(",")) if a.ids else None
    base = make_base()
    results = []
    t0 = time.time()
    for sid, per, title, fn in SCENARIOS:
        if ids and sid not in ids or only and sid[0] not in only:
            continue
        box = Box(os.path.join(base, "home"))
        t = T(box)
        s0 = time.time()
        try:
            fn(t); status, sev, msg = "PASS", "", ""
        except Fail as f:
            if f.sev == "skip":
                status, sev, msg = "SKIP", "", f.msg
            else:
                status, sev, msg = "FAIL", f.sev, f.msg
        except Exception as e:
            import traceback
            status, sev, msg = "ERROR", "harness", "".join(traceback.format_exception(type(e), e, e.__traceback__))[-600:]
        finally:
            box.cleanup()
        results.append((sid, per, title, status, sev, msg, time.time() - s0))
        print("%-4s %-4s %-12s %-10s %5.1fs  %s" % (sid, status, per, sev, results[-1][6], title))
        if msg:
            print("       -> " + msg[:600].replace("\n", " | "))
        sys.stdout.flush()
    shutil.rmtree(base, ignore_errors=True)
    n = {k: sum(1 for r in results if r[3] == k) for k in ("PASS", "FAIL", "SKIP", "ERROR")}
    print("\nPersona tests: %d pass, %d FAIL, %d skip, %d harness errors  (%.0fs)" % (n["PASS"], n["FAIL"], n["SKIP"], n["ERROR"], time.time() - t0))
    if a.json:
        json.dump([dict(id=r[0], persona=r[1], title=r[2], status=r[3], severity=r[4], saw=r[5], secs=round(r[6], 1)) for r in results], open(a.json, "w"), indent=1)
    return 1 if n["FAIL"] or n["ERROR"] else 0


if __name__ == "__main__":
    sys.exit(main())
