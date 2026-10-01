# Frame-sequence intelligence over a local directory of PNG frames
# (AE/C4D render output). Built on the ImageStats signature engine.
#
# loop.seams     — rank start/end frame pairs for a seamless loop; read-only
# golden.record  — write a new golden-frame receipt (hashes + signatures); never overwrites
# golden.check   — compare a frame directory against a golden receipt; read-only

# Validate a local, readable frame directory. Sets MJ_FRAMES_DIR on success.
frames_require_dir() {
  local _dir="$1"
  MJ_FRAMES_DIR=""
  is_absolute_path "$_dir" || { set_error "INVALID_PATH" "Frame directory must be absolute."; return 65; }
  [ -d "$_dir" ] || { set_error "INVALID_TARGET" "Frame path must be a directory of PNG frames."; return 65; }
  [ -r "$_dir" ] && [ -x "$_dir" ] || { set_error "PERMISSION_DENIED" "Frame directory is not readable."; return 77; }
  cap_available python3 || { set_error "UNSUPPORTED" "Frame operations require python3."; return 69; }
  mj_require_local_existing_path "$_dir" || return 73
  MJ_FRAMES_DIR=$(canonical_existing_dir "$_dir") || { set_error "INVALID_TARGET" "Could not resolve frame directory."; return 65; }
}

# Map a python {"ok":false,"code":...} result to an error envelope, or print data.
frames_emit_python_result() {
  local _out="$1"
  local _data=""
  _data=$(project_emit_python_data "$_out") && {
    split_warnings "$_data"
    emit_success_start "$REQUEST_COMMAND" "$REQUEST_ID"
    printf '%s' "$MJ_DATA_JSON"
    emit_success_end
    return 0
  }
  MJ_FRAMES_ERR_CODE=$(printf '%s' "$_out" | /usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin).get("code","ENGINE_FAILED"))' 2>/dev/null || printf 'ENGINE_FAILED')
  MJ_FRAMES_ERR_MSG=$(printf '%s' "$_out" | /usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin).get("message","Frame engine failed."))' 2>/dev/null || printf 'Frame engine failed.')
  set_error "$MJ_FRAMES_ERR_CODE" "$MJ_FRAMES_ERR_MSG"
  emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"
  return 74
}

