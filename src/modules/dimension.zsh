# Dimension_CLI prong. Allowlisted subprocess only.
# MJ does not grow a shell. These three commands exec `dimension` with a
# fixed argv. Preset ids are a closed character class. Paths are existing
# local files. stdout must be one JSON document (dimension --json).

dimension_bin() {
  if [ -n "${MJ_DIMENSION_BIN:-}" ] && [ -x "$MJ_DIMENSION_BIN" ]; then
    printf '%s' "$MJ_DIMENSION_BIN"
    return 0
  fi
  command -v dimension 2>/dev/null
}

dimension_preset_ok() {
  case "$1" in
    ""|*[!A-Za-z0-9_:-]*) return 1 ;;
    *) [ ${#1} -le 128 ] ;;
  esac
}

# dimension_exec <outvar> -- dimension-args...
dimension_exec() {
  local _outvar="$1"
  shift
  local _bin="" _stdout="" _stderr="" _rc=0
  _bin=$(dimension_bin) || {
    set_error "UNSUPPORTED" "dimension is not on PATH. Set MJ_DIMENSION_BIN or install dimension-cli."
    return 69
  }
  _stdout=$(mktemp "${TMPDIR:-/tmp}/mj-dimension.XXXXXX") || {
    set_error "INTERNAL" "Could not stage dimension stdout."
    return 1
  }
  _stderr=$(mktemp "${TMPDIR:-/tmp}/mj-dimension.XXXXXX") || {
    /bin/rm -f "$_stdout"
    set_error "INTERNAL" "Could not stage dimension stderr."
    return 1
  }
  "$_bin" "$@" >"$_stdout" 2>"$_stderr"
  _rc=$?
  if [ "$_rc" -ne 0 ]; then
    set_error "DIMENSION_FAILED" "dimension exited ${_rc}. stderr was kept off the response."
    /bin/rm -f "$_stdout" "$_stderr"
    return 1
  fi
  if ! /usr/bin/python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$_stdout" 2>/dev/null; then
    set_error "DIMENSION_RESULT_INVALID" "dimension did not return one JSON document."
    /bin/rm -f "$_stdout" "$_stderr"
    return 1
  fi
  eval "$_outvar=\$_stdout"
  /bin/rm -f "$_stderr"
  return 0
}

handle_dimension_probe() {
  local _stdout="" _rc=0
  dimension_exec _stdout --json catalog profiles || { _rc=$?; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return $_rc; }
  emit_success_start "$REQUEST_COMMAND" "$REQUEST_ID"
  /usr/bin/python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(json.dumps({"engine":"dimension","reachable":True,"result":d},separators=(",",":")))' "$_stdout"
  emit_success_end
  /bin/rm -f "$_stdout"
  return 0
}

handle_dimension_safezone() {
  local _preset="" _stdout="" _rc=0
  require_arg spec || { emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  _preset="$MJ_REQUIRED_ARG_VALUE"
  dimension_preset_ok "$_preset" || { set_error "INVALID_ARGUMENT" "spec must be a preset id (letters, digits, underscore, colon, hyphen)."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  dimension_exec _stdout --json safe-zone plan --preset "$_preset" || { _rc=$?; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return $_rc; }
  emit_success_start "$REQUEST_COMMAND" "$REQUEST_ID"
  /usr/bin/python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(json.dumps({"engine":"dimension","op":"safe-zone","preset":sys.argv[2],"result":d},separators=(",",":")))' "$_stdout" "$_preset"
  emit_success_end
  /bin/rm -f "$_stdout"
  return 0
}

handle_dimension_conform() {
  local _path="" _preset="" _stdout="" _rc=0
  require_arg path || { emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  _path="$MJ_REQUIRED_ARG_VALUE"
  require_arg spec || { emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  _preset="$MJ_REQUIRED_ARG_VALUE"
  dimension_preset_ok "$_preset" || { set_error "INVALID_ARGUMENT" "spec must be a preset id (letters, digits, underscore, colon, hyphen)."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  [ -f "$_path" ] || { set_error "INVALID_TARGET" "path must be an existing manifest file."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  dimension_exec _stdout --json conform --source "$_path" --preset "$_preset" || { _rc=$?; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return $_rc; }
  emit_success_start "$REQUEST_COMMAND" "$REQUEST_ID"
  /usr/bin/python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(json.dumps({"engine":"dimension","op":"conform","preset":sys.argv[2],"result":d},separators=(",",":")))' "$_stdout" "$_preset"
  emit_success_end
  /bin/rm -f "$_stdout"
  return 0
}
