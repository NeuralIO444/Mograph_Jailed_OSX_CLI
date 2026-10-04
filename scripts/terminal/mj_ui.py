#!/usr/bin/python3
# MographJailed terminal UI: launch screen (`mj`) and live dashboard (`mj ui`).
#
# Read-only. It asks the runtime for facts (host.detect, index.verify,
# audit.verify, audit.plugins) and reads the render history and audit log files
# directly; it never writes anywhere. System python3, standard library only.
#
#   mj_ui.py home [--plain] [--width N] [--no-anim]
#   mj_ui.py ui   [--tab overview|renders|library|audit] [--once] [--plain] [--width N] [--height N]
#
# Environment: MJ_CLI (runtime path), MJ_STORE_DIR, MJ_AUDIT_DIR, NO_COLOR,
# MJ_PLAIN=1 (no color/animation), MJ_ASCII=1 (ASCII borders), MJ_NO_ANIM=1.

import json, os, re, select, shutil, signal, subprocess, sys, tempfile, threading, time
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone

ROOT = os.environ.get("MOGRAPHJAILED_ROOT") or os.path.join(os.path.expanduser("~"), "Documents", "MographJailed")
CLI = os.environ.get("MJ_CLI") or os.path.join(ROOT, "dist", "mograph-jailed.zsh")
STORE = os.environ.get("MJ_STORE_DIR") or os.path.join(os.path.expanduser("~"), "Library", "Application Support", "MographJailed")
AUDIT_DIR = os.environ.get("MJ_AUDIT_DIR") or os.path.join(os.path.expanduser("~"), "Library", "Logs", "MographJailed")

# ---------------------------------------------------------------- terminal ----

class Term:
    def __init__(self, plain=False, width=None, height=None, anim=True):
        tty = sys.stdout.isatty()
        self.tty = tty
        self.color = (not plain) and tty and not os.environ.get("NO_COLOR") and os.environ.get("TERM", "dumb") != "dumb" \
            and os.environ.get("MJ_PLAIN") != "1"
        self.true = self.color and os.environ.get("COLORTERM", "").lower() in ("truecolor", "24bit")
        self.ascii = os.environ.get("MJ_ASCII") == "1" or plain or not tty   # logs and pipes get ASCII
        self.anim = anim and self.color and os.environ.get("MJ_NO_ANIM") != "1"
        size = shutil.get_terminal_size((80, 24))
        self.w = max(50, min(width or size.columns, 120))
        self.h = height or size.lines

    # colors -------------------------------------------------------------
    def _c(self, rgb, bg=False):
        if not self.color:
            return ""
        r, g, b = rgb
        if self.true:
            return "\x1b[%d;2;%d;%d;%dm" % (48 if bg else 38, r, g, b)
        def q(v): return 0 if v < 48 else 1 if v < 115 else (v - 35) // 40
        return "\x1b[%d;5;%dm" % (48 if bg else 38, 16 + 36 * q(r) + 6 * q(g) + q(b))

    def paint(self, text, rgb, bold=False, dim=False):
        if not self.color:
            return text
        return (("\x1b[1m" if bold else "") + ("\x1b[2m" if dim else "") + self._c(rgb) + text + "\x1b[0m")

    def gradient(self, text, a, b, bold=True):
        if not self.color:
            return text
        n = max(len(text) - 1, 1)
        out = []
        for i, ch in enumerate(text):
            if ch == " ":
                out.append(ch); continue
            t = i / n
            rgb = tuple(int(a[k] + (b[k] - a[k]) * t) for k in range(3))
            out.append(("\x1b[1m" if bold else "") + self._c(rgb) + ch)
        return "".join(out) + "\x1b[0m"

    # glyphs -------------------------------------------------------------
    @property
    def g(self):
        if self.ascii:
            return dict(tl="+", tr="+", bl="+", br="+", h="-", v="|", dot="*", ok="v", bad="x", warn="!",
                        off="-", arrow=">", spin="|/-\\", spark=" .:-=+*#", sep="|", bar_on="#", bar_off=".", mid="-")
        return dict(tl="╭", tr="╮", bl="╰", br="╯", h="─", v="│", dot="●", ok="✓", bad="✗", warn="▲",
                    off="○", arrow="›", spin="⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏", spark=" ▁▂▃▄▅▆▇█", sep="·", bar_on="█", bar_off="░", mid="─")


TEAL, VIOLET = (0, 214, 170), (150, 110, 255)
OK, BAD, WARN, DIM, TEXT, ACCENT = (80, 220, 130), (255, 90, 100), (255, 190, 70), (120, 130, 150), (210, 215, 225), (110, 190, 255)
ANSI = re.compile(r"\x1b\[[0-9;?]*[A-Za-z]")


