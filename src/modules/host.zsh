# Host applications — After Effects and Cinema 4D (Power CLI Phases 0-1).
#
# host.detect — installed AE / C4D (2024+), their CLIs, Redshift, macOS, GPU; read-only
# ae.render   — aerender one comp to a new PNG-sequence folder with a receipt
# c4d.render  — C4D Commandline render to a new PNG-sequence folder with a receipt
#
# Hosts are discovered only under MJ_HOST_APPS_DIR (/Applications); no host path
# is ever taken from a request. Renders run one at a time (one GPU, one licence),
# with stdin closed, a hard timeout, process-group kill, and licence-prompt
# detection so an unlicensed host fails fast instead of hanging.

IFS= read -r -d '' MJ_PY_HOST_LIB <<'PY_HOST_LIB' || true
import plistlib, selectors, signal

AE_RE = re.compile(r"^Adobe After Effects (\d{4})$")
C4D_RE = re.compile(r"^Maxon Cinema 4D (\d{4})$")
LICENCE_MARKERS = ("Enter the license method", "Please select:", "No valid license", "license could not be")

def plist_version(app):
    try:
        with open(os.path.join(app, "Contents", "Info.plist"), "rb") as f:
            return str(plistlib.load(f).get("CFBundleShortVersionString") or "")
    except Exception:
        return ""

def is_exec(p):
    return os.path.isfile(p) and os.access(p, os.X_OK)

def discover(apps_dir, min_year):
    ae, c4d = [], []
    try:
        names = sorted(os.listdir(apps_dir))
    except OSError:
        names = []
    for name in names:
        root = os.path.join(apps_dir, name)
        m = AE_RE.match(name)
        if m and os.path.isdir(root):
            year = int(m.group(1))
            app = os.path.join(root, "%s.app" % name)
            aerender = os.path.join(root, "aerender")
            complete = os.path.isdir(app) and is_exec(aerender)
            ae.append({"year": year, "path": root, "app": app if os.path.isdir(app) else None,
                       "version": plist_version(app), "aerender": aerender if is_exec(aerender) else None,
                       "complete": complete, "supported": complete and year >= min_year})
        m = C4D_RE.match(name)
        if m and os.path.isdir(root):
            year = int(m.group(1))
            app = os.path.join(root, "Cinema 4D.app")
            c4dpy = os.path.join(root, "c4dpy.app", "Contents", "MacOS", "c4dpy")
            cmdline = os.path.join(root, "Commandline.app", "Contents", "MacOS", "Commandline")
            complete = os.path.isdir(app) and is_exec(cmdline)
            c4d.append({"year": year, "path": root, "app": app if os.path.isdir(app) else None,
                        "version": plist_version(app), "c4dpy": c4dpy if is_exec(c4dpy) else None,
                        "commandline": cmdline if is_exec(cmdline) else None,
                        "redshift": os.path.isfile(os.path.join(root, "corelibs", "redshift.xlib")),
                        "complete": complete, "supported": complete and year >= min_year})
    return ae, c4d

def pick_host(hosts, year):
    usable = [h for h in hosts if h["supported"]]
    if year:
        usable = [h for h in usable if h["year"] == year]
    if not usable:
        err("HOST_NOT_FOUND", "No supported installation found%s." % (" for %d" % year if year else ""))
    return max(usable, key=lambda h: h["year"])

def render_lock(store):
    """One render at a time. A lock whose owner process is gone is reclaimed."""
    lock = os.path.join(store, "locks", "render.lock")
    os.makedirs(os.path.dirname(lock), mode=0o700, exist_ok=True)
    for _ in range(2):
        try:
            os.mkdir(lock)
            with open(os.path.join(lock, "pid"), "w") as f:
                f.write(str(os.getpid()))
            return lock
        except FileExistsError:
            try:
                pid = int(open(os.path.join(lock, "pid")).read().strip())
                os.kill(pid, 0)
                err("RENDER_BUSY", "Another render is running (pid %d). Renders run one at a time." % pid)
            except (ValueError, FileNotFoundError, ProcessLookupError):
                shutil.rmtree(lock, ignore_errors=True)
            except PermissionError:
                err("RENDER_BUSY", "Another render is running. Renders run one at a time.")
    err("RENDER_BUSY", "Could not take the render lock.")

