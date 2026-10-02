#!/bin/zsh -f
# MographJailed Tier 0 Observer Dashboard — a btop-style live terminal view.
#
# STRICTLY READ-ONLY (Tier 0): this dashboard only reads snapshot versions,
# scrape receipts, and watcher logs. It never modifies AE projects and never
# writes outside temp request files it deletes immediately.
#
# Usage:
#   tools/mj-observe-dash.zsh [--versions ~/AE_Versions] [--receipts ~/AE_Receipts]
#   (folders and --cli can be remembered once with:  mj config set versions_dir ~/AE_Versions)
#                             [--cli dist/mograph-jailed.zsh] [--interval 5] [--once | --json]
#
# Keys: q quit · r refresh now. --once renders a single frame (scripting).
# --json prints the same data as one JSON document (implies --once); --ticks N
# (for tests) collects N times first, exercising the receipt cache.

emulate -R zsh
set -u

ROOT=$(cd "$(dirname "$0")/.." && pwd)
VERSIONS_DIR=""
RECEIPTS_DIR=""
CLI_PATH="$ROOT/dist/mograph-jailed.zsh"
INTERVAL=5
ONCE=0
JSON=0
TICKS=1
CLI_FROM_FLAG=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --versions) VERSIONS_DIR="$2"; shift 2 ;;
    --receipts) RECEIPTS_DIR="$2"; shift 2 ;;
    --cli) CLI_PATH="$2"; CLI_FROM_FLAG=1; shift 2 ;;
    --interval) INTERVAL="$2"; shift 2 ;;
    --once) ONCE=1; shift ;;
    --json) JSON=1; ONCE=1; shift ;;
    --ticks) TICKS="$2"; shift 2 ;;
    -h|--help) sed -n '2,18p' "$0"; exit 0 ;;
    *) print -u2 "unknown arg: $1"; exit 2 ;;
  esac
done

# Remembered settings: flag > environment > config file (mj config) > default.
[[ -r "$ROOT/scripts/shell/mj-config.zsh" ]] && source "$ROOT/scripts/shell/mj-config.zsh"
if (( $+functions[mj_config_get] )); then
  [[ -n "$VERSIONS_DIR" ]] || VERSIONS_DIR=$(mj_config_get versions_dir)
  [[ -n "$RECEIPTS_DIR" ]] || { RECEIPTS_DIR=$(mj_config_get receipts_dir); [[ -d "$RECEIPTS_DIR" ]] || RECEIPTS_DIR=""; }
  if (( ! CLI_FROM_FLAG )); then
    _cfg=$(_mj_config_resolve cli); [[ "${_cfg##*	}" == default ]] || CLI_PATH="${_cfg%%	*}"
  fi
fi
if [[ -z "$VERSIONS_DIR" ]]; then
  print -u2 "mj-observe-dash: no versions folder. Pass --versions DIR, or set it once:  mj config set versions_dir ~/AE_Versions"
  exit 2
fi
if [[ ! -d "$VERSIONS_DIR" ]]; then
  print -u2 "mj-observe-dash: versions folder not found: $VERSIONS_DIR"
  print -u2 "  Pass --versions DIR, or set it once:  mj config set versions_dir <folder>"
  exit 2
fi
if [[ ! -x "$CLI_PATH" ]]; then
  print -u2 "mj-observe-dash: CLI not executable: $CLI_PATH (use --cli)"
  exit 2
fi

export MJ_DASH_VERSIONS="$VERSIONS_DIR"
export MJ_DASH_RECEIPTS="$RECEIPTS_DIR"
export MJ_DASH_CLI="$CLI_PATH"
export MJ_DASH_INTERVAL="$INTERVAL"
export MJ_DASH_ONCE="$ONCE"
export MJ_DASH_JSON="$JSON"
export MJ_DASH_TICKS="$TICKS"

/usr/bin/python3 - "$@" <<'PY_DASH'
import json, os, sys, time, shutil, subprocess, tempfile, select, termios, tty