def vlen(s):
    return len(ANSI.sub("", s))


def pad(s, n):
    return s + " " * max(0, n - vlen(s))


def clip(s, n):
    """Truncate to n visible columns, keeping ANSI sequences intact."""
    if vlen(s) <= n:
        return s
    out, vis, i = [], 0, 0
    while i < len(s) and vis < n - 1:
        m = ANSI.match(s, i)
        if m:
            out.append(m.group(0)); i = m.end(); continue
        out.append(s[i]); vis += 1; i += 1
    return "".join(out) + "…" + ("\x1b[0m" if "\x1b" in s else "")


def card(t, title, lines, width, accent=TEAL):
    g = t.g
    inner = width - 4
    top_title = " " + t.paint(title, accent, bold=True) + " "
    fill = width - 2 - vlen(top_title) - 1
    top = t.paint(g["tl"] + g["h"], DIM) + top_title + t.paint(g["h"] * max(fill, 0) + g["tr"], DIM)
    body = [t.paint(g["v"], DIM) + " " + pad(clip(ln, inner), inner) + " " + t.paint(g["v"], DIM) for ln in lines]
    bot = t.paint(g["bl"] + g["h"] * (width - 2) + g["br"], DIM)
    return [top] + body + [bot]


def side_by_side(a, b, gap=2):
    h = max(len(a), len(b))
    wa = max(vlen(x) for x in a)
    wb = max(vlen(x) for x in b)
    a = a + [" " * wa] * (h - len(a))
    b = b + [" " * wb] * (h - len(b))
    return [pad(x, wa) + " " * gap + y for x, y in zip(a, b)]