frames_uint_arg() {
  # $1 arg name, $2 default, $3 min, $4 max. Sets MJ_FRAMES_UINT (no subshell, so set_error survives).
  local _v="$2"
  if request_arg_present "$1"; then
    _v=$(request_arg_get "$1")
    case "$_v" in ''|*[!0-9]*) set_error "INVALID_ARGUMENT" "$1 must be a non-negative integer."; return 1 ;; esac
    [ ${#_v} -le 6 ] && [ "$_v" -ge "$3" ] && [ "$_v" -le "$4" ] || { set_error "INVALID_ARGUMENT" "$1 must be between $3 and $4."; return 1 ;}
  fi
  MJ_FRAMES_UINT="$_v"
}

handle_loop_seams() {
  local _rc=0 _max="" _min="" _out=""
  require_arg path || { emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  frames_require_dir "$MJ_REQUIRED_ARG_VALUE" || { _rc=$?; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return $_rc; }
  frames_uint_arg maxResults 5 1 50 || { emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  _max="$MJ_FRAMES_UINT"
  # minFrames 0 means "half the sequence"; long loops are what motion designers want.
  frames_uint_arg minFrames 0 0 100000 || { emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  _min="$MJ_FRAMES_UINT"

  _out=$(MJ_DIR="$MJ_FRAMES_DIR" MJ_MAX="$_max" MJ_MIN="$_min" image_sig_python <<'PY_LOOP_SEAMS'
def main():
    d = os.environ["MJ_DIR"]
    id0 = tree_id(d)
    try:
        names = list_frames(d)
        if len(names) < 3:
            print(error_json("INSUFFICIENT_FRAMES", "loop.seams needs at least 3 PNG frames.")); return
        n = len(names)
        min_len = int(os.environ["MJ_MIN"]) or max(2, n // 2)
        if min_len >= n:
            print(error_json("INVALID_ARGUMENT", "minFrames must be smaller than the frame count.")); return
        sigs, downscaled = signatures_for(d, names)
    except ValueError as e:
        code = str(e).split(":")[0]
        print(error_json(code if code in ("TOO_MANY_FRAMES", "DECODE_FAILED") else "STATS_FAILED", str(e))); return
    # ponytail: O(n^2) pair scan, fine to MJ_MAX_FRAMES; coarse-to-fine if renders get longer.
    pairs = []
    for s in range(n):
        for e in range(s + min_len, n):
            score, hs, gs = signature_score(sigs[s], sigs[e])
            pairs.append((score, e - s, s, e, hs, gs))
    pairs.sort(key=lambda p: (-p[0], -p[1], p[2]))
    # Suppress near-duplicates: (s, e) and (s+1, e+1) are the same seam.
    chosen = []
    for p in pairs:
        if any(abs(p[2] - c[2]) <= 2 and abs(p[3] - c[3]) <= 2 for c in chosen):
            continue
        chosen.append(p)
        if len(chosen) >= int(os.environ["MJ_MAX"]):
            break
    print(json.dumps({"ok": True, "data": {
        "schema": "MJ_LOOP_SEAMS_1",
        "path": d,
        "frameCount": n,
        "minFrames": min_len,
        "signatureDownscaled": downscaled,
        "candidates": [{
            "rank": i + 1,
            "startFrame": p[2], "endFrame": p[3], "lengthFrames": p[1],
            "startName": names[p[2]], "endName": names[p[3]],
            "score": p[0], "histogramSimilarity": p[4], "gridSimilarity": p[5],
        } for i, p in enumerate(chosen)],
        "note": "Loop plays startFrame..endFrame-1; endFrame should match startFrame.",
        "sourceUnchanged": tree_id(d) == id0,
    }}))

main()
PY_LOOP_SEAMS
) || true
  frames_emit_python_result "$_out"
}

handle_golden_record() {
  local _rc=0 _outdir="" _label="" _receipt="" _out=""
  require_arg path || { emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  frames_require_dir "$MJ_REQUIRED_ARG_VALUE" || { _rc=$?; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return $_rc; }
  require_arg output || { emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  _outdir="$MJ_REQUIRED_ARG_VALUE"
  require_arg label || { emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  _label="$MJ_REQUIRED_ARG_VALUE"
  case "$_label" in .*|*[!A-Za-z0-9._-]*) set_error "INVALID_ARGUMENT" "label may contain only letters, digits, dot, dash and underscore."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65 ;; esac
  [ ${#_label} -le 64 ] || { set_error "INVALID_ARGUMENT" "label must be at most 64 characters."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  is_absolute_path "$_outdir" || { set_error "INVALID_PATH" "Output directory must be absolute."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  [ -d "$_outdir" ] && [ -w "$_outdir" ] || { set_error "OUTPUT_UNAVAILABLE" "Golden output directory must exist and be writable."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 73; }
  mj_require_local_existing_path "$_outdir" || { emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 73; }
  _receipt="$(canonical_existing_dir "$_outdir")/$_label.golden.json"
  [ ! -e "$_receipt" ] && [ ! -L "$_receipt" ] || { set_error "OUTPUT_EXISTS" "Refusing to overwrite an existing golden receipt."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 73; }

  _out=$(MJ_DIR="$MJ_FRAMES_DIR" MJ_RECEIPT="$_receipt" MJ_LABEL="$_label" image_sig_python <<'PY_GOLDEN_RECORD'
import time
def main():
    d = os.environ["MJ_DIR"]
    id0 = tree_id(d)
    try:
        names = list_frames(d)
        if not names:
            print(error_json("INSUFFICIENT_FRAMES", "No PNG frames found.")); return
        sigs, downscaled = signatures_for(d, names)
        frames = [{"name": n, "sha256": sha256_file(os.path.join(d, n)),
                   "histogram": s["histogram"], "grid": s["grid"]} for n, s in zip(names, sigs)]
    except ValueError as e:
        print(error_json("STATS_FAILED", str(e))); return
    receipt = {
        "schema": "MJ_GOLDEN_1",
        "label": os.environ["MJ_LABEL"],
        "sourceDir": d,
        "createdAt": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "signatureDownscaled": downscaled,
        "signatureMaxEdge": SIG_MAX_EDGE,
        "frames": frames,
    }
    path = os.environ["MJ_RECEIPT"]
    try:
        # O_EXCL: never overwrite, even if a receipt appears after the shell check.
        fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o644)
    except FileExistsError:
        print(error_json("OUTPUT_EXISTS", "Refusing to overwrite an existing golden receipt.")); return
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        json.dump(receipt, f, sort_keys=True, separators=(",", ":"))
        f.write("\n")
    print(json.dumps({"ok": True, "data": {
        "schema": "MJ_GOLDEN_1", "label": receipt["label"], "receiptPath": path,
        "sourceDir": d, "frameCount": len(frames), "signatureDownscaled": downscaled,
        "sourceUnchanged": tree_id(d) == id0,
    }}))

main()
PY_GOLDEN_RECORD
) || true
  frames_emit_python_result "$_out"
}

handle_golden_check() {
  local _rc=0 _receipt="" _threshold="0.98" _out=""
  require_arg path || { emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  frames_require_dir "$MJ_REQUIRED_ARG_VALUE" || { _rc=$?; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return $_rc; }
  require_arg input || { emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  _receipt="$MJ_REQUIRED_ARG_VALUE"
  is_absolute_path "$_receipt" || { set_error "INVALID_PATH" "Golden receipt path must be absolute."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  [ -f "$_receipt" ] && [ -r "$_receipt" ] || { set_error "INVALID_TARGET" "Golden receipt must be a readable file."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  mj_require_local_existing_path "$_receipt" || { emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 73; }
  if request_arg_present threshold; then
    _threshold=$(request_arg_get threshold)
    case "$_threshold" in 0|1|0.[0-9]|0.[0-9][0-9]|0.[0-9][0-9][0-9]|0.[0-9][0-9][0-9][0-9]|1.0) ;; *) set_error "INVALID_ARGUMENT" "threshold must be a decimal between 0 and 1 (up to 4 places)."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65 ;; esac
  fi

  _out=$(MJ_DIR="$MJ_FRAMES_DIR" MJ_RECEIPT="$_receipt" MJ_THRESHOLD="$_threshold" image_sig_python <<'PY_GOLDEN_CHECK'
def main():
    d = os.environ["MJ_DIR"]
    id0 = tree_id(d)
    threshold = float(os.environ["MJ_THRESHOLD"])
    try:
        if os.path.getsize(os.environ["MJ_RECEIPT"]) > 67108864:
            raise ValueError("too large")
        with open(os.environ["MJ_RECEIPT"], encoding="utf-8") as f:
            golden = json.load(f)
        assert golden.get("schema") == "MJ_GOLDEN_1" and isinstance(golden.get("frames"), list)
        recorded = {fr["name"]: fr for fr in golden["frames"]}
    except Exception:
        print(error_json("INVALID_RECEIPT", "Input is not a valid MJ_GOLDEN_1 receipt.")); return
    try:
        names = list_frames(d)
        present = [n for n in names if n in recorded]
        hashes = {n: sha256_file(os.path.join(d, n)) for n in present}
        # Only frames whose bytes changed need a signature.
        changed = [n for n in present if hashes[n] != recorded[n].get("sha256")]
        sigs, downscaled = signatures_for(d, changed)
    except ValueError as e:
        print(error_json("STATS_FAILED", str(e))); return
    sig_by_name = dict(zip(changed, sigs))
    results = []
    for n in sorted(recorded):
        if n not in hashes:
            results.append({"name": n, "status": "missing", "score": None}); continue
        if n not in sig_by_name:
            results.append({"name": n, "status": "identical", "score": 1.0}); continue
        score, hs, gs = signature_score(sig_by_name[n], recorded[n])
        results.append({"name": n, "status": "pass" if score >= threshold else "changed",
                        "score": score, "histogramSimilarity": hs, "gridSimilarity": gs})
    extra = [n for n in names if n not in recorded]
    scores = [r["score"] for r in results if r["score"] is not None]
    failed = [r for r in results if r["status"] in ("missing", "changed")]
    print(json.dumps({"ok": True, "data": {
        "schema": "MJ_GOLDEN_CHECK_1",
        "label": golden.get("label"),
        "path": d,
        "receiptPath": os.environ["MJ_RECEIPT"],
        "threshold": threshold,
        "passed": not failed,
        "framesRecorded": len(recorded),
        "framesFailed": len(failed),
        "worstScore": min(scores) if scores else None,
        "frames": results,
        "extraFrames": extra,
        "signatureDownscaled": downscaled if changed else golden.get("signatureDownscaled"),
        "_warnings": ([{"code": "EXTRA_FRAMES", "message": "%d frames are not in the golden record and were not checked." % len(extra)}] if extra else []),
        "sourceUnchanged": tree_id(d) == id0,
    }}))

main()
PY_GOLDEN_CHECK
) || true
  frames_emit_python_result "$_out"
}
