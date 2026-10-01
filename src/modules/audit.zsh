# Audit log — hash-chained, append-only record of every request this runtime handled.
#
# Opt-in: logging happens only when the audit directory already exists
# (default ~/Library/Logs/MographJailed; MJ_AUDIT_DIR overrides). Each line is
# one JSON object whose "prev" is the SHA-256 of the previous line, so editing
# or deleting any line breaks the chain from that point. Logging never changes
# an operation's response or exit code.
#
# audit.verify — read-only chain check of an audit log.

MJ_AUDIT_ZERO_HASH=0000000000000000000000000000000000000000000000000000000000000000

audit_dir() {
  printf '%s' "${MJ_AUDIT_DIR:-${HOME:-}/Library/Logs/MographJailed}"
}

audit_sha256_stdin() {
  if cap_available shasum; then
    /usr/bin/shasum -a 256 | /usr/bin/awk '{print $1}'
  elif cap_available sha256; then
    "$(cap_path sha256)" -q
  else
    return 1
  fi
}

# mkdir is atomic; concurrent runs serialize on it. A lock older than a minute
# is a crashed writer and is cleared.
audit_lock() {
  local _lock="$1" _i=0
  while ! /bin/mkdir "$_lock" 2>/dev/null; do
    _i=$((_i + 1))
    if [ "$_i" -eq 20 ] && [ -n "$(/usr/bin/find "$_lock" -maxdepth 0 -mmin +1 2>/dev/null)" ]; then
      /bin/rmdir "$_lock" 2>/dev/null
    fi
    [ "$_i" -lt 50 ] || return 1
    /bin/sleep 0.1
  done
}

audit_append() {
  local _rc="$1" _dir="" _log="" _lock="" _prev="" _last="" _name="" _first=1 _line=""
  _dir=$(audit_dir)
  [ -n "$_dir" ] && [ -d "$_dir" ] && [ -w "$_dir" ] || return 0
  _log="$_dir/audit.jsonl"
  _lock="$_dir/.audit.lock"
  audit_lock "$_lock" || return 0

  _prev="$MJ_AUDIT_ZERO_HASH"
  if [ -s "$_log" ]; then
    _last=$(/usr/bin/tail -n 1 "$_log" 2>/dev/null)
    _prev=$(printf '%s' "$_last" | audit_sha256_stdin 2>/dev/null) || _prev=""
  fi
  if [ ${#_prev} -eq 64 ]; then
    _line=$(
      printf '{"v":1,"ts":'; json_quote "$(/bin/date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null)"
      printf ',"cliVersion":'; json_quote "$MOGRAPHJAILED_CLI_VERSION"
      printf ',"requestId":'; json_quote "${REQUEST_ID:-}"
      printf ',"command":'; json_quote "${REQUEST_COMMAND:-}"
      printf ',"exitCode":%s,"args":{' "$_rc"
      for _name in ${=REQUEST_ARG_NAMES}; do
        [ "$_first" -eq 1 ] || printf ','
        _first=0
        json_quote "$_name"; printf ':'; json_quote "$(request_arg_get "$_name" 2>/dev/null)"
      done
      printf '},"prev":'; json_quote "$_prev"; printf '}'
    )
    printf '%s\n' "$_line" >> "$_log" 2>/dev/null
  fi
  /bin/rmdir "$_lock" 2>/dev/null
  return 0
}

handle_audit_verify() {
  local _path="" _out=""
  require_arg path || { emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  _path="$MJ_REQUIRED_ARG_VALUE"
  is_absolute_path "$_path" || { set_error "INVALID_PATH" "Audit log path must be absolute."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  [ -f "$_path" ] || { set_error "INVALID_TARGET" "Audit log must be a regular file."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  [ -r "$_path" ] || { set_error "PERMISSION_DENIED" "Audit log is not readable."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 77; }
  cap_available python3 || { set_error "UNSUPPORTED" "audit.verify requires python3."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 69; }
  mj_require_local_existing_path "$_path" || { emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 73; }

  _out=$(MJ_AUDIT_PATH="$_path" /usr/bin/python3 - <<'PY_AUDIT_VERIFY' 2>/dev/null
import hashlib, json, os
path = os.environ["MJ_AUDIT_PATH"]
prev = "0" * 64
entries = 0
broken = None
reason = None
first_ts = last_ts = None
with open(path, "rb") as f:
    for n, raw in enumerate(f, 1):
        line = raw.rstrip(b"\n")
        try:
            obj = json.loads(line)
            assert isinstance(obj, dict)
        except Exception:
            broken, reason = n, "unparseable line"
            break
        if obj.get("prev") != prev:
            broken, reason = n, "chain mismatch: previous line was altered, removed or inserted"
            break
        entries += 1
        first_ts = first_ts or obj.get("ts")
        last_ts = obj.get("ts")
        prev = hashlib.sha256(line).hexdigest()
print(json.dumps({"ok": True, "data": {
    "schema": "MJ_AUDIT_VERIFY_1",
    "path": path,
    "valid": broken is None,
    "entriesVerified": entries,
    "firstBrokenLine": broken,
    "reason": reason,
    "firstTimestamp": first_ts,
    "lastTimestamp": last_ts,
    "headHash": prev if broken is None else None,
    "note": "headHash identifies the newest entry; record it elsewhere to detect truncation of the log tail.",
}}))
PY_AUDIT_VERIFY
) || true
  frames_emit_python_result "$_out"
}