def reserve_job_dir(outdir, label):
    base = os.path.join(outdir, "%s.%s" % (label, utc_stamp()))
    for n in range(1, 100):
        d = base if n == 1 else "%s-%d" % (base, n)
        try:
            os.mkdir(d)
            return d
        except FileExistsError:
            continue
    err("OUTPUT_EXISTS", "Could not reserve a new render folder.")

def run_guarded(argv, log_path, timeout, on_tick=None):
    """Run a host CLI: no stdin, own process group, streamed log, hard timeout,
    licence-prompt detection. Returns (status, exit_code, tail_lines)."""
    started = time.time()
    last_tick = 0.0
    tail, window = [], ""
    with open(log_path, "wb") as log:
        p = subprocess.Popen(argv, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                             stderr=subprocess.STDOUT, start_new_session=True)
        sel = selectors.DefaultSelector()
        sel.register(p.stdout, selectors.EVENT_READ)
        status = None
        while True:
            left = timeout - (time.time() - started)
            if left <= 0:
                status = "timeout"; break
            if on_tick and time.time() - last_tick >= 0.5:
                last_tick = time.time()
                on_tick()
            if not sel.select(timeout=min(left, 1.0)):
                if p.poll() is not None:
                    break
                continue
            chunk = os.read(p.stdout.fileno(), 65536)
            if not chunk:
                break
            log.write(chunk); log.flush()
            text = chunk.decode("utf-8", "replace")
            window = (window + text)[-4096:]
            tail = (tail + text.splitlines())[-25:]
            if any(m in window for m in LICENCE_MARKERS):
                status = "licence"; break
        if status:
            try:
                os.killpg(p.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
        p.wait()
    return status or ("finished" if p.returncode == 0 else "failed"), p.returncode, tail

def parse_range(text):
    if not text:
        return None
    m = re.match(r"^(\d{1,7})-(\d{1,7})$", text)
    if not m or int(m.group(1)) > int(m.group(2)):
        err("INVALID_ARGUMENT", "range must look like START-END with START <= END.")
    return int(m.group(1)), int(m.group(2))

def frame_summary(job, rng):
    frames = sorted(n for n in os.listdir(job) if n.lower().endswith(".png") and not n.startswith("."))
    out = {"count": len(frames), "expected": (rng[1] - rng[0] + 1) if rng else None,
           "first": frames[0] if frames else None, "last": frames[-1] if frames else None}
    out["firstSha256"] = sha256_file(os.path.join(job, frames[0])) if frames else None
    out["lastSha256"] = sha256_file(os.path.join(job, frames[-1])) if frames else None
    return out

def progress_writer(store, job, host, label, rng):
    """Returns a tick() that records how many frames exist so far. Counting finished PNGs is
    host-independent: it needs nothing from the host's own output format."""
    path = os.path.join(store, "render-progress.json")
    t0 = time.time()
    total = (rng[1] - rng[0] + 1) if rng else None
    def tick():
        try:
            done = sum(1 for n in os.listdir(job) if n.lower().endswith(".png") and not n.startswith("."))
        except OSError:
            return
        el = time.time() - t0
        rate = done / el if done and el > 0 else 0.0
        eta = (total - done) / rate if total and rate and done < total else None
        doc = {"host": host, "label": label, "outputDir": job, "pid": os.getpid(), "startedAt": now_iso(),
               "elapsed": round(el, 1), "frames": done, "total": total,
               "percent": round(100.0 * done / total, 1) if total else None,
               "fps": round(rate, 2), "etaSeconds": round(eta) if eta is not None else None}
        tmp = path + ".%d" % os.getpid()
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(doc, f)
        os.replace(tmp, path)
    return tick

def clear_progress(store):
    try:
        os.unlink(os.path.join(store, "render-progress.json"))
    except OSError:
        pass

def write_last_render(store, receipt):
    """Pointer for `mj last` / `mj open-last`; replaced atomically, never a render output."""
    tmp = os.path.join(store, ".last-render.json.%d" % os.getpid())
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump({"receiptPath": receipt["receiptPath"], "outputDir": receipt["outputDir"],
                   "status": receipt["status"], "host": receipt["host"], "endedAt": receipt["endedAt"]}, f)
    os.replace(tmp, os.path.join(store, "last-render.json"))
    # Append-only history for the dashboard (one short JSON object per line).
    with open(os.path.join(store, "renders.jsonl"), "a", encoding="utf-8") as f:
        f.write(json.dumps({"endedAt": receipt["endedAt"], "host": receipt["host"], "status": receipt["status"],
                            "label": os.path.basename(receipt["outputDir"]), "frames": receipt["frames"]["count"],
                            "expected": receipt["frames"]["expected"], "seconds": receipt["seconds"],
                            "receiptPath": receipt["receiptPath"]}, sort_keys=True) + "\n")

def finish_render(receipt, job, rng, status, code, tail, source_path, sha_before):
    sha_after = sha256_file(source_path)
    frames = frame_summary(job, rng)
    if status == "finished":
        status = "complete" if frames["count"] and (frames["expected"] in (None, frames["count"])) else "incomplete"
    receipt.update({
        "endedAt": now_iso(), "status": status, "exitCode": code, "frames": frames, "errorTail": tail[-10:],
        "source": {"path": source_path, "sha256Before": sha_before, "sha256After": sha_after,
                   "unchanged": sha_before == sha_after},
    })
    receipt["seconds"] = round(time.time() - receipt.pop("_t0"), 1)
    path = os.path.join(job, "render.json")
    with open(path, "w", encoding="utf-8") as f:
        json.dump(receipt, f, indent=1, sort_keys=True); f.write("\n")
    receipt["receiptPath"] = path
    write_last_render(os.environ["MJ_STORE"], receipt)
    codes = {"licence": ("LICENCE_NOT_CONFIGURED", "The host asked for a licence choice; run it once interactively to configure licensing."),
             "timeout": ("RENDER_TIMEOUT", "Render exceeded its time limit and was stopped."),
             "failed": ("RENDER_FAILED", "The host exited with an error."),
             "incomplete": ("RENDER_INCOMPLETE", "The host finished but frames are missing.")}
    if status in codes:
        code_name, msg = codes[status]
        err(code_name, "%s Receipt: %s" % (msg, path))
    if not receipt["source"]["unchanged"]:
        receipt["_warnings"] = [{"code": "SOURCE_CHANGED_DURING_RENDER", "message": "The project or scene file changed while it was rendering; the frames may mix two versions."}]
    print(json.dumps({"ok": True, "data": receipt}))
PY_HOST_LIB

host_python() {
  local _main=""
  IFS= read -r -d '' _main || true
  printf '%s\n%s\n%s\n%s' "$MJ_PY_PROTECT_LIB" "$MJ_PY_LIBRARY" "$MJ_PY_HOST_LIB" "$_main" | /usr/bin/python3 - 2>/dev/null
}

handle_host_detect() {
  local _out=""
  cap_available python3 || { set_error "UNSUPPORTED" "host.detect requires python3."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 69; }
  _out=$(MJ_APPS="$MJ_HOST_APPS_DIR" MJ_MIN_YEAR="$MJ_HOST_MIN_YEAR" host_python <<'PY_HOST_DETECT'
import platform
min_year = int(os.environ["MJ_MIN_YEAR"])
ae, c4d = discover(os.environ["MJ_APPS"], min_year)
gpu, gui = [], None
if sys.platform == "darwin":
    try:
        sp = subprocess.run(["/usr/sbin/system_profiler", "-json", "SPDisplaysDataType"],
                            capture_output=True, text=True, timeout=20).stdout
        for g in json.loads(sp).get("SPDisplaysDataType", []):
            gpu.append({"name": g.get("sppci_model") or g.get("_name"),
                        "metal": g.get("spdisplays_mtlgpufamilysupport"),
                        "cores": g.get("sppci_cores")})
    except Exception:
        pass
    try:
        import pwd
        gui = pwd.getpwuid(os.stat("/dev/console").st_uid).pw_name == pwd.getpwuid(os.getuid()).pw_name
    except Exception:
        gui = None
osver = platform.mac_ver()[0] if sys.platform == "darwin" else ""
print(json.dumps({"ok": True, "data": {
    "schema": "MJ_HOST_DETECT_1",
    "minimumYear": min_year,
    "macOS": {"version": osver, "arch": platform.machine()},
    "guiSession": gui,
    "gpu": gpu,
    "afterEffects": ae,
    "cinema4d": c4d,
    "ready": {"aeRender": any(h["supported"] for h in ae),
              "c4dRender": any(h["supported"] for h in c4d),
              "c4dHeadlessPython": any(h["supported"] and h["c4dpy"] for h in c4d)},
    "licence": "unverified",
    "notes": ["Licensing is only observed when a host runs; an unconfigured C4D licence surfaces as LICENCE_NOT_CONFIGURED.",
              "AE scripting (not used by renders) may additionally require macOS Automation permission."],
}}))
PY_HOST_DETECT
) || true
  frames_emit_python_result "$_out"
}

# Shared request validation for both render operations. Sets MJ_RENDER_* globals.
host_render_args() {
  local _ext="$1" _rc=0
  MJ_RENDER_SRC="" MJ_RENDER_OUT="" MJ_RENDER_LABEL="" MJ_RENDER_RANGE="" MJ_RENDER_TIMEOUT="" MJ_RENDER_YEAR=""
  require_arg path || return 65
  MJ_RENDER_SRC="$MJ_REQUIRED_ARG_VALUE"
  require_arg output || return 65
  MJ_RENDER_OUT="$MJ_REQUIRED_ARG_VALUE"
  require_arg label || return 65
  MJ_RENDER_LABEL="$MJ_REQUIRED_ARG_VALUE"
  library_label_ok "$MJ_RENDER_LABEL" || return 65
  is_absolute_path "$MJ_RENDER_SRC" || { set_error "INVALID_PATH" "Scene/project path must be absolute."; return 65; }
  [ -f "$MJ_RENDER_SRC" ] && [ -r "$MJ_RENDER_SRC" ] || { set_error "INVALID_TARGET" "Scene/project must be a readable file."; return 65; }
  case "${MJ_RENDER_SRC##*/}" in *."$_ext") ;; *) set_error "INVALID_TARGET" "Expected a .$_ext file."; return 65 ;; esac
  mj_require_local_existing_path "$MJ_RENDER_SRC" || return 73
  protect_require_output_dir "$MJ_RENDER_OUT" || return $?
  MJ_RENDER_OUT=$(canonical_existing_dir "$MJ_RENDER_OUT")
  request_arg_present range && MJ_RENDER_RANGE=$(request_arg_get range)
  frames_uint_arg timeoutSeconds 3600 10 86400 || return 65
  MJ_RENDER_TIMEOUT="$MJ_FRAMES_UINT"
  frames_uint_arg version 0 2024 2100 || return 65
  MJ_RENDER_YEAR="$MJ_FRAMES_UINT"
  library_require_store create || return $?
}