def ago(iso):
    try:
        then = datetime.strptime(iso, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)
    except (TypeError, ValueError):
        return "?"
    s = int((datetime.now(timezone.utc) - then).total_seconds())
    if s < 0: return "now"
    if s < 90: return "%ds ago" % s
    if s < 5400: return "%dm ago" % (s // 60)
    if s < 172800: return "%dh ago" % (s // 3600)
    return "%dd ago" % (s // 86400)


def n(v):
    return "{:,}".format(v) if isinstance(v, int) else str(v)


def spark(t, vals, width):
    vals = vals[-width:]
    if not vals:
        return ""
    lo, hi = min(vals), max(vals)
    ramp = t.g["spark"]
    return "".join(ramp[1 + int((v - lo) / (hi - lo) * (len(ramp) - 2))] if hi > lo else ramp[len(ramp) // 2] for v in vals)

# -------------------------------------------------------------------- data ----


UNSAFE = re.compile("[\x00-\x08\x0b-\x1f\x7f-\x9f\u00ad\u061c\u200b-\u200f\u2028-\u202e\u2060-\u206f\ufeff\ufff9-\ufffb\U000e0000-\U000e007f]")


def scrub(v):
    """Names and paths in the data come from projects and can carry terminal control codes or right-to-left overrides:
    show them as visible escapes. The dashboard's own colours are added later, so they are unaffected."""
    if isinstance(v, str):
        return UNSAFE.sub(lambda m: "\\x%02x" % ord(m.group()) if ord(m.group()) < 256 else "\\u%04x" % ord(m.group()) if ord(m.group()) < 0x10000 else "\\U%08x" % ord(m.group()), v)
    if isinstance(v, list):
        return [scrub(x) for x in v]
    if isinstance(v, dict):
        return {k: scrub(x) for k, x in v.items()}
    return v


def call(op, **args):
    """One runtime request. Returns the response envelope, or None if the runtime is unusable."""
    if not os.path.isfile(CLI):
        return None
    fd, req = tempfile.mkstemp(prefix="mj-ui-request.")
    try:
        import base64
        with os.fdopen(fd, "w") as f:
            f.write("MOGRAPHJAILED_REQUEST 1\nrequestId=ui-%d-%d\ncommand=%s\n" % (os.getpid(), threading.get_ident() % 100000, op))
            for k, v in args.items():
                f.write("arg.%s=%s\n" % (k, base64.b64encode(str(v).encode()).decode()))
        env = dict(os.environ)
        r = subprocess.run(["/bin/zsh", "-f", CLI, "--request", req], capture_output=True, text=True, timeout=60, env=env, stdin=subprocess.DEVNULL)
        return scrub(json.loads(r.stdout))
    except Exception:
        return None
    finally:
        try: os.unlink(req)
        except OSError: pass


def read_jsonl_tail(path, count):
    try:
        with open(path, "rb") as f:
            f.seek(0, os.SEEK_END)
            size = f.tell()
            f.seek(max(0, size - 65536))
            lines = f.read().decode("utf-8", "replace").splitlines()
    except OSError:
        return []
    out = []
    for ln in lines[-count:]:
        try: out.append(json.loads(ln))
        except ValueError: pass
    return out


def render_running():
    try:
        pid = int(open(os.path.join(STORE, "locks", "render.lock", "pid")).read().strip())
        os.kill(pid, 0)
        return True
    except (OSError, ValueError):
        return False


def read_progress():
    """Live render progress, only while a render really is running (lock owner alive)."""
    if not render_running():
        return None
    try:
        with open(os.path.join(STORE, "render-progress.json")) as f:
            d = json.load(f)
        os.kill(int(d["pid"]), 0)
        return d
    except (OSError, ValueError, KeyError, TypeError):
        return None


def hms(seconds):
    if seconds is None:
        return "--:--"
    seconds = int(seconds)
    return "%d:%02d" % (seconds // 60, seconds % 60) if seconds < 3600 else "%d:%02d:%02d" % (seconds // 3600, seconds % 3600 // 60, seconds % 60)


def progress_text(p):
    if p.get("total"):
        return "%s · %d/%d frames · %d%% · %.1f fps · eta %s" % (p["label"], p["frames"], p["total"], round(p["percent"] or 0), p.get("fps") or 0, hms(p.get("etaSeconds")))
    return "%s · %d frames · %.1f fps · %s elapsed" % (p["label"], p["frames"], p.get("fps") or 0, hms(p.get("elapsed")))


def progress_bar(t, p, width, tick):
    """Determinate bar with a moving highlight when the total is known, a bouncing block otherwise."""
    g = t.g
    width = max(10, width)
    if p.get("total"):
        fill = int(width * min(1.0, p["frames"] / p["total"]))
        cells = []
        for i in range(width):
            if i < fill:
                shimmer = (i - tick) % 14 == 0 and t.color
                rgb = (255, 255, 255) if shimmer else tuple(int(TEAL[k] + (VIOLET[k] - TEAL[k]) * i / max(width - 1, 1)) for k in range(3))
                cells.append(t.paint(g["bar_on"], rgb))
            else:
                cells.append(t.paint(g["bar_off"], DIM))
        return "".join(cells)
    pos = abs((tick % (2 * (width - 4))) - (width - 4))
    return "".join(t.paint(g["bar_on"], TEAL) if pos <= i < pos + 4 else t.paint(g["bar_off"], DIM) for i in range(width))


class State:
    """Facts about this machine, each loaded independently so the UI can fill in as they land."""
    SLOTS = ("describe", "hosts", "library", "audit", "plugins", "health")

    def __init__(self):
        self.d = {k: None for k in self.SLOTS}
        self.done = {k: False for k in self.SLOTS}
        self.stamp = 0.0
        self.lock = threading.Lock()

    def fetch(self, slot):
        if slot == "describe":
            v = call("system.describe")
        elif slot == "hosts":
            v = call("host.detect")
        elif slot == "library":
            v = call("index.verify")
        elif slot == "plugins":
            v = call("audit.plugins", maxResults=8)
        elif slot == "health":
            v = call("project.health", format="all")
        else:
            log = os.path.join(AUDIT_DIR, "audit.jsonl")
            v = {"enabled": os.path.isdir(AUDIT_DIR), "exists": os.path.isfile(log), "verify": call("audit.verify", path=log) if os.path.isfile(log) else None}
        with self.lock:
            self.d[slot] = v
            self.done[slot] = True
            self.stamp = time.time()

    def refresh_async(self, pool, slots=None):
        for s in slots or self.SLOTS:
            self.done[s] = False
            pool.submit(self.fetch, s)

    @property
    def loading(self):
        return not all(self.done.values())

# ----------------------------------------------------------------- content ----


def version_info(st):
    r = st.d["describe"]
    if not r or not r.get("ok"):
        return None
    ops = r["data"]["operations"]
    return {"version": r.get("cliVersion", "?"), "ops": len(ops), "available": sum(1 for o in ops.values() if o.get("available"))}


def hosts_rows(t, st, spin):
    """(label, state, text) rows. state: ok|warn|bad|off|load"""
    if not st.done["hosts"]:
        return [("hosts", "load", "detecting After Effects and Cinema 4D")]
    r = st.d["hosts"]
    if not r or not r.get("ok"):
        return [("hosts", "bad", "runtime unavailable")]
    d = r["data"]
    rows = []
    sup = sorted((h for h in d["afterEffects"] if h["supported"]), key=lambda h: -h["year"])
    if sup:
        h = sup[0]
        rows.append(("after effects", "ok", "%d (%s)  aerender %s" % (h["year"], h["version"] or "?", t.g["ok"])))
    else:
        old = [h for h in d["afterEffects"] if not h["supported"]]
        rows.append(("after effects", "warn" if old else "off", "none 2024+ found" + ("  (%s older/incomplete)" % ", ".join(str(h["year"]) for h in old) if old else "")))
    c4 = sorted((h for h in d["cinema4d"] if h["supported"]), key=lambda h: -h["year"])
    if c4:
        h = c4[0]
        rows.append(("cinema 4d", "ok", "%d (%s)  redshift %s  c4dpy %s" % (h["year"], h["version"] or "?", t.g["ok"] if h["redshift"] else t.g["off"], t.g["ok"] if h["c4dpy"] else t.g["off"])))
    else:
        rows.append(("cinema 4d", "off", "none 2024+ found"))
    if d.get("gpu"):
        gp = d["gpu"][0]
        rows.append(("gpu", "ok", "%s%s  %s" % (gp.get("name") or "?", " · %s cores" % gp["cores"] if gp.get("cores") else "", (gp.get("metal") or "").replace("spdisplays_", "").replace("_", " "))))
    return rows


def library_rows(t, st):
    if not st.done["library"]:
        return [("library", "load", "opening the local index")]
    r = st.d["library"]
    if not r:
        return [("library", "bad", "runtime unavailable")]
    if not r.get("ok"):
        if (r.get("error") or {}).get("code") == "STORE_EMPTY":
            return [("library", "off", "empty  %s  mj index.add path=<receipts>" % t.g["arrow"])]
        return [("library", "bad", (r.get("error") or {}).get("code", "error"))]
    d = r["data"]
    ok = d.get("healthy")
    txt = "%s projects · %s entries · %s presets · %s" % (n(d.get("projects", 0)), n(d["entries"]), n(d["presetBlobs"]), "healthy" if ok else "NEEDS ATTENTION")
    rows = [("library", "ok" if ok else "bad", txt)]
    if d.get("staleDocs"):
        rows.append(("", "warn", "%d indexed receipts no longer on disk" % len(d["staleDocs"])))
    if d.get("corruptPresetBlobs"):
        rows.append(("", "bad", "%d preset blobs failed their hash" % len(d["corruptPresetBlobs"])))
    return rows


def audit_rows(t, st):
    if not st.done["audit"]:
        return [("audit log", "load", "checking the hash chain")]
    a = st.d["audit"]
    if not a or not a["enabled"]:
        return [("audit log", "off", "off  %s  mkdir -p ~/Library/Logs/MographJailed" % t.g["arrow"])]
    if not a["exists"]:
        return [("audit log", "ok", "on · no entries yet")]
    v = a["verify"]
    if not v or not v.get("ok"):
        return [("audit log", "bad", "could not verify")]
    d = v["data"]
    if d["valid"]:
        return [("audit log", "ok", "chain intact · %s entries · head %s" % (n(d["entriesVerified"]), (d["headHash"] or "")[:8]))]
    return [("audit log", "bad", "CHAIN BROKEN at line %s (%s)" % (d["firstBrokenLine"], d["reason"]))]


def render_rows(t, spin):
    hist = read_jsonl_tail(os.path.join(STORE, "renders.jsonl"), 1)
    if render_running():
        pr = read_progress()
        return [("last render", "run", progress_text(pr) if pr else "rendering now")]
    if not hist:
        return [("last render", "off", "none yet  %s  mj ae.render … / mj c4d.render …" % t.g["arrow"])]
    h = hist[-1]
    st = "ok" if h["status"] == "complete" else "bad"
    exp = "/%s" % h["expected"] if h.get("expected") else ""
    return [("last render", st, "%s · %s · %s%s frames · %ss · %s" % ({"afterEffects": "ae", "cinema4d": "c4d"}.get(h["host"], h["host"]), h["status"], h["frames"], exp, h["seconds"], ago(h["endedAt"])))]


def row_line(t, label, state, text, spin, tick, labels=True):
    g = t.g
    if state == "load":
        mark = t.paint(g["spin"][spin % len(g["spin"])], ACCENT)
        body = t.paint(text, DIM)
    elif state == "run":
        pulse = TEAL if tick % 8 < 4 else VIOLET
        mark = t.paint(g["dot"], pulse, bold=True)
        body = t.paint(text, pulse, bold=True)
    else:
        col = {"ok": OK, "warn": WARN, "bad": BAD, "off": DIM}[state]
        mark = t.paint({"ok": g["ok"], "warn": g["warn"], "bad": g["bad"], "off": g["off"]}[state], col, bold=True)
        body = t.paint(text, TEXT if state == "ok" else col)
    if not labels:      # inside a card whose title already names the row
        return "%s %s" % (mark, body)
    return "%s %s %s" % (mark, t.paint(pad(label, 14), DIM), body)

# ---------------------------------------------------------------- launch -----

WORDMARK = [
    "█▀▄▀█ █▀█ █▀▀ █▀█ ▄▀█ █▀█ █ █   ▀█ ▄▀█ █ █   █▀▀ █▀▄",
    "█ ▀ █ █▄█ █▄█ █▀▄ █▀█ █▀▀ █▀█ █▄█ █▀█ █ █▄▄ ██▄ █▄▀",
]
WORDMARK_ASCII = ["M O G R A P H   J A I L E D"]
TIPS = [
    "mj ops lists every operation; Tab completes names and arguments",
    "mj loop.seams path=<frames> finds the best loop points in a render",
    "mj golden.check catches a look changing after a plugin update",
    "mj trace.asset format=missing shows the nested path to every missing file",
    "mj audit.plugins target=<matchName> lists projects using an effect",
    "mj recipe <file> runs a checked, data-only multi-step recipe",
    "mj ui opens the live dashboard",
]


def banner(t, version_text):
    mark = WORDMARK_ASCII if t.ascii else WORDMARK
    out = [""]
    for i, ln in enumerate(mark):
        a = tuple(int(TEAL[k] + (VIOLET[k] - TEAL[k]) * (i / max(len(mark), 1)) * 0.4) for k in range(3))
        out.append("  " + t.gradient(ln, a, VIOLET))
    out.append("  " + t.paint("after effects  " + t.g["sep"] + "  cinema 4d  " + t.g["sep"] + "  local  " + t.g["sep"] + "  zero-daemon", DIM))
    if version_text:
        out.append("  " + t.paint(version_text, DIM))
    out.append("")
    return out


def run_home(t):
    st = State()
    pool = ThreadPoolExecutor(max_workers=5)
    st.refresh_async(pool)
    # banner reveal
    first = banner(t, "")
    for ln in first:
        print(ln, flush=True)
        if t.anim:
            time.sleep(0.035)
    spin = 0
    drawn = 0

    def rows():
        r = hosts_rows(t, st, spin) + library_rows(t, st) + audit_rows(t, st) + render_rows(t, spin)
        vi = version_info(st) if st.done["describe"] else None
        head = ("runtime", "ok", "%s · %d operations (%d available) · protocol v1" % (vi["version"], vi["ops"], vi["available"])) if vi else \
               (("runtime", "load", "starting") if not st.done["describe"] else ("runtime", "bad", "runtime not found at %s" % CLI))
        return [head] + r

    def draw():
        nonlocal drawn
        lines = ["  " + row_line(t, a, b, c, spin, spin) for a, b, c in rows()]
        if drawn and t.anim:
            sys.stdout.write("\x1b[%dA" % drawn)
        for ln in lines:
            sys.stdout.write("\x1b[2K" + clip(ln, t.w) + "\n" if t.anim else clip(ln, t.w) + "\n")
        sys.stdout.flush()
        drawn = len(lines)

    if t.anim:
        sys.stdout.write("\x1b[?25l")
        try:
            deadline = time.time() + 20
            while st.loading and time.time() < deadline:
                draw(); spin += 1; time.sleep(0.08)
            draw()
        finally:
            sys.stdout.write("\x1b[?25h")
    else:
        deadline = time.time() + 30
        while st.loading and time.time() < deadline:
            time.sleep(0.05)
        draw()
    pool.shutdown(wait=False)
    tip = TIPS[int(time.time() // 60) % len(TIPS)]
    print()
    print(clip("  " + t.paint("try", DIM) + "  " + t.paint(tip, TEXT), t.w))
    print(clip("       " + t.paint("mj ui", ACCENT, bold=True) + t.paint("  live dashboard    ", DIM) + t.paint("mj help", ACCENT, bold=True) + t.paint("  usage    ", DIM) + t.paint("mj-man", ACCENT, bold=True) + t.paint("  manual", DIM), t.w))
    print()

# ------------------------------------------------------------- dashboard -----

TABS = ["overview", "renders", "library", "audit"]


def header(t, st, tab, w, tick):
    vi = version_info(st) if st.done["describe"] else None
    title = t.gradient("MOGRAPHJAILED", TEAL, VIOLET) if t.color else "MOGRAPHJAILED"
    right = "%s · %d ops" % (vi["version"], vi["ops"]) if vi else ""
    tabs = []
    for i, name in enumerate(TABS):
        label = "%d %s" % (i + 1, name)
        if name != tab:
            tabs.append(t.paint(" %s " % label, DIM))
        elif t.color:   # selected tab: dark text on a teal chip
            tabs.append(t._c((20, 24, 34)) + t._c(TEAL, bg=True) + "\x1b[1m" + " %s " % label + "\x1b[0m")
        else:
            tabs.append("[%s]" % label)
    line1 = " " + title + "  " + t.paint(right, DIM)
    line2 = " " + "".join(tabs)
    rule = t.paint(t.g["mid"] * w, DIM)
    return [line1, line2, rule]


def footer(t, st, w, tick, msg=""):
    spin = t.g["spin"][tick % len(t.g["spin"])] if st.loading else t.g["ok"]
    age = "updated %ds ago" % int(time.time() - st.stamp) if st.stamp else ""
    left = "  " + t.paint(spin, ACCENT if st.loading else OK) + " " + t.paint("loading" if st.loading else age, DIM)
    keys = t.paint("1-4/tab", ACCENT) + t.paint(" switch  ", DIM) + t.paint("r", ACCENT) + t.paint(" refresh  ", DIM) + t.paint("q", ACCENT) + t.paint(" quit", DIM)
    gap = w - vlen(left) - vlen(keys) - 1
    return [t.paint(t.g["mid"] * w, DIM), left + " " * max(gap, 2) + keys]


def tab_overview(t, st, w, tick):
    rows = []
    cw = w if w < 100 else (w - 2) // 2
    hosts = card(t, "HOSTS", [row_line(t, a, b, c, tick, tick) for a, b, c in hosts_rows(t, st, tick)], cw)
    lib = card(t, "LIBRARY", [row_line(t, a, b, c, tick, tick, labels=False) for a, b, c in library_rows(t, st)], cw, VIOLET)
    aud = card(t, "AUDIT LOG", [row_line(t, a, b, c, tick, tick, labels=False) for a, b, c in audit_rows(t, st)], cw, ACCENT)
    ren = card(t, "LAST RENDER", [row_line(t, a, b, c, tick, tick, labels=False) for a, b, c in render_rows(t, tick)] + _progress_lines(t, cw - 4, tick) + _render_spark_lines(t, cw - 4), cw, WARN)
    k = int(time.time() // 60)
    tips = card(t, "TRY", [t.paint(t.g["arrow"] + " ", ACCENT) + t.paint(TIPS[(k + i) % len(TIPS)], TEXT) for i in range(3)], w, DIM)
    if w >= 100:
        rows += side_by_side(hosts + ren, lib + aud)
    else:
        rows += hosts + lib + aud + ren
    return rows + tips


def _progress_lines(t, width, tick):
    pr = read_progress()
    if not pr:
        return []
    pct = ("%3d%%" % round(pr["percent"] or 0)) if pr.get("total") else " ..."
    return ["  " + progress_bar(t, pr, width - 10, tick) + " " + t.paint(pct, TEAL, bold=True)]


def _render_spark_lines(t, width):
    hist = read_jsonl_tail(os.path.join(STORE, "renders.jsonl"), 40)
    if len(hist) < 2:
        return []
    secs = [float(h.get("seconds") or 0) for h in hist]
    ok = sum(1 for h in hist if h["status"] == "complete")
    return [t.paint("  " + "time  ", DIM) + t.paint(spark(t, secs, max(10, width - 24)), TEAL) + t.paint("  %d/%d complete" % (ok, len(hist)), DIM)]


def tab_renders(t, st, w, tick):
    hist = read_jsonl_tail(os.path.join(STORE, "renders.jsonl"), 200)
    head = ["when", "host", "status", "frames", "secs", "folder"]
    wid = [10, 6, 11, 9, 7]
    lines = [t.paint("  ".join(pad(h, wid[i]) if i < 5 else h for i, h in enumerate(head)), DIM)]
    for h in reversed(hist[-(max(t.h - 14, 5)):]):
        col = OK if h["status"] == "complete" else BAD
        frames = "%s/%s" % (h["frames"], h["expected"]) if h.get("expected") else str(h["frames"])
        lines.append("  ".join([pad(ago(h["endedAt"]), wid[0]), pad({"afterEffects": "ae", "cinema4d": "c4d"}.get(h["host"], h["host"]), wid[1]),
                                t.paint(pad(h["status"], wid[2]), col, bold=True), pad(frames, wid[3]), pad(str(h["seconds"]), wid[4]), t.paint(h["label"], DIM)]))
    if len(hist) == 0:
        lines.append(t.paint("  no renders yet.  mj ae.render … / mj c4d.render …", DIM))
    out = card(t, "RENDER HISTORY (%d)" % len(hist), lines, w, WARN)
    if render_running():
        out = card(t, "RENDERING", [row_line(t, a, b, c, tick, tick, labels=False) for a, b, c in render_rows(t, tick)] + _progress_lines(t, w - 4, tick), w, TEAL) + out
    return out


def health_lines(t, st, width):
    """One line per recorded project: score, trend sparkline, direction. Colour follows the band."""
    if not st.done["health"]:
        return [t.paint(t.g["spin"][0] + " reading recorded health scores", DIM)]
    h = st.d["health"]
    if not h or not h.get("ok"):
        return [t.paint("  none recorded yet.  mj health last --record", DIM)]
    rows = []
    arrow = {"improving": "▲", "worsening": "▼", "steady": "•"} if not t.ascii else {"improving": "^", "worsening": "v", "steady": "-"}
    for p in h["data"]["projects"][:8]:
        sc = p["latestScore"]
        col = OK if sc >= 90 else ACCENT if sc >= 70 else WARN if sc >= 40 else BAD
        name = os.path.basename(p["projectPath"])
        rows.append("%s %s  %s  %s" % (pad(clip(name, max(12, width - 36)), max(12, width - 36)), t.paint("%3d" % sc, col, bold=True),
                                      t.paint(pad(spark(t, [float(v) for v in p["series"]], 14), 14), col), t.paint("%s %s" % (arrow[p["direction"]], p["direction"]), DIM)))
    return rows or [t.paint("  none recorded yet.  mj health last --record", DIM)]


def tab_library(t, st, w, tick):
    lib = [row_line(t, a, b, c, tick, tick) for a, b, c in library_rows(t, st)]
    out = card(t, "LIBRARY", lib, w, VIOLET) + card(t, "PROJECT HEALTH", health_lines(t, st, w - 4), w, OK)
    p = st.d["plugins"]
    lines = []
    if not st.done["plugins"]:
        lines = [row_line(t, "plugins", "load", "reading the plugin inventory", tick, tick)]
    elif p and p.get("ok"):
        d = p["data"]
        mx = max([e["projects"] for e in d["effects"]] + [1])
        lines.append(t.paint("%-34s %8s %8s" % ("effect matchName", "projects", "uses"), DIM))
        for e in d["effects"][:max(t.h - 18, 4)]:
            bar = int(10 * e["projects"] / mx)
            lines.append("%-34s %8d %8d  %s" % (clip(e["matchName"], 34), e["projects"], e["layerUses"], t.paint(t.g["bar_on"] * bar + t.g["bar_off"] * (10 - bar), TEAL)))
    else:
        lines = [t.paint("  index some scrapes first:  mj index.add path=<receipts>", DIM)]
    return out + card(t, "TOP EFFECTS", lines, w, TEAL)


def tab_audit(t, st, w, tick):
    out = card(t, "HASH CHAIN", [row_line(t, a, b, c, tick, tick) for a, b, c in audit_rows(t, st)], w, ACCENT)
    entries = read_jsonl_tail(os.path.join(AUDIT_DIR, "audit.jsonl"), max(t.h - 16, 6))
    lines = [t.paint("%-22s %-20s %5s" % ("time (UTC)", "command", "exit"), DIM)]
    for e in reversed(entries):
        col = OK if e.get("exitCode") == 0 else BAD
        lines.append("%-22s %-20s %s" % (e.get("ts", "?")[:19].replace("T", " "), clip(e.get("command") or "(invalid)", 20), t.paint("%5s" % e.get("exitCode"), col)))
    if not entries:
        lines.append(t.paint("  nothing logged.  mkdir -p ~/Library/Logs/MographJailed", DIM))
    return out + card(t, "RECENT REQUESTS", lines, w, TEAL)


def compose(t, st, tab, tick):
    w = t.w
    body = {"overview": tab_overview, "renders": tab_renders, "library": tab_library, "audit": tab_audit}[tab](t, st, w - 2, tick)
    lines = header(t, st, tab, w, tick) + [" " + clip(ln, w - 1) for ln in body]
    return lines, footer(t, st, w, tick)


def run_ui(t, tab, once):
    st = State()
    pool = ThreadPoolExecutor(max_workers=5)
    st.refresh_async(pool)
    if once:
        deadline = time.time() + 40
        while st.loading and time.time() < deadline:
            time.sleep(0.05)
        body, foot = compose(t, st, tab, 0)
        print("\n".join(clip(ln, t.w) for ln in body + foot))
        pool.shutdown(wait=False)
        return 0

    import termios, tty
    fd = sys.stdin.fileno()
    old = termios.tcgetattr(fd)

    def restore(*_):
        sys.stdout.write("\x1b]2;\x07\x1b[?25h\x1b[?1049l")
        sys.stdout.flush()
        try: termios.tcsetattr(fd, termios.TCSADRAIN, old)
        except termios.error: pass

    def bye(*_):
        restore(); os._exit(0)

    signal.signal(signal.SIGTERM, bye)
    signal.signal(signal.SIGHUP, bye)
    tick, last_full, last_frame, last_title = 0, time.time(), [], None
    try:
        tty.setcbreak(fd)
        sys.stdout.write("\x1b[?1049h\x1b[?25l")
        while True:
            size = shutil.get_terminal_size((80, 24))
            t.w, t.h = max(50, min(size.columns, 120)), size.lines
            body, foot = compose(t, st, tab, tick)
            room = t.h - len(foot)
            frame = [clip(ln, t.w) for ln in (body[:room] + [""] * max(0, room - len(body)))] + foot
            pr = read_progress()
            title = "MJ · rendering %s" % (("%d%%" % round(pr["percent"])) if pr and pr.get("percent") is not None else "…") if pr else "MJ"
            if title != last_title:
                sys.stdout.write("\x1b]2;%s\x07" % title)
                last_title = title
            if frame != last_frame:
                sys.stdout.write("\x1b[H" + "\n".join("\x1b[2K" + ln for ln in frame[:t.h]))
                sys.stdout.flush()
                last_frame = frame
            r, _, _ = select.select([sys.stdin], [], [], 0.1)
            tick += 1
            if r:
                ch = os.read(fd, 8).decode("utf-8", "ignore")
                if ch in ("q", "Q", "\x03", "\x04"):
                    break
                if ch in ("1", "2", "3", "4"):
                    tab = TABS[int(ch) - 1]
                elif ch == "\t" or ch == "\x1b[C":
                    tab = TABS[(TABS.index(tab) + 1) % len(TABS)]
                elif ch == "\x1b[D":
                    tab = TABS[(TABS.index(tab) - 1) % len(TABS)]
                elif ch in ("r", "R"):
                    st.refresh_async(pool)
                    last_full = time.time()
            if time.time() - last_full > 10 and not st.loading:
                st.refresh_async(pool, ("library", "audit"))
                last_full = time.time()
    finally:
        restore()
        pool.shutdown(wait=False)
    return 0


def status_line(t):
    """One short line from files only (no runtime calls), fast enough for a shell prompt."""
    pr = read_progress()
    if pr:
        pct = ("%d%%" % round(pr["percent"])) if pr.get("percent") is not None else "%d frames" % pr["frames"]
        return "MJ %s rendering %s %s eta %s" % (t.g["dot"], pr["label"], pct, hms(pr.get("etaSeconds"))), "run"
    hist = read_jsonl_tail(os.path.join(STORE, "renders.jsonl"), 1)
    if hist:
        h = hist[-1]
        mark, kind = (t.g["ok"], "ok") if h["status"] == "complete" else (t.g["bad"], "bad")
        return "MJ %s last render %s %s %s" % (mark, h["label"].split(".")[0], h["status"], ago(h["endedAt"])), kind
    return "MJ %s idle" % t.g["off"], "off"


def main(argv):
    mode = argv[1] if len(argv) > 1 else "home"
    opts = argv[2:]
    plain = "--plain" in opts or os.environ.get("MJ_PLAIN") == "1"
    def val(flag):
        return int(opts[opts.index(flag) + 1]) if flag in opts else None
    t = Term(plain=plain, width=val("--width"), height=val("--height"), anim="--no-anim" not in opts)
    if mode == "home":
        run_home(t); return 0
    if mode == "status":
        line, kind = status_line(t)
        if "--swiftbar" in opts:
            print(line); print("---")
            if kind == "run":
                pr = read_progress()
                if pr: print(progress_text(pr))
        else:
            print(line)
        return 0
    if mode == "ui":
        tab = opts[opts.index("--tab") + 1] if "--tab" in opts else "overview"
        if tab not in TABS:
            print("mj ui: unknown tab %s (overview, renders, library, audit)" % tab, file=sys.stderr); return 64
        once = "--once" in opts or not (sys.stdin.isatty() and sys.stdout.isatty())
        return run_ui(t, tab, once)
    print("usage: mj_ui.py home|ui [options]", file=sys.stderr)
    return 64


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv))
    except KeyboardInterrupt:
        sys.stdout.write("\x1b[?25h\x1b[?1049l")
        sys.exit(130)
    except BrokenPipeError:        # e.g. `mj | head`
        try: sys.stdout.close()
        except Exception: pass
        os._exit(0)