VERSIONS = os.environ["MJ_DASH_VERSIONS"]
RECEIPTS = os.environ.get("MJ_DASH_RECEIPTS") or ""
CLI = os.environ["MJ_DASH_CLI"]
INTERVAL = int(os.environ.get("MJ_DASH_INTERVAL", "5"))
ONCE = os.environ.get("MJ_DASH_ONCE") == "1"
JSON_OUT = os.environ.get("MJ_DASH_JSON") == "1"
TICKS = max(1, int(os.environ.get("MJ_DASH_TICKS", "1")))
# Receipt ingest cache: re-run project.ingest / expression.lint only when the newest
# receipt changes (path, size, mtime), including when it failed, so a bad receipt is not
# re-parsed every refresh.
_RECEIPT_CACHE = {"key": None, "summary": None, "lint": None, "error": None}
INGEST_CALLS = 0

# ---------- palette (btop-ish, dark) ----------
ESC = "\x1b["
RESET = ESC + "0m"
BOLD = ESC + "1m"
DIM = ESC + "2m"
FG = {
    "cyan": ESC + "38;5;51m", "teal": ESC + "38;5;37m",
    "green": ESC + "38;5;42m", "yellow": ESC + "38;5;221m",
    "red": ESC + "38;5;203m", "magenta": ESC + "38;5;213m",
    "white": ESC + "38;5;255m", "grey": ESC + "38;5;245m",
    "dark": ESC + "38;5;238m",
}
BG_BAR = ESC + "48;5;236m"

def disp_width(s):
    # Terminal cell width: East Asian Wide/Fullwidth count as 2, all else 1.
    # Matches the common Western-locale rendering of box-drawing/ambiguous chars.
    import unicodedata
    w = 0
    for ch in s:
        w += 2 if unicodedata.east_asian_width(ch) in ("W", "F") else 1
    return w

def strip_ansi(s):
    import re
    return re.sub(r"\x1b\[[0-9;]*m", "", s)

SPARKS = "▁▂▃▄▅▆▇█"

def cli_request(command, args):
    """Fire one CLI request via a temp file; always cleans up. Read-only ops only."""
    assert command in ("project.ingest", "expression.lint"), "dashboard may only fire Tier 0 reads"
    fd, req = tempfile.mkstemp(prefix="mjdash-", suffix=".txt", dir="/tmp")
    try:
        with os.fdopen(fd, "w") as f:
            f.write("MOGRAPHJAILED_REQUEST 1\n")
            f.write("requestId=dash-%d\n" % int(time.time() * 1000))
            f.write("command=%s\n" % command)
            for k, v in args.items():
                import base64
                f.write("arg.%s=%s\n" % (k, base64.b64encode(v.encode()).decode()))
        p = subprocess.run([CLI, "--request", req], capture_output=True, text=True, timeout=30)
        try:
            return json.loads(p.stdout)
        except Exception:
            return {"ok": False}
    finally:
        try: os.unlink(req)
        except OSError: pass