handle_ae_render() {
  local _rc=0 _comp="" _out=""
  host_render_args aep || { _rc=$?; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return $_rc; }
  require_arg target || { emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  _comp="$MJ_REQUIRED_ARG_VALUE"
  [ ${#_comp} -le 255 ] || { set_error "INVALID_ARGUMENT" "Comp name is too long."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }

  _out=$(MJ_APPS="$MJ_HOST_APPS_DIR" MJ_MIN_YEAR="$MJ_HOST_MIN_YEAR" MJ_STORE="$MJ_STORE" \
    MJ_SRC="$MJ_RENDER_SRC" MJ_OUT="$MJ_RENDER_OUT" MJ_LABEL="$MJ_RENDER_LABEL" MJ_COMP="$_comp" \
    MJ_RANGE="$MJ_RENDER_RANGE" MJ_TIMEOUT="$MJ_RENDER_TIMEOUT" MJ_YEAR="$MJ_RENDER_YEAR" host_python <<'PY_AE_RENDER'
rng = parse_range(os.environ["MJ_RANGE"])
ae, _ = discover(os.environ["MJ_APPS"], int(os.environ["MJ_MIN_YEAR"]))
host = pick_host(ae, int(os.environ["MJ_YEAR"]))
src, label = os.environ["MJ_SRC"], os.environ["MJ_LABEL"]
lock = render_lock(os.environ["MJ_STORE"])
try:
    sha_before = sha256_file(src)
    job = reserve_job_dir(os.environ["MJ_OUT"], label)
    # Output format is forced to a PNG sequence via -outputSettings, so no
    # install-specific output-module template name is needed. Never -reuse:
    # a fresh AE instance is launched and quits; changes are never saved.
    argv = [host["aerender"], "-project", src, "-comp", os.environ["MJ_COMP"],
            "-output", os.path.join(job, label + "_[#####].png"),
            "-outputSettings", "Format: PNG Sequence",
            "-close", "DO_NOT_SAVE_CHANGES", "-v", "ERRORS_AND_PROGRESS", "-sound", "OFF"]
    if rng:
        argv += ["-s", str(rng[0]), "-e", str(rng[1])]
    receipt = {"schema": "MJ_RENDER_1", "host": "afterEffects", "hostYear": host["year"],
               "hostVersion": host["version"], "binary": host["aerender"], "target": os.environ["MJ_COMP"],
               "range": list(rng) if rng else None, "outputDir": job, "argv": argv,
               "startedAt": now_iso(), "_t0": time.time(), "logPath": os.path.join(job, "render.log")}
    tick = progress_writer(os.environ["MJ_STORE"], job, "afterEffects", label, rng)
    tick()
    status, code, tail = run_guarded(argv, receipt["logPath"], int(os.environ["MJ_TIMEOUT"]), tick)
    clear_progress(os.environ["MJ_STORE"])
    finish_render(receipt, job, rng, status, code, tail, src, sha_before)
finally:
    clear_progress(os.environ["MJ_STORE"])
    shutil.rmtree(lock, ignore_errors=True)
PY_AE_RENDER
) || true
  frames_emit_python_result "$_out"
}

handle_c4d_render() {
  local _rc=0 _take="" _out=""
  host_render_args c4d || { _rc=$?; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return $_rc; }
  request_arg_present target && _take=$(request_arg_get target)
  [ ${#_take} -le 255 ] || { set_error "INVALID_ARGUMENT" "Take name is too long."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }

  _out=$(MJ_APPS="$MJ_HOST_APPS_DIR" MJ_MIN_YEAR="$MJ_HOST_MIN_YEAR" MJ_STORE="$MJ_STORE" \
    MJ_SRC="$MJ_RENDER_SRC" MJ_OUT="$MJ_RENDER_OUT" MJ_LABEL="$MJ_RENDER_LABEL" MJ_TAKE="$_take" \
    MJ_RANGE="$MJ_RENDER_RANGE" MJ_TIMEOUT="$MJ_RENDER_TIMEOUT" MJ_YEAR="$MJ_RENDER_YEAR" host_python <<'PY_C4D_RENDER'
rng = parse_range(os.environ["MJ_RANGE"])
_, c4d = discover(os.environ["MJ_APPS"], int(os.environ["MJ_MIN_YEAR"]))
host = pick_host(c4d, int(os.environ["MJ_YEAR"]))
src, label = os.environ["MJ_SRC"], os.environ["MJ_LABEL"]
lock = render_lock(os.environ["MJ_STORE"])
try:
    sha_before = sha256_file(src)
    job = reserve_job_dir(os.environ["MJ_OUT"], label)
    # Renders with the scene's own render settings (Redshift or Physical);
    # only image path and format are overridden. C4D appends frame numbers.
    argv = [host["commandline"], "-render", src, "-oimage", os.path.join(job, label + "_"), "-oformat", "PNG"]
    if rng:
        argv += ["-frame", str(rng[0]), str(rng[1])]
    if os.environ["MJ_TAKE"]:
        argv += ["-take", os.environ["MJ_TAKE"]]
    receipt = {"schema": "MJ_RENDER_1", "host": "cinema4d", "hostYear": host["year"],
               "hostVersion": host["version"], "binary": host["commandline"], "redshiftInstalled": host["redshift"],
               "target": os.environ["MJ_TAKE"] or None, "range": list(rng) if rng else None, "outputDir": job,
               "argv": argv, "startedAt": now_iso(), "_t0": time.time(), "logPath": os.path.join(job, "render.log")}
    tick = progress_writer(os.environ["MJ_STORE"], job, "cinema4d", label, rng)
    tick()
    status, code, tail = run_guarded(argv, receipt["logPath"], int(os.environ["MJ_TIMEOUT"]), tick)
    clear_progress(os.environ["MJ_STORE"])
    finish_render(receipt, job, rng, status, code, tail, src, sha_before)
finally:
    clear_progress(os.environ["MJ_STORE"])
    shutil.rmtree(lock, ignore_errors=True)
PY_C4D_RENDER
) || true
  frames_emit_python_result "$_out"
}