def collect():
    data = {"projects": [], "summary": None, "lint": None,
            "watcher": {"loaded": False, "tail": []}, "receipt": None}
    # --- snapshots: one row per project ---
    # Primary index: *.latest.json (written by project.snapshot).
    # Fallback: group snapshot-named *.aep files (<stem>.<ts>.<hash>.aep).
    import re
    snap_re = re.compile(r"^(.*)\.\d{8}T\d{6}Z\.[0-9a-f]{12}\.(aep|c4d)$")
    if os.path.isdir(VERSIONS):
        indexed = {}
        for fn in sorted(os.listdir(VERSIONS)):
            if not fn.endswith(".latest.json"):
                continue
            stem = fn[:-len(".latest.json")]
            try:
                with open(os.path.join(VERSIONS, fn)) as f:
                    doc = json.load(f)
                latest = doc.get("data") or doc      # project.snapshot writes the latest pointer unwrapped
            except Exception:
                latest = {}
            indexed[stem] = latest.get("sourcePath", "")
        groups = {}
        for g in sorted(os.listdir(VERSIONS)):
            if not (g.endswith(".aep") or g.endswith(".c4d")) or g.endswith(".snapshot.json"):
                continue
            m = snap_re.match(g)
            if not m:
                continue
            stem = m.group(1) + (".c4d" if m.group(2) == "c4d" else "")     # matches the pointer name Foo.c4d.latest.json
            p = os.path.join(VERSIONS, g)
            try:
                st = os.stat(p)
            except OSError:
                continue
            groups.setdefault(stem, []).append((st.st_mtime, st.st_size, g))
        for stem, snaps in groups.items():
            snaps.sort()
            total = sum(s for _, s, _ in snaps)
            data["projects"].append({
                "name": stem,
                "count": len(snaps),
                "bytes": total,
                "latest_mtime": snaps[-1][0] if snaps else 0,
                "latest_file": snaps[-1][2] if snaps else "",
                "sizes": [s for _, s, _ in snaps[-24:]],
                "project_path": indexed.get(stem, ""),
            })
        data["projects"].sort(key=lambda r: r["latest_mtime"], reverse=True)
        # watcher log tail
        logp = os.path.join(VERSIONS, "watcher.log")
        if os.path.isfile(logp):
            try:
                with open(logp, errors="replace") as f:
                    lines = f.read().splitlines()
                data["watcher"]["tail"] = lines[-3:]
            except OSError:
                pass
    # --- watcher launchd state (macOS) ---
    try:
        p = subprocess.run(["/bin/launchctl", "list"], capture_output=True, text=True, timeout=5)
        data["watcher"]["loaded"] = "com.neuralio.mograph-jailed.watcher" in p.stdout
    except Exception:
        pass
    # --- newest scrape receipt -> ingest + lint ---
    if RECEIPTS and os.path.isdir(RECEIPTS):
        best, best_mtime = None, 0
        for fn in os.listdir(RECEIPTS):
            if fn.endswith(".scrape.json"):
                p = os.path.join(RECEIPTS, fn)
                try:
                    m = os.stat(p).st_mtime
                except OSError:
                    continue
                if m > best_mtime:
                    best, best_mtime = p, m
        if best:
            data["receipt"] = os.path.basename(best)
            try:
                st = os.stat(best)
                key = (best, st.st_size, st.st_mtime_ns)
            except OSError:
                key = None
            if key is None or key != _RECEIPT_CACHE["key"]:
                global INGEST_CALLS
                INGEST_CALLS += 1
                c = {"key": key, "summary": None, "lint": None, "error": None}
                r = cli_request("project.ingest", {"path": best})
                if r.get("ok"):
                    c["summary"] = r["data"]
                else:
                    c["error"] = (r.get("error") or {}).get("code", "INGEST_FAILED")
                r = cli_request("expression.lint", {"path": best})
                if r.get("ok"):
                    c["lint"] = r["data"]
                _RECEIPT_CACHE.update(c)
            if _RECEIPT_CACHE["summary"] is not None:
                data["summary"] = _RECEIPT_CACHE["summary"]
            if _RECEIPT_CACHE["error"]:
                data["receipt_error"] = _RECEIPT_CACHE["error"]
            if _RECEIPT_CACHE["lint"] is not None:
                data["lint"] = _RECEIPT_CACHE["lint"]
    return data

def human_bytes(n):
    for unit in ("B", "KB", "MB", "GB"):
        if n < 1024 or unit == "GB":
            return ("%.0f%s" % (n, unit)) if unit == "B" else ("%.1f%s" % (n, unit))
        n /= 1024.0

def ago(ts):
    if not ts:
        return "—"
    d = int(time.time() - ts)
    if d < 60: return "%ds ago" % d
    if d < 3600: return "%dm ago" % (d // 60)
    if d < 86400: return "%dh ago" % (d // 3600)
    return "%dd ago" % (d // 86400)

def sparkline(vals, width):
    if not vals:
        return DIM + "·" * width + RESET
    mx = max(vals) or 1
    out = []
    for v in vals[-width:]:
        out.append(SPARKS[min(7, int(v / mx * 7))])
    return "".join(out)

def bar(frac, width):
    frac = max(0.0, min(1.0, frac))
    full = int(frac * width)
    return FG["green"] + "█" * full + FG["dark"] + "░" * (width - full) + RESET

def hline(width, left="├", right="┤", title=""):
    if title:
        t = " %s " % title
        fill = width - disp_width(left) - disp_width(right) - disp_width(strip_ansi(t))
        return FG["dark"] + left + "─" * 2 + FG["teal"] + BOLD + t + FG["dark"] + "─" * max(0, fill - 2) + right + RESET
    return FG["dark"] + left + "─" * max(0, width - disp_width(left) - disp_width(right)) + right + RESET

def render(d, W, H):
    L = []
    def pad(s, w):
        # pad by display cells, not codepoints, so wide chars stay aligned
        plain = strip_ansi(s)
        return s + " " * max(0, w - disp_width(plain))
    inner = W - 2
    # header
    L.append(FG["dark"] + "╭" + "─" * inner + "╮" + RESET)
    clock = time.strftime("%H:%M:%S")
    title = "%s%s MOGRAPHJAILED %s·%s TIER 0 OBSERVER " % (BOLD, FG["cyan"], FG["grey"], FG["cyan"])
    badge = "%s%s READ-ONLY %s" % (FG["dark"], BG_BAR, RESET)
    L.append("│" + pad(title + badge, inner - disp_width(strip_ansi(clock))) + FG["grey"] + clock + RESET + "│")
    L.append(hline(W, "├", "┤", "PROJECT SNAPSHOTS (%d)" % len(d["projects"])))
    if not d["projects"]:
        L.append("│" + pad(DIM + "  no snapshots yet — run project.snapshot or install the watcher" + RESET, inner) + "│")
    else:
        maxb = max((p["bytes"] for p in d["projects"]), default=1)
        for p in d["projects"][:max(1, H // 3)]:
            nm = (p["name"][:28] + "…") if len(p["name"]) > 29 else p["name"]
            row = "  %s%-29s%s %s %4d snaps  %8s  %s" % (
                FG["white"] + BOLD, nm, RESET,
                bar(p["bytes"] / maxb, 12), p["count"],
                human_bytes(p["bytes"]), FG["grey"] + ago(p["latest_mtime"]) + RESET)
            L.append("│" + pad(row, inner) + "│")
            if inner > 78:
                L.append("│" + pad("  " + DIM + "▸ " + sparkline(p["sizes"], 24) +
                                   "  " + (p["latest_file"][-40:]) + RESET, inner) + "│")
    L.append(hline(W, "├", "┤", "PROJECT VITALS"))
    s = d.get("summary")
    if not s:
        if d.get("receipt"):
            msg = "receipt %s failed validation (%s)" % (d["receipt"], d.get("receipt_error", "?"))
        else:
            msg = "no scrape receipts" + ("" if RECEIPTS else " (--receipts not given)")
            msg += " — run the AE scraper, then point --receipts at the folder"
        L.append("│" + pad(DIM + "  %s" % msg + RESET, inner) + "│")
    else:
        stats = [("comps", s.get("numComps", 0), "cyan"), ("layers", s.get("numLayers", 0), "teal"),
                 ("exprs", s.get("numExpressions", 0), "magenta"), ("effects", s.get("numEffects", 0), "yellow"),
                 ("fonts", s.get("numFonts", 0), "green"), ("footage", s.get("numFootage", 0), "white")]
        row = "  "
        for name, val, col in stats:
            row += "%s%4d%s %s  " % (FG[col] + BOLD, val, RESET, DIM + name + RESET)
        L.append("│" + pad(row, inner) + "│")
        miss = s.get("footageMissing", []) or []
        unl = s.get("footageUnlinked", []) or []
        flags = []
        if miss: flags.append("%s⚠ missing footage: %s%s" % (FG["red"], ", ".join(miss[:3]), RESET))
        if unl: flags.append("%s⚠ unlinked: %s%s" % (FG["yellow"], ", ".join(unl[:3]), RESET))
        if s.get("compsTruncated"): flags.append(DIM + "comps truncated" + RESET)
        if s.get("footageTruncated"): flags.append(DIM + "footage truncated" + RESET)
        if flags:
            L.append("│" + pad("  " + "   ".join(flags), inner) + "│")
        if d.get("receipt"):
            L.append("│" + pad(DIM + "  receipt: " + d["receipt"] + RESET, inner) + "│")
    L.append(hline(W, "├", "┤", "EXPRESSION LINT"))
    li = d.get("lint")
    if not li:
        L.append("│" + pad(DIM + "  no lint data — needs a scrape receipt" + RESET, inner) + "│")
    else:
        e, w, i = li.get("errors", 0), li.get("warnings", 0), li.get("info", 0)
        tot = max(1, e + w + i)
        row = "  %s●%s %d errors   %s●%s %d warnings   %s●%s %d info" % (
            FG["red"], RESET, e, FG["yellow"], RESET, w, FG["cyan"], RESET, i)
        row += "   " + bar(e / tot, 8) + " " + bar(w / tot, 8)
        L.append("│" + pad(row, inner) + "│")
        shown = 0
        for f in li.get("findings", []):
            if shown >= 3 or len(L) > H - 8:
                break
            col = {"error": "red", "warning": "yellow"}.get(f.get("severity"), "cyan")
            msg = f.get("message", "")[: inner - 22]
            L.append("│" + pad("  %s%s%s %s· %s" % (FG[col], f.get("code"), RESET, DIM + f.get("layer", "") + RESET, msg), inner) + "│")
            shown += 1
    L.append(hline(W, "├", "┤", "WATCHER"))
    wstate = d["watcher"]
    dot = FG["green"] + "●" + RESET if wstate["loaded"] else FG["dark"] + "○" + RESET
    L.append("│" + pad("  %s launchd agent %s" % (dot, "loaded" if wstate["loaded"] else "not loaded"), inner) + "│")
    for t in wstate["tail"]:
        L.append("│" + pad(DIM + "  " + t[-(inner - 4):] + RESET, inner) + "│")
    L.append(FG["dark"] + "╰" + "─" * inner + "╯" + RESET)
    L.append(pad(DIM + " q quit · r refresh · Tier 0: observes only, changes nothing" + RESET, W))
    return "\n".join(L[:H])

def main():
    if not os.path.isdir(VERSIONS):
        sys.stderr.write("mj-observe-dash: versions dir not found: %s\n" % VERSIONS)
        sys.exit(2)
    if ONCE:
        for _ in range(TICKS):
            data = collect()
        if JSON_OUT:
            data["schema"] = "MJ_OBSERVE_DASH_1"
            data["generatedAt"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
            data["ingestCalls"] = INGEST_CALLS
            sys.stdout.write(json.dumps(data, sort_keys=True, indent=1) + "\n")
            return
        W, H = shutil.get_terminal_size((100, 30))
        sys.stdout.write(render(data, W, H) + "\n")
        return
    # interactive loop
    fd = sys.stdin.fileno()
    old = termios.tcgetattr(fd)
    try:
        tty.setcbreak(fd)
        sys.stdout.write(ESC + "?1049h" + ESC + "?25l")  # alt screen, hide cursor
        last = 0
        data = None
        while True:
            now = time.time()
            if data is None or now - last >= INTERVAL:
                data = collect()
                last = now
            W, H = shutil.get_terminal_size((100, 30))
            sys.stdout.write(ESC + "H" + ESC + "2J" + render(data, W, H))
            sys.stdout.flush()
            r, _, _ = select.select([sys.stdin], [], [], 0.5)
            if r:
                ch = sys.stdin.read(1)
                if ch in ("q", "Q", "\x03"):
                    break
                if ch in ("r", "R"):
                    data = None
    finally:
        termios.tcsetattr(fd, termios.TCSADRAIN, old)
        sys.stdout.write(ESC + "?25h" + ESC + "?1049l")
        sys.stdout.flush()

main()
PY_DASH
