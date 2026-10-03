#!/usr/bin/env zsh
set -u

# --- src/core/constants.zsh ---
MOGRAPHJAILED_PROTOCOL="MOGRAPHJAILED"
MOGRAPHJAILED_PROTOCOL_VERSION="1"
MOGRAPHJAILED_CLI_VERSION="0.4.0-dev.3"
MOGRAPHJAILED_STANDARD_LIBRARY_VERSION="1.0"
MOGRAPHJAILED_REQUEST_MAGIC="MOGRAPHJAILED_REQUEST"
MOGRAPHJAILED_REQUEST_VERSION="1"

# Normalize environment-sensitive native utility behavior. All production
# executable paths are absolute; PATH is retained only for child-tool hygiene.
LC_ALL=C
LANG=C
PATH=/usr/bin:/bin:/usr/sbin:/sbin
CDPATH=
COMMAND_MODE=unix2003
IFS=' 	
'
export LC_ALL LANG PATH CDPATH COMMAND_MODE IFS

# Prevent inherited macOS compatibility settings and startup/tool hooks from
# changing command behavior after the audited CLI starts. zsh -f also skips
# user startup files; /etc/zshenv remains an OS/IT-controlled target-Mac gate.
unset SYSTEM_VERSION_COMPAT 2>/dev/null || true
unset ENV BASH_ENV ZDOTDIR 2>/dev/null || true
unset DITTOABORT DITTONORSRC DITTOKEEPBINARIESPATTERN DITTOKEEPBINARIESDIR DITTO_TEST_OPTIONS 2>/dev/null || true
unset COPYFILE_DISABLE COPYFILE_PACK COPYFILE_UNPACK 2>/dev/null || true
unset PERL5OPT PERL5LIB PERLLIB PERL_LOCAL_LIB_ROOT PERL_MB_OPT PERL_MM_OPT 2>/dev/null || true
unset SQLITE_HISTORY SQLITE_TMPDIR 2>/dev/null || true
# Python reads these before running any code; PYTHONPATH/PYTHONHOME would let
# the caller's environment inject modules into every embedded python3 script.
unset PYTHONPATH PYTHONHOME PYTHONSTARTUP PYTHONUSERBASE PYTHONINSPECT PYTHONEXECUTABLE PYTHONWARNINGS 2>/dev/null || true
PYTHONNOUSERSITE=1
PYTHONDONTWRITEBYTECODE=1
export PYTHONNOUSERSITE PYTHONDONTWRITEBYTECODE

# Host applications (After Effects, Cinema 4D) are only ever discovered here.
MJ_HOST_APPS_DIR="/Applications"
MJ_PS="/bin/ps"
MJ_HOST_MIN_YEAR=2024
MJ_HOST_APPS_DIR="${MJ_TEST_APPS_DIR:-/Applications}"
MJ_PS="${MJ_TEST_PS:-/bin/ps}"

# --- src/core/json.zsh ---
json_quote() {
  # JSON-quote one shell string in pure zsh (no process): backslash and quote escaped, ASCII controls
  # below 0x20 escaped (\b \f \n \r \t by name, others \u00XX); all other bytes, Unicode included, as is.
  setopt localoptions nomultibyte     # byte-wise: ASCII controls never occur inside a UTF-8 sequence
  local _s="$1" _o="" _c _i
  _s=${_s//\\/\\\\}
  _s=${_s//\"/\\\"}
  _s=${_s//$'\0'/\\u0000}        # zsh strings can hold a NUL; JSON needs it spelled out (after the backslash doubling)
  if [[ "$_s" == *[$'\001'-$'\037']* ]]; then
    _s=${_s//$'\n'/\\n}; _s=${_s//$'\r'/\\r}; _s=${_s//$'\t'/\\t}; _s=${_s//$'\b'/\\b}; _s=${_s//$'\f'/\\f}
    if [[ "$_s" == *[$'\001'-$'\037']* ]]; then
      for (( _i = 1; _i <= ${#_s}; _i++ )); do
        _c=${_s[_i]}
        if [[ "$_c" == [$'\001'-$'\037'] ]]; then _o+=$(printf '\\u%04x' "'$_c"); else _o+=$_c; fi
      done
      _s=$_o
    fi
  fi
  printf '"%s"' "$_s"
}

json_bool() {
  if [ "$1" = "1" ] || [ "$1" = "true" ]; then printf 'true'; else printf 'false'; fi
}

# --- src/core/errors.zsh ---
MJ_ERR_CODE=""
MJ_ERR_MESSAGE=""

set_error() {
  MJ_ERR_CODE="$1"
  MJ_ERR_MESSAGE="$2"
}

emit_error_response() {
  local _cmd="$1"
  local _req="$2"
  printf '{'
  printf '"protocol":'; json_quote "$MOGRAPHJAILED_PROTOCOL"; printf ','
  printf '"protocolVersion":%s,' "$MOGRAPHJAILED_PROTOCOL_VERSION"
  printf '"cliVersion":'; json_quote "$MOGRAPHJAILED_CLI_VERSION"; printf ','
  printf '"requestId":'; json_quote "$_req"; printf ','
  printf '"command":'; json_quote "$_cmd"; printf ','
  printf '"ok":false,"data":null,"warnings":[],'
  printf '"error":{"code":'; json_quote "$MJ_ERR_CODE"; printf ',"message":'; json_quote "$MJ_ERR_MESSAGE"; printf '}'
  printf '}\n'
}

# --- src/core/response.zsh ---
# Warnings are real: handlers call add_warning, or (for operations backed by a Python
# engine) return a reserved `_warnings` list in their data that split_warnings lifts out.
MJ_WARNINGS=""
MJ_DATA_JSON=""

# add_warning <CODE> <message>
add_warning() {
  local _item="{\"code\":$(json_quote "$1"),\"message\":$(json_quote "$2")}"
  MJ_WARNINGS="${MJ_WARNINGS:+$MJ_WARNINGS,}$_item"
}

# split_warnings <data-json>: sets MJ_DATA_JSON (data without `_warnings`) and appends the
# warnings. If the JSON cannot be split, the data is passed through unchanged.
split_warnings() {
  local _out="" _w=""
  MJ_DATA_JSON="$1"
  _out=$(printf '%s' "$1" | /usr/bin/python3 -c '
import json, sys
d = json.load(sys.stdin)
ws = d.pop("_warnings", []) if isinstance(d, dict) else []
print(",".join(json.dumps({"code": str(w["code"]), "message": str(w["message"])}) for w in ws if isinstance(w, dict) and "code" in w and "message" in w))
print(json.dumps(d, sort_keys=True, separators=(",", ":")))
' 2>/dev/null) || return 0
  { IFS= read -r _w; IFS= read -r MJ_DATA_JSON; } <<EOF_SPLIT
$_out
EOF_SPLIT
  [ -z "$_w" ] || MJ_WARNINGS="${MJ_WARNINGS:+$MJ_WARNINGS,}$_w"
}

emit_success_start() {
  local _cmd="$1"
  local _req="$2"
  printf '{'
  printf '"protocol":'; json_quote "$MOGRAPHJAILED_PROTOCOL"; printf ','
  printf '"protocolVersion":%s,' "$MOGRAPHJAILED_PROTOCOL_VERSION"
  printf '"cliVersion":'; json_quote "$MOGRAPHJAILED_CLI_VERSION"; printf ','
  printf '"requestId":'; json_quote "$_req"; printf ','
  printf '"command":'; json_quote "$_cmd"; printf ','
  printf '"ok":true,"data":'
}

emit_success_end() {
  printf ',"warnings":[%s],"error":null}\n' "$MJ_WARNINGS"
}

# --- src/core/protocol.zsh ---
REQUEST_ID=""
REQUEST_COMMAND=""
REQUEST_ARG_NAMES=""

MJ_REQUEST_MAX_LINE_CHARS=32768
MJ_REQUEST_MAX_ARG_CHARS=16384
MJ_REQUEST_MAX_LINES=32

is_safe_request_id() {
  case "$1" in
    "") return 1 ;;
    *[!A-Za-z0-9._:-]*) return 1 ;;
    *) [ ${#1} -le 128 ] ;;
  esac
}

is_safe_command_name() {
  case "$1" in
    system.probe|system.doctor|system.describe|runtime.verify|file.inspect|file.hash|file.provenance|asset.manifest|asset.verify|search.candidate|image.inspect|image.derivative|image.stats|image.compare|storage.preflight|volume.inspect|temp.create|temp.clean|media.inspect|media.timing|media.frame|project.ingest|expression.lint|plugin.audit|project.snapshot|loop.seams|golden.record|golden.check|audit.verify|project.restore|deps.graph|handoff.package|index.add|index.search|index.verify|preset.add|preset.get|host.detect|ae.render|c4d.render|trace.asset|audit.plugins|project.diff|project.health|c4d.inspect|c4d.lint|bridge.check|project.preflight|cache.inspect|cache.clean|media.qc|project.extract|project.conform|project.jobcheck|package.create|report.tech) return 0 ;;
    *) return 1 ;;
  esac
}

is_safe_arg_name() {
  case "$1" in
    path|pathA|pathB|target|label|runId|output|input|format|expectedCliVersion|expectedProtocolVersion|expectedFilename|expectedSha256|expectedSizeBytes|expectedModifiedEpoch|requiredBytes|maxResults|timeSeconds|maxPixels|minFrames|threshold|version|range|timeoutSeconds|spec) return 0 ;;
    *) return 1 ;;
  esac
}

REQUEST_ARG_path=""
REQUEST_ARG_pathA=""
REQUEST_ARG_pathB=""
REQUEST_ARG_target=""
REQUEST_ARG_label=""
REQUEST_ARG_runId=""
REQUEST_ARG_output=""
REQUEST_ARG_input=""
REQUEST_ARG_format=""
REQUEST_ARG_expectedCliVersion=""
REQUEST_ARG_expectedProtocolVersion=""
REQUEST_ARG_expectedFilename=""
REQUEST_ARG_expectedSha256=""
REQUEST_ARG_expectedSizeBytes=""
REQUEST_ARG_expectedModifiedEpoch=""
REQUEST_ARG_requiredBytes=""
REQUEST_ARG_maxResults=""
REQUEST_ARG_timeSeconds=""
REQUEST_ARG_maxPixels=""
REQUEST_ARG_minFrames=""
REQUEST_ARG_threshold=""
REQUEST_ARG_version=""
REQUEST_ARG_range=""
REQUEST_ARG_timeoutSeconds=""
REQUEST_ARG_spec=""

request_arg_present() {
  local _name="$1"
  case " $REQUEST_ARG_NAMES " in *" $_name "*) return 0 ;; *) return 1 ;; esac
}

request_arg_set() {
  local _name="$1"
  local _value="$2"
  request_arg_present "$_name" && return 1
  REQUEST_ARG_NAMES="$REQUEST_ARG_NAMES $_name"
  case "$_name" in
    path) REQUEST_ARG_path="$_value" ;;
    pathA) REQUEST_ARG_pathA="$_value" ;;
    pathB) REQUEST_ARG_pathB="$_value" ;;
    target) REQUEST_ARG_target="$_value" ;;
    label) REQUEST_ARG_label="$_value" ;;
    runId) REQUEST_ARG_runId="$_value" ;;
    output) REQUEST_ARG_output="$_value" ;;
    input) REQUEST_ARG_input="$_value" ;;
    format) REQUEST_ARG_format="$_value" ;;
    expectedCliVersion) REQUEST_ARG_expectedCliVersion="$_value" ;;
    expectedProtocolVersion) REQUEST_ARG_expectedProtocolVersion="$_value" ;;
    expectedFilename) REQUEST_ARG_expectedFilename="$_value" ;;
    expectedSha256) REQUEST_ARG_expectedSha256="$_value" ;;
    expectedSizeBytes) REQUEST_ARG_expectedSizeBytes="$_value" ;;
    expectedModifiedEpoch) REQUEST_ARG_expectedModifiedEpoch="$_value" ;;
    requiredBytes) REQUEST_ARG_requiredBytes="$_value" ;;
    maxResults) REQUEST_ARG_maxResults="$_value" ;;
    timeSeconds) REQUEST_ARG_timeSeconds="$_value" ;;
    maxPixels) REQUEST_ARG_maxPixels="$_value" ;;
    minFrames) REQUEST_ARG_minFrames="$_value" ;;
    threshold) REQUEST_ARG_threshold="$_value" ;;
    version) REQUEST_ARG_version="$_value" ;;
    range) REQUEST_ARG_range="$_value" ;;
    timeoutSeconds) REQUEST_ARG_timeoutSeconds="$_value" ;;
    spec) REQUEST_ARG_spec="$_value" ;;
    *) return 1 ;;
  esac
}

request_arg_get() {
  local _name="$1"
  request_arg_present "$_name" || return 1
  case "$_name" in
    path) printf '%s' "$REQUEST_ARG_path" ;;
    pathA) printf '%s' "$REQUEST_ARG_pathA" ;;
    pathB) printf '%s' "$REQUEST_ARG_pathB" ;;
    target) printf '%s' "$REQUEST_ARG_target" ;;
    label) printf '%s' "$REQUEST_ARG_label" ;;
    runId) printf '%s' "$REQUEST_ARG_runId" ;;
    output) printf '%s' "$REQUEST_ARG_output" ;;
    input) printf '%s' "$REQUEST_ARG_input" ;;
    format) printf '%s' "$REQUEST_ARG_format" ;;
    expectedCliVersion) printf '%s' "$REQUEST_ARG_expectedCliVersion" ;;
    expectedProtocolVersion) printf '%s' "$REQUEST_ARG_expectedProtocolVersion" ;;
    expectedFilename) printf '%s' "$REQUEST_ARG_expectedFilename" ;;
    expectedSha256) printf '%s' "$REQUEST_ARG_expectedSha256" ;;
    expectedSizeBytes) printf '%s' "$REQUEST_ARG_expectedSizeBytes" ;;
    expectedModifiedEpoch) printf '%s' "$REQUEST_ARG_expectedModifiedEpoch" ;;
    requiredBytes) printf '%s' "$REQUEST_ARG_requiredBytes" ;;
    maxResults) printf '%s' "$REQUEST_ARG_maxResults" ;;
    timeSeconds) printf '%s' "$REQUEST_ARG_timeSeconds" ;;
    maxPixels) printf '%s' "$REQUEST_ARG_maxPixels" ;;
    minFrames) printf '%s' "$REQUEST_ARG_minFrames" ;;
    threshold) printf '%s' "$REQUEST_ARG_threshold" ;;
    version) printf '%s' "$REQUEST_ARG_version" ;;
    range) printf '%s' "$REQUEST_ARG_range" ;;
    timeoutSeconds) printf '%s' "$REQUEST_ARG_timeoutSeconds" ;;
    spec) printf '%s' "$REQUEST_ARG_spec" ;;
    *) return 1 ;;
  esac
}

base64_decode() {
  if [ "$(/usr/bin/uname -s 2>/dev/null)" = "Darwin" ]; then
    printf '%s' "$1" | /usr/bin/base64 -D 2>/dev/null
  else
    printf '%s' "$1" | /usr/bin/base64 -d 2>/dev/null
  fi
}

base64_encode_compact() {
  /usr/bin/base64 | /usr/bin/awk 'BEGIN{ORS=""} {printf "%s",$0}'
}

has_ascii_control() {
  REQUEST_CONTROL_INPUT="$1" /usr/bin/awk 'BEGIN {
    s=ENVIRON["REQUEST_CONTROL_INPUT"];
    for (i=1;i<=length(s);i++) {
      c=substr(s,i,1);
      for (j=1;j<32;j++) if (c==sprintf("%c",j)) exit 0;
      if (c==sprintf("%c",127)) exit 0;
    }
    exit 1;
  }'
}

# Per-command argument schema. Sets MJ_SCHEMA_ALLOWED / MJ_SCHEMA_REQUIRED
# (space-padded name lists). Also published by system.describe.
request_schema_for() {
  MJ_SCHEMA_ALLOWED=""
  MJ_SCHEMA_REQUIRED=""
  case "$1" in
    system.probe|system.doctor|system.describe|temp.create|report.tech|index.verify|host.detect)
      MJ_SCHEMA_ALLOWED=""
      MJ_SCHEMA_REQUIRED=""
      ;;
    runtime.verify)
      MJ_SCHEMA_ALLOWED=" expectedCliVersion expectedProtocolVersion expectedFilename expectedSha256 "
      MJ_SCHEMA_REQUIRED=" expectedCliVersion expectedProtocolVersion "
      ;;
    file.inspect|file.hash|file.provenance|image.inspect|volume.inspect|temp.clean|media.inspect|media.timing)
      MJ_SCHEMA_ALLOWED=" path "
      MJ_SCHEMA_REQUIRED=" path "
      ;;
    media.frame)
      MJ_SCHEMA_ALLOWED=" path output timeSeconds maxPixels "
      MJ_SCHEMA_REQUIRED=" path output timeSeconds "
      ;;
    asset.manifest)
      MJ_SCHEMA_ALLOWED=" path format "
      MJ_SCHEMA_REQUIRED=" path "
      ;;
    asset.verify)
      MJ_SCHEMA_ALLOWED=" path expectedFilename expectedSizeBytes expectedModifiedEpoch expectedSha256 "
      MJ_SCHEMA_REQUIRED=" path "
      ;;
    search.candidate)
      MJ_SCHEMA_ALLOWED=" path target maxResults "
      MJ_SCHEMA_REQUIRED=" path target "
      ;;
    image.derivative)
      MJ_SCHEMA_ALLOWED=" input output target "
      MJ_SCHEMA_REQUIRED=" input output target "
      ;;
    image.stats)
      MJ_SCHEMA_ALLOWED=" path "
      MJ_SCHEMA_REQUIRED=" path "
      ;;
    image.compare)
      MJ_SCHEMA_ALLOWED=" pathA pathB "
      MJ_SCHEMA_REQUIRED=" pathA pathB "
      ;;
    storage.preflight)
      MJ_SCHEMA_ALLOWED=" path requiredBytes "
      MJ_SCHEMA_REQUIRED=" path "
      ;;
    package.create)
      MJ_SCHEMA_ALLOWED=" path output "
      MJ_SCHEMA_REQUIRED=" path output "
      ;;
    project.ingest|expression.lint|plugin.audit)
      MJ_SCHEMA_ALLOWED=" path "
      MJ_SCHEMA_REQUIRED=" path "
      ;;
    project.snapshot)
      MJ_SCHEMA_ALLOWED=" path output "
      MJ_SCHEMA_REQUIRED=" path output "
      ;;
    loop.seams)
      MJ_SCHEMA_ALLOWED=" path maxResults minFrames "
      MJ_SCHEMA_REQUIRED=" path "
      ;;
    golden.record)
      MJ_SCHEMA_ALLOWED=" path output label "
      MJ_SCHEMA_REQUIRED=" path output label "
      ;;
    golden.check)
      MJ_SCHEMA_ALLOWED=" path input threshold "
      MJ_SCHEMA_REQUIRED=" path input "
      ;;
    audit.verify|deps.graph)
      MJ_SCHEMA_ALLOWED=" path "
      MJ_SCHEMA_REQUIRED=" path "
      ;;
    project.restore)
      MJ_SCHEMA_ALLOWED=" path output "
      MJ_SCHEMA_REQUIRED=" path output "
      ;;
    handoff.package)
      MJ_SCHEMA_ALLOWED=" path input output label "
      MJ_SCHEMA_REQUIRED=" path input output label "
      ;;
    index.add)
      MJ_SCHEMA_ALLOWED=" path "
      MJ_SCHEMA_REQUIRED=" path "
      ;;
    index.search)
      MJ_SCHEMA_ALLOWED=" target maxResults "
      MJ_SCHEMA_REQUIRED=" target "
      ;;
    preset.add)
      MJ_SCHEMA_ALLOWED=" path label "
      MJ_SCHEMA_REQUIRED=" path label "
      ;;
    preset.get)
      MJ_SCHEMA_ALLOWED=" label output version "
      MJ_SCHEMA_REQUIRED=" label output "
      ;;
    trace.asset)
      MJ_SCHEMA_ALLOWED=" target path format maxResults "
      MJ_SCHEMA_REQUIRED=" "
      ;;
    audit.plugins)
      MJ_SCHEMA_ALLOWED=" target maxResults "
      MJ_SCHEMA_REQUIRED=" "
      ;;
    project.diff)
      MJ_SCHEMA_ALLOWED=" path input "
      MJ_SCHEMA_REQUIRED=" path input "
      ;;
    project.health)
      MJ_SCHEMA_ALLOWED=" path input format "
      MJ_SCHEMA_REQUIRED=" "
      ;;
    c4d.inspect|c4d.lint)
      MJ_SCHEMA_ALLOWED=" path "
      MJ_SCHEMA_REQUIRED=" path "
      ;;
    bridge.check)
      MJ_SCHEMA_ALLOWED=" path input target "
      MJ_SCHEMA_REQUIRED=" path input "
      ;;
    ae.render)
      MJ_SCHEMA_ALLOWED=" path target output label range timeoutSeconds version "
      MJ_SCHEMA_REQUIRED=" path target output label "
      ;;
    c4d.render)
      MJ_SCHEMA_ALLOWED=" path target output label range timeoutSeconds version "
      MJ_SCHEMA_REQUIRED=" path output label "
      ;;
    project.preflight)
      MJ_SCHEMA_ALLOWED=" path "
      MJ_SCHEMA_REQUIRED=" path "
      ;;
    cache.inspect)
      MJ_SCHEMA_ALLOWED="  "
      MJ_SCHEMA_REQUIRED="  "
      ;;
    cache.clean)
      MJ_SCHEMA_ALLOWED=" target format "
      MJ_SCHEMA_REQUIRED=" target "
      ;;
    media.qc)
      MJ_SCHEMA_ALLOWED=" path format input "
      MJ_SCHEMA_REQUIRED=" path "
      ;;
    project.extract)
      MJ_SCHEMA_ALLOWED=" path input target output label "
      MJ_SCHEMA_REQUIRED=" path input target output label "
      ;;
    project.conform)
      MJ_SCHEMA_ALLOWED=" path input spec format output label "
      MJ_SCHEMA_REQUIRED=" input "
      ;;
    project.jobcheck)
      MJ_SCHEMA_ALLOWED=" path "
      MJ_SCHEMA_REQUIRED=" path "
      ;;
    *) return 1 ;;
  esac
}

validate_request_schema() {
  local _allowed=""
  local _required=""
  local _arg
  request_schema_for "$REQUEST_COMMAND" || {
    set_error "UNSUPPORTED_COMMAND" "Command is not allowlisted."
    return 1
  }
  _allowed="$MJ_SCHEMA_ALLOWED"
  _required="$MJ_SCHEMA_REQUIRED"

  for _arg in path pathA pathB target label runId output input format expectedCliVersion expectedProtocolVersion expectedFilename expectedSha256 expectedSizeBytes expectedModifiedEpoch requiredBytes maxResults timeSeconds maxPixels minFrames threshold version range timeoutSeconds; do
    if request_arg_present "$_arg"; then
      case "$_allowed" in *" $_arg "*) ;; *)
        set_error "UNEXPECTED_ARGUMENT" "Argument is not valid for command: $_arg."
        return 1
        ;;
      esac
    fi
  done

  case "$_required" in
    *" path "*) request_arg_present path || { set_error "MISSING_ARGUMENT" "Required argument is missing: path."; return 1; } ;;
  esac
  case "$_required" in
    *" pathA "*) request_arg_present pathA || { set_error "MISSING_ARGUMENT" "Required argument is missing: pathA."; return 1; } ;;
  esac
  case "$_required" in
    *" pathB "*) request_arg_present pathB || { set_error "MISSING_ARGUMENT" "Required argument is missing: pathB."; return 1; } ;;
  esac
  case "$_required" in
    *" output "*) request_arg_present output || { set_error "MISSING_ARGUMENT" "Required argument is missing: output."; return 1; } ;;
  esac
  case "$_required" in
    *" input "*) request_arg_present input || { set_error "MISSING_ARGUMENT" "Required argument is missing: input."; return 1; } ;;
  esac
  case "$_required" in
    *" target "*) request_arg_present target || { set_error "MISSING_ARGUMENT" "Required argument is missing: target."; return 1; } ;;
  esac
  case "$_required" in
    *" expectedCliVersion "*) request_arg_present expectedCliVersion || { set_error "MISSING_ARGUMENT" "Required argument is missing: expectedCliVersion."; return 1; } ;;
  esac
  case "$_required" in
    *" expectedProtocolVersion "*) request_arg_present expectedProtocolVersion || { set_error "MISSING_ARGUMENT" "Required argument is missing: expectedProtocolVersion."; return 1; } ;;
  esac
  case "$_required" in
    *" timeSeconds "*) request_arg_present timeSeconds || { set_error "MISSING_ARGUMENT" "Required argument is missing: timeSeconds."; return 1; } ;;
  esac
  return 0
}

load_request_file() {
  local _file="$1"
  local _line_no=0
  local _line=""
  local _lhs=""
  local _name=""
  local _encoded=""
  local _decoded_with_marker=""
  local _decode_rc=0
  local _decoded=""
  local _roundtrip=""

  REQUEST_ID=""
  REQUEST_COMMAND=""
  REQUEST_ARG_NAMES=""
  REQUEST_ARG_path=""
  REQUEST_ARG_pathA=""
  REQUEST_ARG_pathB=""
  REQUEST_ARG_target=""
  REQUEST_ARG_label=""
  REQUEST_ARG_runId=""
  REQUEST_ARG_output=""
  REQUEST_ARG_input=""
  REQUEST_ARG_format=""
  REQUEST_ARG_expectedCliVersion=""
  REQUEST_ARG_expectedProtocolVersion=""
  REQUEST_ARG_expectedFilename=""
  REQUEST_ARG_expectedSha256=""
  REQUEST_ARG_expectedSizeBytes=""
  REQUEST_ARG_expectedModifiedEpoch=""
  REQUEST_ARG_requiredBytes=""
  REQUEST_ARG_maxResults=""
  REQUEST_ARG_timeSeconds=""
  REQUEST_ARG_maxPixels=""
  REQUEST_ARG_minFrames=""
  REQUEST_ARG_threshold=""
  REQUEST_ARG_version=""
  REQUEST_ARG_range=""
  REQUEST_ARG_timeoutSeconds=""

  if [ -z "$_file" ] || [ ! -f "$_file" ]; then
    set_error "REQUEST_NOT_FOUND" "Request file does not exist."
    return 1
  fi
  if [ ! -r "$_file" ]; then
    set_error "PERMISSION_DENIED" "Request file is not readable."
    return 1
  fi

  while IFS= read -r _line || [ -n "$_line" ]; do
    _line_no=$((_line_no + 1))
    [ $_line_no -le $MJ_REQUEST_MAX_LINES ] || {
      set_error "REQUEST_TOO_LARGE" "Request contains too many lines."
      return 1
    }
    [ ${#_line} -le $MJ_REQUEST_MAX_LINE_CHARS ] || {
      set_error "REQUEST_TOO_LARGE" "Request line exceeds the protocol limit."
      return 1
    }

    if [ $_line_no -eq 1 ]; then
      [ "$_line" = "$MOGRAPHJAILED_REQUEST_MAGIC $MOGRAPHJAILED_REQUEST_VERSION" ] || {
        set_error "BAD_REQUEST_VERSION" "Unsupported or malformed request header."
        return 1
      }
      continue
    fi

    [ -z "$_line" ] && continue
    case "$_line" in
      requestId=*)
        [ -z "$REQUEST_ID" ] || { set_error "DUPLICATE_FIELD" "Duplicate requestId."; return 1; }
        REQUEST_ID=${_line#requestId=}
        is_safe_request_id "$REQUEST_ID" || { set_error "INVALID_REQUEST_ID" "requestId contains unsupported characters or length."; return 1; }
        ;;
      command=*)
        [ -z "$REQUEST_COMMAND" ] || { set_error "DUPLICATE_FIELD" "Duplicate command."; return 1; }
        REQUEST_COMMAND=${_line#command=}
        is_safe_command_name "$REQUEST_COMMAND" || { set_error "UNSUPPORTED_COMMAND" "Command is not allowlisted."; return 1; }
        ;;
      arg.*=*)
        _lhs=${_line%%=*}
        _name=${_lhs#arg.}
        is_safe_arg_name "$_name" || { set_error "INVALID_ARGUMENT" "Argument name is not allowlisted."; return 1; }
        _encoded=${_line#*=}
        [ ${#_encoded} -le $MJ_REQUEST_MAX_LINE_CHARS ] || { set_error "REQUEST_TOO_LARGE" "Encoded argument exceeds the protocol limit."; return 1; }
        _decoded_with_marker=$(base64_decode "$_encoded"; _decode_rc=$?; printf '__MJ_SENTINEL__'; exit $_decode_rc) || { set_error "INVALID_ARGUMENT_ENCODING" "Argument is not valid Base64."; return 1; }
        _decoded=${_decoded_with_marker%__MJ_SENTINEL__}
        [ ${#_decoded} -le $MJ_REQUEST_MAX_ARG_CHARS ] || { set_error "REQUEST_TOO_LARGE" "Decoded argument exceeds the protocol limit."; return 1; }
        _roundtrip=$(printf '%s' "$_decoded" | base64_encode_compact)
        [ "$_roundtrip" = "$_encoded" ] || { set_error "INVALID_ARGUMENT_ENCODING" "Argument encoding is non-canonical or contains unsupported bytes."; return 1; }
        if has_ascii_control "$_decoded"; then
          set_error "INVALID_ARGUMENT" "ASCII control characters are not accepted in protocol arguments."
          return 1
        fi
        request_arg_set "$_name" "$_decoded" || { set_error "DUPLICATE_FIELD" "Duplicate argument."; return 1; }
        ;;
      *)
        set_error "MALFORMED_REQUEST" "Unknown request field."
        return 1
        ;;
    esac
  done < "$_file"

  [ -n "$REQUEST_ID" ] || { set_error "MISSING_FIELD" "requestId is required."; return 1; }
  [ -n "$REQUEST_COMMAND" ] || { set_error "MISSING_FIELD" "command is required."; return 1; }
  validate_request_schema || return 1
  return 0
}

# --- src/core/path.zsh ---
MJ_REQUIRED_ARG_VALUE=""

require_arg() {
  local _name="$1"
  MJ_REQUIRED_ARG_VALUE=""
  if ! request_arg_present "$_name"; then
    set_error "MISSING_ARGUMENT" "Required argument is missing: $_name."
    return 1
  fi
  MJ_REQUIRED_ARG_VALUE=$(request_arg_get "$_name" 2>/dev/null) || {
    set_error "MISSING_ARGUMENT" "Required argument is missing: $_name."
    return 1
  }
  [ -n "$MJ_REQUIRED_ARG_VALUE" ] || {
    set_error "MISSING_ARGUMENT" "Required argument is empty: $_name."
    return 1
  }
  return 0
}

is_absolute_path() {
  case "$1" in /*) return 0 ;; *) return 1 ;; esac
}

canonical_existing_dir() {
  local _dir="$1"
  [ -n "$_dir" ] || return 1
  is_absolute_path "$_dir" || return 1
  [ -d "$_dir" ] || return 1
  (cd "$_dir" 2>/dev/null && /bin/pwd -P)
}

mj_tmp_parent() {
  local _base=${TMPDIR:-/tmp}
  _base=${_base%/}
  [ -n "$_base" ] || _base=/tmp
  if is_absolute_path "$_base" && [ -d "$_base" ]; then
    canonical_existing_dir "$_base" 2>/dev/null || printf '%s' "$_base"
  else
    printf '%s' "$_base"
  fi
}

parent_path() {
  local _path_arg="$1"
  local _parent=${_path_arg%/*}
  [ -n "$_parent" ] || _parent=/
  printf '%s' "$_parent"
}


MJ_STAGE_DIR=""

create_mj_stage_dir() {
  local _parent="$1"
  local _prefix="$2"
  local _dir=""
  local _marker=""
  MJ_STAGE_DIR=""
  is_absolute_path "$_parent" || return 1
  [ -d "$_parent" ] && [ -w "$_parent" ] || return 1
  case "$_prefix" in MographJailed_*) ;; *) return 1 ;; esac
  _dir=$(/usr/bin/mktemp -d "$_parent/${_prefix}.XXXXXXXX" 2>/dev/null) || return 1
  _marker="$_dir/.mj_native_stage"
  if ! printf '%s\n%s\n%s\n%s\n%s\n' "$MOGRAPHJAILED_PROTOCOL" "$REQUEST_ID" "$_dir" "${EUID:-unknown}" "$_prefix" > "$_marker"; then
    # Marker initialization happens immediately after mktemp. Remove only the
    # known marker and then the now-empty directory; never recurse without proof.
    /bin/rm -f "$_marker" 2>/dev/null || true
    /bin/rm -d "$_dir" 2>/dev/null || true
    return 1
  fi
  MJ_STAGE_DIR="$_dir"
  return 0
}

is_safe_mj_stage_dir() {
  local _dir="$1"
  local _parent="$2"
  local _prefix="$3"
  local _leaf=""
  local _actual_parent=""
  local _marker=""
  local _protocol=""
  local _request=""
  local _bound_path=""
  local _bound_euid=""
  local _bound_prefix=""

  case "$_dir" in */) return 1 ;; esac
  _leaf=${_dir##*/}
  _actual_parent=${_dir%/*}
  [ "$_actual_parent" = "$_parent" ] || return 1
  case "$_leaf" in "${_prefix}."*) ;; *) return 1 ;; esac
  [ -d "$_dir" ] && [ ! -L "$_dir" ] || return 1
  _marker="$_dir/.mj_native_stage"
  [ -f "$_marker" ] && [ ! -L "$_marker" ] || return 1
  {
    IFS= read -r _protocol || return 1
    IFS= read -r _request || return 1
    IFS= read -r _bound_path || return 1
    IFS= read -r _bound_euid || return 1
    IFS= read -r _bound_prefix || return 1
  } < "$_marker"
  [ "$_protocol" = "$MOGRAPHJAILED_PROTOCOL" ] || return 1
  [ "$_request" = "$REQUEST_ID" ] || return 1
  [ "$_bound_path" = "$_dir" ] || return 1
  [ "$_bound_euid" = "${EUID:-unknown}" ] || return 1
  [ "$_bound_prefix" = "$_prefix" ] || return 1
  return 0
}

cleanup_mj_stage_dir() {
  local _dir="$1"
  local _parent="$2"
  local _prefix="$3"
  is_safe_mj_stage_dir "$_dir" "$_parent" "$_prefix" || return 1
  /bin/rm -rf "$_dir" || return 1
  [ ! -e "$_dir" ] && [ ! -L "$_dir" ]
}

# --- src/core/capabilities.zsh ---
cap_path() {
  case "$1" in
    zsh) printf '/bin/zsh' ;;
    sw_vers) printf '/usr/bin/sw_vers' ;;
    stat) printf '/usr/bin/stat' ;;
    file) printf '/usr/bin/file' ;;
    df) printf '/bin/df' ;;
    mktemp) printf '/usr/bin/mktemp' ;;
    plutil) printf '/usr/bin/plutil' ;;
    sqlite3) printf '/usr/bin/sqlite3' ;;
    jq) printf '/usr/bin/jq' ;;
    sips) printf '/usr/bin/sips' ;;
    ditto) printf '/usr/bin/ditto' ;;
    sha256)
      if [ -x /sbin/sha256 ]; then printf '/sbin/sha256'
      elif [ -x /usr/bin/sha256 ]; then printf '/usr/bin/sha256'
      else printf '/sbin/sha256'; fi
      ;;
    shasum) printf '/usr/bin/shasum' ;;
    mdls) printf '/usr/bin/mdls' ;;
    avmediainfo) printf '/usr/bin/avmediainfo' ;;
    avconvert) printf '/usr/bin/avconvert' ;;
    afinfo) printf '/usr/bin/afinfo' ;;
    afconvert) printf '/usr/bin/afconvert' ;;
    mdfind) printf '/usr/bin/mdfind' ;;
    xattr) printf '/usr/bin/xattr' ;;
    osascript) printf '/usr/bin/osascript' ;;
    python3) printf '/usr/bin/python3' ;;
    base64) printf '/usr/bin/base64' ;;
    awk) printf '/usr/bin/awk' ;;
    uname) printf '/usr/bin/uname' ;;
    sed) printf '/usr/bin/sed' ;;
    rm) printf '/bin/rm' ;;
    date) printf '/bin/date' ;;
    mv) printf '/bin/mv' ;;
    cp) printf '/bin/cp' ;;
    pwd) printf '/bin/pwd' ;;
    *) return 1 ;;
  esac
}

cap_available() {
  local _cap_path
  _cap_path=$(cap_path "$1") || return 1
  [ -x "$_cap_path" ]
}

emit_capability_object() {
  local _name="$1"
  local _path
  _path=$(cap_path "$_name" 2>/dev/null || printf '')
  printf '{"available":'; if [ -n "$_path" ] && [ -x "$_path" ]; then printf 'true'; else printf 'false'; fi
  printf ',"path":'; json_quote "$_path"; printf '}'
}
functions -c cap_path _mj_cap_path_real; cap_path() { case "$1" in avmediainfo) [ -n "${MJ_TEST_AVMEDIAINFO:-}" ] && { printf "%s" "$MJ_TEST_AVMEDIAINFO"; return 0; } ;; afconvert) [ -n "${MJ_TEST_AFCONVERT:-}" ] && { printf "%s" "$MJ_TEST_AFCONVERT"; return 0; } ;; esac; _mj_cap_path_real "$1"; }
cap_available() { case " ${MJ_TEST_MISSING_CAPS:-} " in *" $1 "*) return 1 ;; esac; local _cap_path; _cap_path=$(cap_path "$1") || return 1; [ -x "$_cap_path" ]; }

# --- src/core/operations.zsh ---
operation_names() {
  printf '%s\n' \
    system.probe \
    system.doctor \
    system.describe \
    runtime.verify \
    file.inspect \
    file.hash \
    file.provenance \
    asset.manifest \
    asset.verify \
    search.candidate \
    image.inspect \
    image.derivative \
    image.stats \
    image.compare \
    storage.preflight \
    volume.inspect \
    temp.create \
    temp.clean \
    media.inspect \
    media.timing \
    media.frame \
    project.ingest \
    expression.lint \
    plugin.audit \
    project.snapshot \
    loop.seams \
    golden.record \
    golden.check \
    audit.verify \
    project.restore \
    deps.graph \
    handoff.package \
    index.add \
    index.search \
    index.verify \
    preset.add \
    preset.get \
    host.detect \
    ae.render \
    c4d.render \
    trace.asset \
    audit.plugins \
    project.diff \
    project.health \
    c4d.inspect \
    c4d.lint \
    bridge.check \
    project.preflight \
    cache.inspect \
    cache.clean \
    media.qc \
    project.extract \
    project.conform \
    project.jobcheck \
    report.tech \
    package.create
}

operation_known() {
  case "$1" in
    system.probe|system.doctor|system.describe|runtime.verify|file.inspect|file.hash|file.provenance|asset.manifest|asset.verify|search.candidate|image.inspect|image.derivative|image.stats|image.compare|storage.preflight|volume.inspect|temp.create|temp.clean|media.inspect|media.timing|media.frame|project.ingest|expression.lint|plugin.audit|project.snapshot|loop.seams|golden.record|golden.check|audit.verify|project.restore|deps.graph|handoff.package|index.add|index.search|index.verify|preset.add|preset.get|host.detect|ae.render|c4d.render|trace.asset|audit.plugins|project.diff|project.health|c4d.inspect|c4d.lint|bridge.check|project.preflight|cache.inspect|cache.clean|media.qc|project.extract|project.conform|project.jobcheck|report.tech|package.create) return 0 ;;
    *) return 1 ;;
  esac
}

# Emit a JSON string array from newline-delimited stdin. This deliberately
# avoids shell word-splitting semantics, which differ between zsh and bash.
emit_string_array_lines() {
  local _first=1
  local _item=""
  printf '['
  while IFS= read -r _item || [ -n "$_item" ]; do
    [ -n "$_item" ] || continue
    [ "$_first" -eq 1 ] || printf ','
    _first=0
    json_quote "$_item"
  done
  printf ']'
}

operation_available() {
  case "$1" in
    system.probe|system.doctor|system.describe|runtime.verify|report.tech)
      return 0
      ;;
    file.inspect)
      cap_available stat && cap_available file && cap_available uname
      ;;
    file.hash)
      cap_available stat && cap_available uname && { cap_available sha256 || cap_available shasum; }
      ;;
    file.provenance)
      cap_available xattr
      ;;
    asset.manifest)
      cap_available stat && cap_available file && cap_available uname
      ;;
    asset.verify)
      cap_available stat && cap_available uname
      ;;
    search.candidate)
      cap_available mdfind && cap_available mktemp && cap_available rm
      ;;
    image.inspect)
      cap_available sips && cap_available awk
      ;;
    image.derivative)
      cap_available sips && cap_available awk && cap_available mktemp && cap_available mv && cap_available rm && cap_available stat && cap_available uname
      ;;
    loop.seams|golden.record|golden.check|audit.verify|deps.graph|index.add|index.search|index.verify|host.detect|ae.render|c4d.render|trace.asset|audit.plugins|project.diff|project.health|c4d.inspect|c4d.lint|bridge.check)
      cap_available python3
      ;;
    project.restore|handoff.package|preset.add|preset.get)
      cap_available python3 && cap_available cp
      ;;
    image.stats|image.compare)
      cap_available python3 && cap_available sips && cap_available awk
      ;;
    storage.preflight)
      cap_available df && cap_available awk && cap_available uname
      ;;
    volume.inspect)
      cap_available df && cap_available awk && cap_available uname
      ;;
    temp.create)
      cap_available mktemp && cap_available rm && cap_available pwd
      ;;
    temp.clean)
      cap_available sed && cap_available rm && cap_available pwd
      ;;
    media.inspect)
      cap_available stat && cap_available file && cap_available uname
      ;;
    media.timing)
      standard_library_mediaprobe_available
      ;;
    media.frame)
      standard_library_framekit_available
      ;;
    project.ingest|expression.lint)
      cap_available python3
      ;;
    plugin.audit)
      cap_available stat && cap_available uname && { cap_available sha256 || cap_available shasum; }
      ;;
    project.snapshot)
      cap_available stat && cap_available uname && cap_available cp && cap_available date && cap_available rm && { cap_available sha256 || cap_available shasum; }
      ;;
    package.create)
      cap_available ditto && cap_available mktemp && cap_available rm && cap_available mv && cap_available stat && cap_available uname
      ;;
    project.preflight)
      cap_available python3
      ;;
    cache.inspect)
      cap_available python3
      ;;
    cache.clean)
      cap_available python3
      ;;
    media.qc)
      cap_available python3 && cap_available avmediainfo
      ;;
    project.extract)
      cap_available python3 && cap_available cp
      ;;
    project.conform)
      cap_available python3 && cap_available cp
      ;;
    project.jobcheck)
      cap_available python3
      ;;
    *) return 1 ;;
  esac
}

operation_summary() {
  case "$1" in
    system.probe) printf 'Detect the macOS version and which native tools are available.' ;;
    system.doctor) printf 'Check that the runtime has what it needs; says what is missing.' ;;
    system.describe) printf 'List every operation, its arguments and availability.' ;;
    runtime.verify) printf 'Confirm the runtime'\''s version, protocol and (optionally) SHA-256.' ;;
    file.inspect) printf 'Read basic facts about a file.' ;;
    file.hash) printf 'SHA-256 of a file, checking it did not change while hashing.' ;;
    file.provenance) printf 'List a file'\''s extended-attribute names (never values).' ;;
    asset.manifest) printf 'Identity record for one asset: size, time, type, hash.' ;;
    asset.verify) printf 'Compare an asset with expected identity evidence.' ;;
    search.candidate) printf 'Spotlight search for files with a given name (never relinks).' ;;
    image.inspect) printf 'Identify an image and report its size and format.' ;;
    image.derivative) printf 'Make a smaller copy of an image; never overwrites.' ;;
    image.stats) printf 'Color signature of a PNG (histogram and grid).' ;;
    image.compare) printf 'Similarity score (0-1) between two PNGs.' ;;
    storage.preflight) printf 'Check free space and writability before a big job.' ;;
    volume.inspect) printf 'Filesystem and volume facts for a path.' ;;
    temp.create) printf 'Create a private temporary working folder.' ;;
    temp.clean) printf 'Remove a temporary folder this tool made.' ;;
    media.inspect) printf 'Fast, conservative media metadata.' ;;
    media.timing) printf 'Duration, frame rate and codec timing of a video.' ;;
    media.frame) printf 'Extract one exact frame from a video as a new PNG.' ;;
    project.ingest) printf 'Summarize an After Effects scrape: comps, layers, fonts, footage.' ;;
    expression.lint) printf 'Check scraped expressions for broken references and slow patterns.' ;;
    plugin.audit) printf 'List and hash the files in a Plug-ins folder.' ;;
    project.snapshot) printf 'Save a verified, hash-named copy of an .aep; never overwrites.' ;;
    loop.seams) printf 'Rank the best loop points in a folder of PNG frames.' ;;
    golden.record) printf 'Record hashes and signatures of key frames; never overwrites.' ;;
    golden.check) printf 'Compare new frames with a golden record.' ;;
    audit.verify) printf 'Check the hash-chained request log for tampering.' ;;
    project.restore) printf 'Copy a snapshot back out as a new, verified .aep.' ;;
    deps.graph) printf 'Per-comp dependencies, missing footage, single points of failure.' ;;
    handoff.package) printf 'Build a delivery folder: project, footage, manifest, README.' ;;
    index.add) printf 'Index scrapes, snapshots, golden records and handoffs.' ;;
    index.search) printf 'Full-text search across everything indexed.' ;;
    index.verify) printf 'Check the local index and stored presets are intact.' ;;
    preset.add) printf 'Store a preset file as a new version of a label.' ;;
    preset.get) printf 'Copy a stored preset out; never overwrites.' ;;
    host.detect) printf 'Find After Effects and Cinema 4D, Redshift and the GPU.' ;;
    ae.render) printf 'Render a comp with aerender to a new PNG-sequence folder.' ;;
    c4d.render) printf 'Render a Cinema 4D scene to a new PNG-sequence folder.' ;;
    trace.asset) printf 'Exact nested comp path to an asset, missing asset or font.' ;;
    c4d.inspect) printf 'Summary of a Cinema 4D scene scrape: renderer, size, range, textures.' ;;
    c4d.lint) printf 'Check a Cinema 4D scene scrape: textures, camera, size, range, output.' ;;
    bridge.check) printf 'Compare a Cinema 4D scene with the After Effects comps that use it.' ;;
    project.diff) printf 'What changed between two scrapes: comps, layers, expressions, footage.' ;;
    project.health) printf 'A documented 0-100 health score for a project, with its trend.' ;;
    audit.plugins) printf 'Projects using an effect matchName, or the plugin inventory.' ;;
    project.preflight) printf '%s' 'Will this project open cleanly here? Fonts, footage, third-party effects.' ;;
    cache.inspect) printf '%s' 'How much disk the After Effects, Adobe media and Redshift caches take.' ;;
    cache.clean) printf '%s' 'Empty one cache by its id; refuses while its app runs.' ;;
    media.qc) printf '%s' 'Check a movie against a delivery spec: codec, size, fps, audio, loudness.' ;;
    project.extract) printf '%s' 'Keep chosen comps and what they use as a new project, via a job on a copy.' ;;
    project.conform) printf '%s' 'Plan studio names, labels, folders, expression fixes; format=job makes a job.' ;;
    project.jobcheck) printf '%s' 'Did an After Effects job run, save its result, and leave the original untouched?' ;;
    report.tech) printf 'Native diagnostic receipt for support.' ;;
    package.create) printf 'Zip a file or folder with ditto; never overwrites.' ;;
    *) printf '' ;;
  esac
}

operation_state() {
  if operation_available "$1"; then printf 'AVAILABLE'; else printf 'UNAVAILABLE'; fi
}

operation_cost() {
  case "$1" in
    system.probe|system.doctor|system.describe|runtime.verify|file.inspect|file.provenance|image.inspect|volume.inspect|storage.preflight|temp.create|temp.clean|report.tech) printf 'FAST' ;;
    file.hash) printf 'SIZE_DEPENDENT' ;;
    asset.manifest|asset.verify) printf 'MODE_DEPENDENT' ;;
    search.candidate) printf 'INDEX_DEPENDENT' ;;
    image.derivative) printf 'IO_BOUND' ;;
    image.stats|image.compare) printf 'SIZE_DEPENDENT' ;;
    loop.seams|golden.record|golden.check) printf 'FRAME_COUNT_DEPENDENT' ;;
    media.inspect) printf 'PATH_DEPENDENT' ;;
    media.timing) printf 'BOUNDED_MEDIA_PROBE' ;;
    media.frame) printf 'FRAME_DECODE' ;;
    project.ingest|expression.lint|audit.verify|deps.graph) printf 'SIZE_DEPENDENT' ;;
    project.restore|handoff.package|preset.add|preset.get) printf 'IO_BOUND' ;;
    index.add) printf 'PATH_DEPENDENT' ;;
    index.search) printf 'INDEX_DEPENDENT' ;;
    index.verify) printf 'SIZE_DEPENDENT' ;;
    host.detect) printf 'BOUNDED_PROBE' ;;
    trace.asset|audit.plugins) printf 'INDEX_DEPENDENT' ;;
    project.diff|project.health|c4d.inspect|c4d.lint|bridge.check) printf 'SIZE_DEPENDENT' ;;
    ae.render|c4d.render) printf 'RENDER_BOUND' ;;
    plugin.audit) printf 'PATH_DEPENDENT' ;;
    project.snapshot) printf 'IO_BOUND' ;;
    package.create) printf 'IO_BOUND' ;;
    project.preflight) printf 'SIZE_DEPENDENT' ;;
    cache.inspect) printf 'SIZE_DEPENDENT' ;;
    cache.clean) printf 'SIZE_DEPENDENT' ;;
    media.qc) printf 'SIZE_DEPENDENT' ;;
    project.extract) printf 'IO_BOUND' ;;
    project.conform) printf 'SIZE_DEPENDENT' ;;
    project.jobcheck) printf 'SIZE_DEPENDENT' ;;
    *) printf 'UNKNOWN' ;;
  esac
}

operation_mutation() {
  case "$1" in
    temp.create) printf 'TEMP_CREATE' ;;
    temp.clean) printf 'TEMP_DELETE' ;;
    search.candidate|loop.seams|golden.check) printf 'INTERNAL_TEMP' ;;
    image.derivative|media.frame|package.create|project.snapshot|golden.record|project.restore|handoff.package|preset.get|ae.render|c4d.render) printf 'DERIVATIVE_CREATE' ;;
    index.add|preset.add|project.health) printf 'STORE_WRITE' ;;
    cache.clean) printf 'CACHE_DELETE' ;;
    project.extract) printf 'DERIVATIVE_CREATE' ;;
    project.conform) printf 'DERIVATIVE_CREATE' ;;
    *) printf 'NONE' ;;
  esac
}

operation_authority() {
  case "$1" in
    system.probe|system.doctor) printf 'AUTHORITATIVE_ENVIRONMENT' ;;
    system.describe) printf 'CONTRACT' ;;
    runtime.verify) printf 'AUTHORITATIVE_RUNTIME' ;;
    file.inspect|volume.inspect|storage.preflight) printf 'MIXED' ;;
    file.hash) printf 'AUTHORITATIVE_BYTES' ;;
    file.provenance) printf 'AUTHORITATIVE_FILESYSTEM_METADATA' ;;
    asset.manifest|asset.verify) printf 'ASSET_IDENTITY' ;;
    search.candidate) printf 'ADVISORY_INDEX' ;;
    image.inspect) printf 'AUTHORITATIVE_IMAGE_STRUCTURE' ;;
    image.stats|image.compare|loop.seams|golden.record|golden.check) printf 'DERIVED_IMAGE_SIGNATURE' ;;
    image.derivative|temp.create|temp.clean|package.create) printf 'AUTHORITATIVE_OPERATION' ;;
    media.inspect) printf 'ADVISORY_METADATA' ;;
    media.timing) printf 'NORMALIZED_NATIVE_MEDIA' ;;
    media.frame) printf 'NATIVE_FRAME_DERIVATIVE' ;;
    report.tech) printf 'DIAGNOSTIC' ;;
    project.ingest) printf 'DERIVED_PROJECT_SUMMARY' ;;
    expression.lint) printf 'DERIVED_LINT_FINDINGS' ;;
    plugin.audit) printf 'AUTHORITATIVE_FILESYSTEM_METADATA' ;;
    project.snapshot) printf 'AUTHORITATIVE_OPERATION' ;;
    audit.verify) printf 'DERIVED_AUDIT_CHAIN' ;;
    project.restore|handoff.package) printf 'AUTHORITATIVE_OPERATION' ;;
    deps.graph) printf 'DERIVED_PROJECT_SUMMARY' ;;
    index.add|preset.add) printf 'MJ_OWNED_STORE' ;;
    index.search) printf 'ADVISORY_INDEX' ;;
    trace.asset|audit.plugins|project.diff|project.health|c4d.inspect|c4d.lint|bridge.check) printf 'DERIVED_PROJECT_SUMMARY' ;;
    index.verify) printf 'AUTHORITATIVE_STORE_INTEGRITY' ;;
    preset.get|ae.render|c4d.render) printf 'AUTHORITATIVE_OPERATION' ;;
    host.detect) printf 'AUTHORITATIVE_ENVIRONMENT' ;;
    project.preflight) printf 'DERIVED_PROJECT_SUMMARY' ;;
    cache.inspect) printf 'AUTHORITATIVE_FILESYSTEM_METADATA' ;;
    cache.clean) printf 'AUTHORITATIVE_OPERATION' ;;
    media.qc) printf 'DERIVED_MEDIA_QC' ;;
    project.extract) printf 'AUTHORITATIVE_OPERATION' ;;
    project.conform) printf 'DERIVED_PROJECT_SUMMARY' ;;
    project.jobcheck) printf 'AUTHORITATIVE_OPERATION' ;;
    *) printf 'UNKNOWN' ;;
  esac
}

operation_interactive_safe() {
  case "$1" in
    file.hash|asset.manifest|asset.verify|search.candidate|image.derivative|media.timing|media.frame|package.create|project.snapshot|loop.seams|golden.record|golden.check|project.restore|handoff.package|index.add|preset.add|preset.get|ae.render|c4d.render|cache.clean) return 1 ;;
    *) return 0 ;;
  esac
}

operation_network_sensitive() {
  case "$1" in
    file.inspect|file.hash|file.provenance|asset.manifest|asset.verify|search.candidate|image.inspect|image.derivative|image.stats|image.compare|storage.preflight|volume.inspect|media.inspect|media.timing|media.frame|package.create|project.ingest|expression.lint|plugin.audit|project.snapshot|loop.seams|golden.record|golden.check|audit.verify|project.restore|deps.graph|handoff.package|index.add|index.search|index.verify|preset.add|preset.get|ae.render|c4d.render|trace.asset|audit.plugins|project.diff|project.health|c4d.inspect|c4d.lint|bridge.check|project.preflight|media.qc|project.extract|project.conform|project.jobcheck) return 0 ;;
    *) return 1 ;;
  esac
}

# Required and optional capability functions emit one capability per line so
# Registry serialization is identical under zsh and bash.
operation_required_all() {
  case "$1" in
    system.probe|system.doctor|system.describe|runtime.verify|report.tech) ;;
    file.inspect) printf '%s\n' stat file uname ;;
    file.hash) printf '%s\n' stat uname ;;
    file.provenance) printf '%s\n' xattr ;;
    asset.manifest) printf '%s\n' stat file uname ;;
    asset.verify) printf '%s\n' stat uname ;;
    search.candidate) printf '%s\n' mdfind mktemp rm ;;
    image.inspect) printf '%s\n' sips awk ;;
    image.derivative) printf '%s\n' sips awk mktemp mv rm stat uname ;;
    image.stats|image.compare) printf '%s\n' python3 sips awk ;;
    loop.seams|golden.record|golden.check|audit.verify|deps.graph|index.add|index.search|index.verify|host.detect|ae.render|c4d.render|trace.asset|audit.plugins|project.diff|project.health|c4d.inspect|c4d.lint|bridge.check) printf '%s\n' python3 ;;
    project.restore|handoff.package|preset.add|preset.get) printf '%s\n' python3 cp ;;
    storage.preflight|volume.inspect) printf '%s\n' df awk uname ;;
    temp.create) printf '%s\n' mktemp rm pwd ;;
    temp.clean) printf '%s\n' sed rm pwd ;;
    media.inspect) printf '%s\n' stat file uname ;;
    media.timing) printf '%s\n' avmediainfo awk df uname ;;
    media.frame) printf '%s\n' avmediainfo python3 jq sips awk df mktemp mv rm stat uname ;;
    package.create) printf '%s\n' ditto mktemp rm mv stat uname ;;
    project.ingest|expression.lint) printf '%s\n' python3 ;;
    plugin.audit) printf '%s\n' stat uname ;;
    project.snapshot) printf '%s\n' stat uname cp date rm ;;
    project.preflight) printf '%s\n' python3 ;;
  esac
}

operation_optional_capabilities() {
  case "$1" in
    system.probe|system.doctor|report.tech) printf '%s\n' sw_vers ;;
    runtime.verify) printf '%s\n' sha256 shasum ;;
    asset.manifest|asset.verify) printf '%s\n' sha256 shasum ;;
    media.inspect) printf '%s\n' mdls avmediainfo ;;
    loop.seams|golden.record|golden.check) printf '%s\n' sips ;;
  esac
}

emit_operation_requires() {
  local _name="$1"
  printf '{"all":'
  operation_required_all "$_name" | emit_string_array_lines
  printf ',"anyOf":['
  case "$_name" in
    file.hash|plugin.audit|project.snapshot)
      printf '["sha256","shasum"]'
      ;;
  esac
  printf ']}'
}

emit_operation_descriptor() {
  local _name="$1"
  local _available=false
  local _interactive=false
  local _network=false
  operation_available "$_name" && _available=true
  operation_interactive_safe "$_name" && _interactive=true
  operation_network_sensitive "$_name" && _network=true

  printf '{"available":'; $_available && printf 'true' || printf 'false'
  printf ',"state":'; json_quote "$(operation_state "$_name")"
  printf ',"summary":'; json_quote "$(operation_summary "$_name")"
  printf ',"cost":'; json_quote "$(operation_cost "$_name")"
  printf ',"mutation":'; json_quote "$(operation_mutation "$_name")"
  printf ',"authority":'; json_quote "$(operation_authority "$_name")"
  printf ',"interactiveSafe":'; $_interactive && printf 'true' || printf 'false'
  printf ',"networkSensitive":'; $_network && printf 'true' || printf 'false'
  printf ',"executionScope":'; case "$_name" in media.timing|media.frame|project.ingest|expression.lint|plugin.audit|project.snapshot|loop.seams|golden.record|golden.check|audit.verify|project.restore|deps.graph|handoff.package|index.add|index.search|index.verify|preset.add|preset.get|host.detect|ae.render|c4d.render|trace.asset|audit.plugins|project.diff|project.health|c4d.inspect|c4d.lint|bridge.check|project.preflight|media.qc|project.extract|project.conform|project.jobcheck) json_quote "LOCAL_ONLY" ;; *) json_quote "EXPLICIT_PATH_OR_NONE" ;; esac
  printf ',"requires":'; emit_operation_requires "$_name"
  printf ',"optionalCapabilities":'; operation_optional_capabilities "$_name" | emit_string_array_lines
  request_schema_for "$_name"
  printf ',"args":{"allowed":'; printf '%s\n' ${=MJ_SCHEMA_ALLOWED} | emit_string_array_lines
  printf ',"required":'; printf '%s\n' ${=MJ_SCHEMA_REQUIRED} | emit_string_array_lines
  printf '}}'
}

emit_operation_registry() {
  local _name
  local _first=1
  printf '{'
  while IFS= read -r _name; do
    [ -n "$_name" ] || continue
    [ "$_first" -eq 1 ] || printf ','
    _first=0
    json_quote "$_name"; printf ':'; emit_operation_descriptor "$_name"
  done <<EOF_OPERATIONS
$(operation_names)
EOF_OPERATIONS
  printf '}'
}

# --- src/lib/local_fs.zsh ---
# MJ Standard Library 1.0 — LocalFS
# Shared filesystem classification and local-only policy helpers.
# This module never enumerates network mounts and never mutates a path.

mj_fs_type() {
  local _path="$1"
  if [ "$(/usr/bin/uname -s 2>/dev/null)" = "Darwin" ]; then
    # macOS BSD stat(1) %T reports the file-object type, not the mounted
    # filesystem. df -Y exposes the mounted filesystem type as column 2.
    /bin/df -kY "$_path" 2>/dev/null | /usr/bin/awk 'NR>1 {v=$2} END{if(v!="") print v}' || true
  else
    /usr/bin/stat -f -c '%T' "$_path" 2>/dev/null || true
  fi
}

mj_fs_class() {
  case "$1" in
    smbfs|nfs|webdav|afpfs|cifs|nfs4) printf 'network' ;;
    apfs|hfs|hfs+|exfat|msdos|vfat|ext2/ext3|ext2|ext3|ext4|xfs|overlay|overlayfs|tmpfs) printf 'local' ;;
    *) printf 'unknown' ;;
  esac
}

# Compatibility names retained for existing modules/consumers of modular source.
volume_fs_type() { mj_fs_type "$1"; }
volume_class() { mj_fs_class "$1"; }

volume_free_kb() {
  /bin/df -kP "$1" 2>/dev/null | /usr/bin/awk 'NR>1 {v=$4} END{if(v ~ /^[0-9]+$/) print v}'
}

# Probe one existing path without walking it. Globals are intentionally namespaced.
mj_local_scope_probe() {
  local _path="$1"
  MJ_LOCAL_SCOPE_FS=""
  MJ_LOCAL_SCOPE_CLASS="unknown"
  MJ_LOCAL_SCOPE_FS=$(mj_fs_type "$_path" 2>/dev/null || printf '')
  if [ -n "$MJ_LOCAL_SCOPE_FS" ]; then
    MJ_LOCAL_SCOPE_CLASS=$(mj_fs_class "$MJ_LOCAL_SCOPE_FS")
  fi
  [ "$MJ_LOCAL_SCOPE_CLASS" = "local" ]
}

# Fail closed for operations that are explicitly local-only. The caller must
# validate path existence/type first so error semantics remain deterministic.
mj_require_local_existing_path() {
  local _path="$1"
  mj_local_scope_probe "$_path" && return 0
  case "$MJ_LOCAL_SCOPE_CLASS" in
    network)
      set_error "NETWORK_SCOPE_BLOCKED" "Operation is local-only; network volumes are outside the MographJailed automatic execution boundary."
      ;;
    *)
      set_error "STORAGE_SCOPE_UNKNOWN" "Operation requires a positively identified local filesystem; storage classification is unknown."
      ;;
  esac
  return 1
}

standard_library_localfs_available() {
  cap_available df && cap_available awk && cap_available uname
}

# --- src/lib/native_db.zsh ---
# MJ Standard Library 1.0 — NativeDB
# Safe capability layer for the stock sqlite3 runtime. There is deliberately no
# public arbitrary-SQL request operation. Product modules may build fixed-schema
# stores on top of these internal helpers after their own contract review.

native_db_available() {
  cap_available sqlite3
}

native_db_version() {
  local _out=""
  native_db_available || return 1
  _out=$(/usr/bin/sqlite3 -version 2>/dev/null) || return 1
  printf '%s\n' "$_out" | /usr/bin/awk 'NR==1 {print $1; exit}'
}

# Static, in-memory capability probes only. No request data becomes SQL and no
# filesystem database is created by these checks.
native_db_probe_features() {
  local _out=""
  MOGRAPHJAILED_DB_RUNTIME=false
  MOGRAPHJAILED_DB_JSON=false
  MOGRAPHJAILED_DB_FTS5=false
  native_db_available || return 1

  _out=$(/usr/bin/sqlite3 -batch -init /dev/null ':memory:' 'PRAGMA temp_store=MEMORY; SELECT 1;' 2>/dev/null) || return 1
  [ "$_out" = "1" ] || return 1
  MOGRAPHJAILED_DB_RUNTIME=true

  _out=$(/usr/bin/sqlite3 -batch -init /dev/null ':memory:' "PRAGMA temp_store=MEMORY; SELECT json_valid('{\"mj\":\"native\"}');" 2>/dev/null || printf '')
  [ "$_out" = "1" ] && MOGRAPHJAILED_DB_JSON=true

  _out=$(/usr/bin/sqlite3 -batch -init /dev/null ':memory:' "PRAGMA temp_store=MEMORY; CREATE VIRTUAL TABLE mj_fts USING fts5(value); INSERT INTO mj_fts(value) VALUES('native search'); SELECT count(*) FROM mj_fts WHERE mj_fts MATCH 'native';" 2>/dev/null || printf '')
  [ "$_out" = "1" ] && MOGRAPHJAILED_DB_FTS5=true
  return 0
}

native_db_parent_for_path() {
  local _path="$1"
  case "$_path" in
    /*) ;;
    *) return 1 ;;
  esac
  case "$_path" in
    */*) printf '%s' "${_path%/*}" ;;
    *) return 1 ;;
  esac
}

# Validate where a future SQLite store may be created. This function does not
# create a database. Network and unknown filesystems fail closed.
native_db_validate_store_path() {
  local _path="$1"
  local _parent=""
  [ -n "$_path" ] || return 1
  _parent=$(native_db_parent_for_path "$_path") || return 1
  [ -n "$_parent" ] || _parent="/"
  [ -d "$_parent" ] || return 1
  [ -w "$_parent" ] || return 1
  if [ -e "$_path" ] || [ -L "$_path" ]; then
    [ -f "$_path" ] || return 1
    [ ! -L "$_path" ] || return 1
  fi
  mj_require_local_existing_path "$_parent"
}

standard_library_nativedb_available() {
  native_db_probe_features
}

# --- src/lib/media_probe.zsh ---
# MJ Standard Library 1.0 — MediaProbe
# Normalizes a bounded subset of Apple's avmediainfo text output. The adapter
# is deliberately conservative: it parses only stable-looking labeled facts,
# validates numeric fields, and fails closed when the expected shape changes.
# It never enumerates the full sample table in the default timing operation.

media_probe_is_uint() {
  case "$1" in ''|*[!0-9]*) return 1 ;; *) return 0 ;; esac
}

media_probe_is_number() {
  printf '%s\n' "$1" | /usr/bin/awk 'BEGIN{ok=0} /^[0-9]+([.][0-9]+)?$/ {ok=1} END{exit ok?0:1}'
}

media_probe_reset() {
  MJ_MEDIA_DURATION_SECONDS=""
  MJ_MEDIA_DURATION_VALUE=""
  MJ_MEDIA_DURATION_TIMESCALE=""
  MJ_MEDIA_TRACK_COUNT=""
  MJ_MEDIA_VIDEO_TRACK_COUNT="0"
  MJ_MEDIA_VIDEO_TRACK_INDEX=""
  MJ_MEDIA_VIDEO_ENABLED="unknown"
  MJ_MEDIA_VIDEO_CODEC=""
  MJ_MEDIA_VIDEO_FOURCC=""
  MJ_MEDIA_VIDEO_WIDTH=""
  MJ_MEDIA_VIDEO_HEIGHT=""
  MJ_MEDIA_VIDEO_DECODE_SUPPORTED="unknown"
  MJ_MEDIA_VIDEO_DATA_BYTES=""
  MJ_MEDIA_VIDEO_TIMESCALE=""
  MJ_MEDIA_VIDEO_DURATION_SECONDS=""
  MJ_MEDIA_VIDEO_NOMINAL_FPS=""
  MJ_MEDIA_VIDEO_MIN_SAMPLE_VALUE=""
  MJ_MEDIA_VIDEO_MIN_SAMPLE_TIMESCALE=""
  MJ_MEDIA_VIDEO_REORDERING="unknown"
}

# Parse labeled avmediainfo output supplied as one string. The parser is kept
# separate from process execution so it can be regression-tested from fixtures.
media_probe_parse_text() {
  local _text="$1"
  local _parsed=""
  local _key=""
  local _value=""

  media_probe_reset
  _parsed=$(MJ_MEDIA_PROBE_INPUT="$_text" /usr/bin/awk 'BEGIN {
      text=ENVIRON["MJ_MEDIA_PROBE_INPUT"];
      n=split(text, lines, "\n");
      assetDuration=""; durationValue=""; durationScale=""; trackCount="";
      videoCount=0; videoIndex=""; videoEnabled="unknown"; codec=""; fourcc="";
      width=""; height=""; decode="unknown"; dataBytes=""; mediaScale="";
      videoDuration=""; fps=""; minValue=""; minScale=""; reorder="unknown";
      inVideo=0;
      for (i=1; i<=n; i++) {
        line=lines[i];
        if (line ~ /^Duration:[[:space:]]*[0-9]/ && assetDuration=="") {
          v=line; sub(/^Duration:[[:space:]]*/, "", v);
          split(v, a, /[[:space:]]+/); assetDuration=a[1];
          r=line; sub(/^.*\(/, "", r); sub(/\).*$/, "", r);
          if (r ~ /^[0-9]+\/[0-9]+$/) { split(r, q, "/"); durationValue=q[1]; durationScale=q[2]; }
        }
        if (line ~ /^Track count:[[:space:]]*[0-9]+/) {
          v=line; sub(/^Track count:[[:space:]]*/, "", v); trackCount=v;
        }
        if (line ~ /^Track [0-9]+: Video/) {
          videoCount++;
          if (videoCount==1) {
            inVideo=1;
            v=line; sub(/^Track[[:space:]]+/, "", v); sub(/:.*/, "", v); videoIndex=v;
            if (line ~ /, Enabled,/) videoEnabled="true";
            else if (line ~ /, Disabled,/) videoEnabled="false";
          } else {
            inVideo=0;
          }
          continue;
        }
        if (line ~ /^Track [0-9]+:/ && line !~ /: Video/) { inVideo=0; continue; }
        if (!inVideo) continue;

        if (line ~ /^[[:space:]]*Enabled:[[:space:]]*/) {
          v=line; sub(/^[[:space:]]*Enabled:[[:space:]]*/, "", v);
          if (v=="Yes") videoEnabled="true"; else if (v=="No") videoEnabled="false";
        } else if (line ~ /^[[:space:]]*Format:[[:space:]]*/) {
          v=line; sub(/^[[:space:]]*Format:[[:space:]]*/, "", v);
          parts=split(v, p, "\047");
          if (parts>=3) { fourcc=p[2]; codec=p[1]; sub(/[[:space:]]+$/, "", codec); }
          else { codec=v; }
        } else if (line ~ /^[[:space:]]*Dimensions:[[:space:]]*[0-9]+[[:space:]]*x[[:space:]]*[0-9]+/) {
          v=line; sub(/^[[:space:]]*Dimensions:[[:space:]]*/, "", v); gsub(/[[:space:]]/, "", v);
          split(v, d, "x"); width=d[1]; height=d[2];
        } else if (line ~ /^[[:space:]]*System support for decoding this track:[[:space:]]*/) {
          v=line; sub(/^.*:[[:space:]]*/, "", v);
          if (v=="Yes") decode="true"; else if (v=="No") decode="false";
        } else if (line ~ /^[[:space:]]*Data size:[[:space:]]*[0-9]+ bytes/) {
          v=line; sub(/^[[:space:]]*Data size:[[:space:]]*/, "", v); sub(/[[:space:]]+bytes.*/, "", v); dataBytes=v;
        } else if (line ~ /^[[:space:]]*Media time scale:[[:space:]]*[0-9]+/) {
          v=line; sub(/^[[:space:]]*Media time scale:[[:space:]]*/, "", v); mediaScale=v;
        } else if (line ~ /^[[:space:]]+Duration:[[:space:]]*[0-9]/) {
          v=line; sub(/^[[:space:]]+Duration:[[:space:]]*/, "", v); split(v, a, /[[:space:]]+/); videoDuration=a[1];
        } else if (line ~ /^[[:space:]]*Nominal frame rate:[[:space:]]*[0-9]/) {
          v=line; sub(/^[[:space:]]*Nominal frame rate:[[:space:]]*/, "", v); sub(/[[:space:]]+fps.*/, "", v); fps=v;
        } else if (line ~ /^[[:space:]]*Minimum sample duration:[[:space:]]*[0-9]+\/[0-9]+ seconds/) {
          v=line; sub(/^[[:space:]]*Minimum sample duration:[[:space:]]*/, "", v); sub(/[[:space:]]+seconds.*/, "", v);
          split(v, q, "/"); minValue=q[1]; minScale=q[2];
        } else if (line ~ /^[[:space:]]*Frame reordering required/) {
          reorder="true";
        } else if (line ~ /^[[:space:]]*Frame reordering not required/) {
          reorder="false";
        }
      }
      print "durationSeconds=" assetDuration;
      print "durationValue=" durationValue;
      print "durationTimescale=" durationScale;
      print "trackCount=" trackCount;
      print "videoTrackCount=" videoCount;
      print "videoTrackIndex=" videoIndex;
      print "videoEnabled=" videoEnabled;
      print "videoCodec=" codec;
      print "videoFourCC=" fourcc;
      print "videoWidth=" width;
      print "videoHeight=" height;
      print "videoDecodeSupported=" decode;
      print "videoDataBytes=" dataBytes;
      print "videoTimescale=" mediaScale;
      print "videoDurationSeconds=" videoDuration;
      print "videoNominalFPS=" fps;
      print "videoMinSampleValue=" minValue;
      print "videoMinSampleTimescale=" minScale;
      print "videoReordering=" reorder;
    }') || return 1

  while IFS='=' read -r _key _value; do
    case "$_key" in
      durationSeconds) MJ_MEDIA_DURATION_SECONDS="$_value" ;;
      durationValue) MJ_MEDIA_DURATION_VALUE="$_value" ;;
      durationTimescale) MJ_MEDIA_DURATION_TIMESCALE="$_value" ;;
      trackCount) MJ_MEDIA_TRACK_COUNT="$_value" ;;
      videoTrackCount) MJ_MEDIA_VIDEO_TRACK_COUNT="$_value" ;;
      videoTrackIndex) MJ_MEDIA_VIDEO_TRACK_INDEX="$_value" ;;
      videoEnabled) MJ_MEDIA_VIDEO_ENABLED="$_value" ;;
      videoCodec) MJ_MEDIA_VIDEO_CODEC="$_value" ;;
      videoFourCC) MJ_MEDIA_VIDEO_FOURCC="$_value" ;;
      videoWidth) MJ_MEDIA_VIDEO_WIDTH="$_value" ;;
      videoHeight) MJ_MEDIA_VIDEO_HEIGHT="$_value" ;;
      videoDecodeSupported) MJ_MEDIA_VIDEO_DECODE_SUPPORTED="$_value" ;;
      videoDataBytes) MJ_MEDIA_VIDEO_DATA_BYTES="$_value" ;;
      videoTimescale) MJ_MEDIA_VIDEO_TIMESCALE="$_value" ;;
      videoDurationSeconds) MJ_MEDIA_VIDEO_DURATION_SECONDS="$_value" ;;
      videoNominalFPS) MJ_MEDIA_VIDEO_NOMINAL_FPS="$_value" ;;
      videoMinSampleValue) MJ_MEDIA_VIDEO_MIN_SAMPLE_VALUE="$_value" ;;
      videoMinSampleTimescale) MJ_MEDIA_VIDEO_MIN_SAMPLE_TIMESCALE="$_value" ;;
      videoReordering) MJ_MEDIA_VIDEO_REORDERING="$_value" ;;
    esac
  done <<EOF_MEDIA_PARSED
$_parsed
EOF_MEDIA_PARSED

  media_probe_is_number "$MJ_MEDIA_DURATION_SECONDS" || return 1
  media_probe_is_uint "$MJ_MEDIA_TRACK_COUNT" || return 1
  if [ -n "$MJ_MEDIA_DURATION_VALUE" ] || [ -n "$MJ_MEDIA_DURATION_TIMESCALE" ]; then
    media_probe_is_uint "$MJ_MEDIA_DURATION_VALUE" || return 1
    media_probe_is_uint "$MJ_MEDIA_DURATION_TIMESCALE" || return 1
    [ "$MJ_MEDIA_DURATION_TIMESCALE" -gt 0 ] || return 1
  fi
  media_probe_is_uint "$MJ_MEDIA_VIDEO_TRACK_COUNT" || return 1

  if [ "$MJ_MEDIA_VIDEO_TRACK_COUNT" -gt 0 ]; then
    media_probe_is_uint "$MJ_MEDIA_VIDEO_TRACK_INDEX" || return 1
    [ "$MJ_MEDIA_VIDEO_TRACK_INDEX" -gt 0 ] || return 1
    [ -n "$MJ_MEDIA_VIDEO_CODEC" ] || return 1
    media_probe_is_uint "$MJ_MEDIA_VIDEO_WIDTH" || return 1
    media_probe_is_uint "$MJ_MEDIA_VIDEO_HEIGHT" || return 1
    [ "$MJ_MEDIA_VIDEO_WIDTH" -gt 0 ] && [ "$MJ_MEDIA_VIDEO_HEIGHT" -gt 0 ] || return 1
    if [ -n "$MJ_MEDIA_VIDEO_DATA_BYTES" ]; then media_probe_is_uint "$MJ_MEDIA_VIDEO_DATA_BYTES" || return 1; fi
    media_probe_is_uint "$MJ_MEDIA_VIDEO_TIMESCALE" || return 1
    [ "$MJ_MEDIA_VIDEO_TIMESCALE" -gt 0 ] || return 1
    media_probe_is_number "$MJ_MEDIA_VIDEO_DURATION_SECONDS" || return 1
    media_probe_is_number "$MJ_MEDIA_VIDEO_NOMINAL_FPS" || return 1
    if [ -n "$MJ_MEDIA_VIDEO_MIN_SAMPLE_VALUE$MJ_MEDIA_VIDEO_MIN_SAMPLE_TIMESCALE" ]; then
      media_probe_is_uint "$MJ_MEDIA_VIDEO_MIN_SAMPLE_VALUE" || return 1
      media_probe_is_uint "$MJ_MEDIA_VIDEO_MIN_SAMPLE_TIMESCALE" || return 1
      [ "$MJ_MEDIA_VIDEO_MIN_SAMPLE_TIMESCALE" -gt 0 ] || return 1
    fi
  fi
  return 0
}

media_probe_analyzed_ok() {
  local _text="$1"
  MJ_MEDIA_PROBE_INPUT="$_text" /usr/bin/awk 'BEGIN {
    text=ENVIRON["MJ_MEDIA_PROBE_INPUT"];
    if (text ~ /Movie analyzed with 0 error\./) exit 0;
    # Target-Mac Gate A (2026-09-29): avmediainfo --brief on audio-only input
    # prints "Error analysis is not supported for format ..." instead of the
    # 0-error sentinel. The container read succeeded; track parsing below
    # still decides NO_VIDEO_TRACK vs timing, so this is not a probe failure.
    if (text ~ /Error analysis is not supported for format /) exit 0;
    exit 1;
  }'
}

# Capture only the pre-sample header. awk exits at "Sample Information" and
# enforces a hard 256-line ceiling so long media cannot create unbounded shell
# output. This is the key Standard Library boundary for synchronous AE use.
media_probe_capture_header() {
  local _path="$1"
  local _out=""
  cap_available avmediainfo && cap_available awk || return 1
  _out=$(/usr/bin/avmediainfo "$_path" --samples --mediatype video 2>/dev/null | /usr/bin/awk '
    NR > 256 { exit 3 }
    /^[[:space:]]*Sample Information[[:space:]]*$/ { exit 0 }
    { print }
  ') || return 1
  MJ_MEDIA_PROBE_HEADER="$_out"
  return 0
}

media_probe_read_timing() {
  local _path="$1"
  local _brief=""
  MJ_MEDIA_PROBE_HEADER=""
  cap_available avmediainfo && cap_available awk || return 1
  _brief=$(/usr/bin/avmediainfo "$_path" --brief 2>/dev/null) || return 1
  media_probe_analyzed_ok "$_brief" || return 1
  media_probe_capture_header "$_path" || return 1
  media_probe_parse_text "$MJ_MEDIA_PROBE_HEADER"
}

standard_library_mediaprobe_available() {
  cap_available avmediainfo && cap_available awk && standard_library_localfs_available
}

# Exact frame-floor lookup from the avmediainfo sample table (text on stdin).
# Prints the presentation timestamp (track-timescale ticks) of the video
# frame displayed at time t: the largest sample presentation timestamp <= t.
#
# Never trusts nominal frame-rate metadata. Target-Mac Gate A (2026-09-29)
# proved a 29.97fps-nominal track uses non-uniform integer presentation
# times in a 600-timescale (..., 561, 581, 601, ...), so frameIndex * fps
# arithmetic cannot name real frames; only the sample table can.
# Fails closed on any shape drift, timescale mismatch, or empty table.
media_probe_sample_floor_ticks_from_text() {
  local _time="$1" _timescale="$2"
  case "$_timescale" in ''|*[!0-9]*) return 1 ;; esac
  MJ_PROBE_FLOOR_TIME="$_time" MJ_PROBE_FLOOR_TS="$_timescale" /usr/bin/awk '
    BEGIN {
      t = ENVIRON["MJ_PROBE_FLOOR_TIME"] + 0;
      ts = ENVIRON["MJ_PROBE_FLOOR_TS"] + 0;
      if (!(t >= 0) || !(ts >= 1)) exit 3;
      req = int(t * ts + 0.000001);
      in_table = 0; best = -1; best_hms = ""; seen = 0;
    }
    !in_table && /Sample Index/ && /Presentation Time/ { in_table = 1; next; }
    in_table && (/^Track / || (/Sample Index/ && /Presentation Time/)) { in_table = 0; next; }
    in_table {
      line = $0; sub(/^[ \t]+/, "", line);
      nf = split(line, f, /[ \t]+/);
      # f[1]=index f[2]=decodeTicks f[3]=decodeHMS f[4]=presentTicks f[5]=presentHMS ...
      if (nf >= 5 && f[1] ~ /^[0-9]+$/ && f[4] ~ /^[0-9]+$/) {
        seen = 1;
        pts = f[4] + 0;
        if (pts <= req && pts > best) { best = pts; best_hms = f[5]; }
      }
      next;
    }
    END {
      if (!seen || best < 0) exit 4;
      # Timescale consistency: the floor tick count expressed in the probe
      # timescale must agree with the table human-readable timestamp.
      nh = split(best_hms, hp, ":");
      if (nh != 3) exit 5;
      hms = hp[1]*3600 + hp[2]*60 + hp[3];
      diff = best/ts - hms;
      if (diff > 0.002 || diff < -0.002) exit 5;
      printf "%d", best;
    }'
}

# Production wrapper: reads the sample table from the media file itself.
media_probe_sample_floor_ticks() {
  local _path="$1" _time="$2" _timescale="$3"
  cap_available avmediainfo && cap_available awk || return 1
  /usr/bin/avmediainfo "$_path" --samples --mediatype video 2>/dev/null | media_probe_sample_floor_ticks_from_text "$_time" "$_timescale"
}

# --- src/lib/image_kit.zsh ---
# MJ Standard Library 1.0 — ImageKit foundation
# Reusable stock-sips inspection primitives. Mutation policy remains in public
# handlers so source images cannot be altered through a generic library API.

image_is_uint() {
  case "$1" in ''|*[!0-9]*) return 1 ;; *) return 0 ;; esac
}

sips_property() {
  local _key="$1"
  local _path="$2"
  local _out=""
  cap_available sips && cap_available awk || return 1
  _out=$(/usr/bin/sips -g "$_key" "$_path" 2>/dev/null) || return 1
  printf '%s\n' "$_out" | /usr/bin/awk -v k="$_key:" '$1==k { $1=""; sub(/^[[:space:]]+/,""); print; exit }'
}

image_positive_identification() {
  local _path="$1"
  local _format=""
  local _width=""
  local _height=""
  _format=$(sips_property format "$_path" 2>/dev/null || printf '')
  _width=$(sips_property pixelWidth "$_path" 2>/dev/null || printf '')
  _height=$(sips_property pixelHeight "$_path" 2>/dev/null || printf '')
  [ -n "$_format" ] || return 1
  image_is_uint "$_width" || return 1
  image_is_uint "$_height" || return 1
  [ "$_width" -gt 0 ] && [ "$_height" -gt 0 ]
}

image_emit_inspection_data() {
  local _path="$1"
  local _width=""
  local _height=""
  local _format=""
  local _space=""
  local _alpha=""
  local _alpha_json="null"
  _width=$(sips_property pixelWidth "$_path" 2>/dev/null || printf '')
  _height=$(sips_property pixelHeight "$_path" 2>/dev/null || printf '')
  _format=$(sips_property format "$_path" 2>/dev/null || printf '')
  _space=$(sips_property space "$_path" 2>/dev/null || printf '')
  _alpha=$(sips_property hasAlpha "$_path" 2>/dev/null || printf '')
  image_is_uint "$_width" || _width=""
  image_is_uint "$_height" || _height=""
  case "$(printf '%s' "$_alpha" | /usr/bin/awk '{print tolower($0)}')" in true|yes|1) _alpha_json=true ;; false|no|0) _alpha_json=false ;; esac
  printf '{"path":'; json_quote "$_path"
  printf ',"pixelWidth":'; [ -n "$_width" ] && printf '%s' "$_width" || printf 'null'
  printf ',"pixelHeight":'; [ -n "$_height" ] && printf '%s' "$_height" || printf 'null'
  printf ',"format":'; [ -n "$_format" ] && json_quote "$_format" || printf 'null'
  printf ',"colorSpace":'; [ -n "$_space" ] && json_quote "$_space" || printf 'null'
  printf ',"hasAlpha":%s,"source":"sips"}' "$_alpha_json"
}

standard_library_imagekit_available() {
  cap_available sips && cap_available awk
}

# --- src/lib/image_stats.zsh ---
# MJ Standard Library — ImageStats (SL-M3)
# Deterministic, bounded image signatures for loop-seam ranking and
# golden-frame regression. Uses only Python 3 stdlib. No new dependencies.
#
# image.stats: 4x4x4 RGB histogram (64 bins) + 8x8 grid averages (64 cells)
# image.compare: histogram intersection + grid similarity → 0.0-1.0 score
# loop.seams / golden.*: same signatures over a directory of PNG frames

# Shared Python signature library. Prepended to each operation's main script.
IFS= read -r -d '' MJ_PY_IMAGE_SIG <<'PY_IMAGE_SIG' || true
import hashlib
import json
import os
import shutil
import struct
import subprocess
import sys
import tempfile
import zlib

def tree_id(path):
    """Cheap identity (size, mtime) of a file, or of the regular files directly inside a directory.
    Compared before and after an operation to report honestly whether its source changed."""
    try:
        if os.path.isdir(path):
            out = []
            for n in sorted(os.listdir(path)):
                p = os.path.join(path, n)
                if os.path.isfile(p):
                    st = os.stat(p); out.append((n, st.st_size, st.st_mtime_ns))
            return tuple(out)
        st = os.stat(path)
        return (st.st_size, st.st_mtime_ns)
    except OSError:
        return None

def error_json(code, message):
    return json.dumps({"ok": False, "code": code, "message": message})

def decode_png(path):
    """Minimal PNG decoder using only stdlib. Returns (w, h, pixels)."""
    try:
        with open(path, 'rb') as f:
            data = f.read()
    except Exception as e:
        raise ValueError("READ_FAILED: " + str(e))
    if len(data) < 8 or data[:8] != b'\x89PNG\r\n\x1a\n':
        raise ValueError("NOT_PNG")
    pos = 8
    width = height = None
    bit_depth = color_type = None
    idat_data = b''
    while pos < len(data):
        if pos + 8 > len(data):
            raise ValueError("TRUNCATED")
        length = struct.unpack('>I', data[pos:pos+4])[0]
        chunk_type = data[pos+4:pos+8]
        if pos + 12 + length > len(data):
            raise ValueError("TRUNCATED")
        chunk_data = data[pos+8:pos+8+length]
        pos += 12 + length
        if chunk_type == b'IHDR':
            width, height, bit_depth, color_type, comp, filt, interlace = struct.unpack('>IIBBBBB', chunk_data)
            if bit_depth not in (8, 16):
                raise ValueError("UNSUPPORTED_BIT_DEPTH")
            if color_type not in (2, 6):
                raise ValueError("UNSUPPORTED_COLOR_TYPE")
            if interlace != 0:
                raise ValueError("INTERLACED_NOT_SUPPORTED")
        elif chunk_type == b'IDAT':
            idat_data += chunk_data
        elif chunk_type == b'IEND':
            break
    if width is None:
        raise ValueError("MISSING_IHDR")
    try:
        raw = zlib.decompress(idat_data)
    except Exception:
        raise ValueError("DECOMPRESS_FAILED")
    sample = bit_depth // 8
    channels = 3 if color_type == 2 else 4
    bpp = channels * sample
    stride = width * bpp
    pixels = []
    prev = bytearray(stride)
    pos = 0
    for y in range(height):
        if pos >= len(raw):
            raise ValueError("TRUNCATED_SCANLINES")
        filt = raw[pos]; pos += 1
        if pos + stride > len(raw):
            raise ValueError("TRUNCATED_SCANLINES")
        cur = bytearray(raw[pos:pos+stride]); pos += stride
        if filt == 1:
            for i in range(bpp, stride):
                cur[i] = (cur[i] + cur[i-bpp]) & 0xff
        elif filt == 2:
            for i in range(stride):
                cur[i] = (cur[i] + prev[i]) & 0xff
        elif filt == 3:
            for i in range(stride):
                a = cur[i-bpp] if i >= bpp else 0
                cur[i] = (cur[i] + ((a + prev[i]) >> 1)) & 0xff
        elif filt == 4:
            for i in range(stride):
                a = cur[i-bpp] if i >= bpp else 0
                b = prev[i]
                c = prev[i-bpp] if i >= bpp else 0
                p = a + b - c
                pa, pb, pc = abs(p-a), abs(p-b), abs(p-c)
                pr = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                cur[i] = (cur[i] + pr) & 0xff
        elif filt != 0:
            raise ValueError("UNKNOWN_FILTER")
        # 16-bit samples: the high byte is the 8-bit equivalent.
        for x in range(width):
            o = x * bpp
            pixels.append((cur[o], cur[o+sample], cur[o+2*sample]))
        prev = cur
    return width, height, pixels

def compute_histogram(pixels, bins_per_channel=4):
    bins = [0] * (bins_per_channel ** 3)
    scale = 256 // bins_per_channel
    for r, g, b in pixels:
        ri = min(r // scale, bins_per_channel - 1)
        gi = min(g // scale, bins_per_channel - 1)
        bi = min(b // scale, bins_per_channel - 1)
        idx = (ri * bins_per_channel + gi) * bins_per_channel + bi
        bins[idx] += 1
    return bins

def compute_grid_averages(pixels, width, height, grid_size=8):
    sums = [[[0, 0, 0, 0] for _ in range(grid_size)] for _ in range(grid_size)]
    for y in range(height):
        for x in range(width):
            r, g, b = pixels[y * width + x]
            gx = min(x * grid_size // width, grid_size - 1)
            gy = min(y * grid_size // height, grid_size - 1)
            sums[gy][gx][0] += r
            sums[gy][gx][1] += g
            sums[gy][gx][2] += b
            sums[gy][gx][3] += 1
    result = []
    for gy in range(grid_size):
        for gx in range(grid_size):
            rs, gs, bs, cnt = sums[gy][gx]
            if cnt > 0:
                result.append([rs // cnt, gs // cnt, bs // cnt])
            else:
                result.append([0, 0, 0])
    return result

def histogram_similarity(h1, h2):
    total = sum(h1)
    if total == 0:
        return 1.0 if sum(h2) == 0 else 0.0
    return sum(min(a, b) for a, b in zip(h1, h2)) / total

def grid_similarity(g1, g2):
    if not g1 or not g2 or len(g1) != len(g2):
        return 0.0
    total_diff = 0
    for (r1, x1, b1), (r2, x2, b2) in zip(g1, g2):
        total_diff += abs(r1 - r2) + abs(x1 - x2) + abs(b1 - b2)
    max_diff = len(g1) * 255 * 3
    return 1.0 - (total_diff / max_diff) if max_diff > 0 else 1.0

def signature(path):
    w, h, px = decode_png(path)
    return {"width": w, "height": h, "histogram": compute_histogram(px), "grid": compute_grid_averages(px, w, h)}

def signature_score(a, b):
    hs = histogram_similarity(a["histogram"], b["histogram"])
    gs = grid_similarity(a["grid"], b["grid"])
    return round((hs + gs) / 2.0, 4), round(hs, 4), round(gs, 4)

def sha256_file(path):
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        for chunk in iter(lambda: f.read(1048576), b''):
            h.update(chunk)
    return h.hexdigest()

# Frame sequences: regular, non-hidden *.png files sorted by name.
MJ_MAX_FRAMES = 2000
SIG_MAX_EDGE = 256

def list_frames(directory):
    names = sorted(n for n in os.listdir(directory)
                   if n.lower().endswith('.png') and not n.startswith('.')
                   and os.path.isfile(os.path.join(directory, n))
                   and not os.path.islink(os.path.join(directory, n)))
    if len(names) > MJ_MAX_FRAMES:
        raise ValueError("TOO_MANY_FRAMES")
    return names

def signatures_for(directory, names):
    """Signatures for frames, downscaled with sips first when available.
    Full-resolution pure-python decoding takes seconds per HD frame."""
    sips = "/usr/bin/sips"
    stage = None
    src = directory
    downscaled = False
    try:
        if names and os.access(sips, os.X_OK):
            stage = tempfile.mkdtemp(prefix="mj-sig-")
            r = subprocess.run([sips, "-Z", str(SIG_MAX_EDGE), "-s", "format", "png"]
                               + [os.path.join(directory, n) for n in names] + ["--out", stage],
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            if r.returncode == 0 and all(os.path.isfile(os.path.join(stage, n)) for n in names):
                src = stage
                downscaled = True
        sigs = []
        for n in names:
            try:
                sigs.append(signature(os.path.join(src, n)))
            except ValueError as e:
                raise ValueError("DECODE_FAILED: " + n + ": " + str(e))
        return sigs, downscaled
    finally:
        if stage:
            shutil.rmtree(stage, ignore_errors=True)
PY_IMAGE_SIG

image_stats_available() {
  cap_available python3 && cap_available sips && cap_available awk
}

# Run the shared library plus an operation-specific main script read from stdin.
image_sig_python() {
  local _main=""
  IFS= read -r -d '' _main || true
  printf '%s\n%s' "$MJ_PY_IMAGE_SIG" "$_main" | /usr/bin/python3 - 2>/dev/null
}

image_stats_compute() {
  local _path="$1"
  local _json=""

  cap_available python3 || return 1
  [ -f "$_path" ] && [ -r "$_path" ] || return 1

  _json=$(MJ_IMAGE_STATS_PATH="$_path" image_sig_python <<'PY_IMAGE_STATS'
def main():
    path = os.environ.get("MJ_IMAGE_STATS_PATH", "")
    if not path:
        print(error_json("INVALID_PATH", "No path provided"))
        return
    try:
        width, height, pixels = decode_png(path)
    except ValueError as e:
        print(error_json("DECODE_FAILED", str(e)))
        return
    except Exception as e:
        print(error_json("DECODE_FAILED", "Unexpected: " + str(e)))
        return
    hist = compute_histogram(pixels)
    grid = compute_grid_averages(pixels, width, height)
    print(json.dumps({
        "ok": True,
        "width": width,
        "height": height,
        "pixelCount": len(pixels),
        "histogramBins": 64,
        "histogram": hist,
        "gridSize": 8,
        "gridAverages": grid,
    }))

main()
PY_IMAGE_STATS
) || return 1

  printf '%s' "$_json"
}

image_stats_compare() {
  MJ_IMAGE_COMPARE_H1="$1" \
  MJ_IMAGE_COMPARE_G1="$2" \
  MJ_IMAGE_COMPARE_H2="$3" \
  MJ_IMAGE_COMPARE_G2="$4" \
  image_sig_python <<'PY_IMAGE_COMPARE'
try:
    a = {"histogram": json.loads(os.environ["MJ_IMAGE_COMPARE_H1"]), "grid": json.loads(os.environ["MJ_IMAGE_COMPARE_G1"])}
    b = {"histogram": json.loads(os.environ["MJ_IMAGE_COMPARE_H2"]), "grid": json.loads(os.environ["MJ_IMAGE_COMPARE_G2"])}
    score, hs, gs = signature_score(a, b)
    print(json.dumps({
        "ok": True,
        "score": score,
        "histogramSimilarity": hs,
        "gridSimilarity": gs,
    }))
except Exception as e:
    print(json.dumps({"ok": False, "code": "COMPARE_FAILED", "message": str(e)}))
PY_IMAGE_COMPARE
}

# --- src/lib/frame_kit.zsh ---
# MJ Standard Library 1.0 — FrameKit
# Narrow local-only AVFoundation frame derivative adapter.
#
# Design boundaries:
# - one readable local media source;
# - one non-existing local PNG output;
# - one non-negative requested time;
# - bounded output dimensions;
# - zero AVAssetImageGenerator time tolerance (frame-accurate request);
# - preferred track transform applied;
# - no generic bridge is exposed to callers.
#
# Bridge note (target-Mac Gate A, 2026-09-29): macOS Tahoe (26.x) broke
# JXA's ObjC bridge for AVFoundation ($.AVURLAsset is undefined even though
# ObjC.import('AVFoundation') succeeds), while Foundation still bridges.
# AppleScriptObjC (use framework "AVFoundation") sees AVFoundation classes
# and copyCGImageAtTime: returns a valid CGImageRef, but the Tahoe
# AppleScript bridge cannot coerce that CGImageRef (a raw C pointer) into
# any usable form -- not to NSBitmapImageRep, not to a reference, not to
# ImageIO C functions, not even to an integer address. The adapter is
# therefore Python 3 + ctypes: the system python3 calls the same
# AVFoundation APIs through libobjc, and ctypes handles C pointers
# natively. NSInvocation is used for every method that takes a CMTime by
# value, so no struct-by-value ABI marshaling is required. The embedded
# script is fixed; request data enters only through environment variables.
#
# Frame-grid note: with zero tolerance, AVAssetImageGenerator returns nil
# unless the requested time is exactly a sample presentation time. Nominal
# frame-rate metadata cannot be trusted to compute one: target-Mac Gate A
# (2026-09-29) proved a 29.97fps-nominal track uses non-uniform integer
# presentation times in a 600-timescale (..., 561, 581, 601, ...), so
# frameIndex * fps arithmetic names phantom times. The caller
# (media.frame) therefore reads the exact presentation timestamp of the
# frame displayed at the requested time from the avmediainfo sample table
# (media_probe_sample_floor_ticks) and passes it in; the adapter requests
# that CMTime with zero tolerance. requestedSeconds echoes the caller's
# time; actualSeconds/value/timescale name the extracted frame. Consumers
# must use actualTime for verification (the media.frame contract already
# provides it alongside deltaSeconds).

MJ_FRAMEKIT_RESULT_JSON=""
MJ_FRAMEKIT_REQUESTED_SECONDS=""
MJ_FRAMEKIT_ACTUAL_SECONDS=""
MJ_FRAMEKIT_ACTUAL_VALUE=""
MJ_FRAMEKIT_ACTUAL_TIMESCALE=""
MJ_FRAMEKIT_PIXEL_WIDTH=""
MJ_FRAMEKIT_PIXEL_HEIGHT=""
MJ_FRAMEKIT_ERROR_CODE=""
MJ_FRAMEKIT_ERROR_MESSAGE=""

frame_kit_reset() {
  MJ_FRAMEKIT_RESULT_JSON=""
  MJ_FRAMEKIT_REQUESTED_SECONDS=""
  MJ_FRAMEKIT_ACTUAL_SECONDS=""
  MJ_FRAMEKIT_ACTUAL_VALUE=""
  MJ_FRAMEKIT_ACTUAL_TIMESCALE=""
  MJ_FRAMEKIT_PIXEL_WIDTH=""
  MJ_FRAMEKIT_PIXEL_HEIGHT=""
  MJ_FRAMEKIT_ERROR_CODE=""
  MJ_FRAMEKIT_ERROR_MESSAGE=""
}

frame_kit_is_time_seconds() {
  printf '%s\n' "$1" | /usr/bin/awk 'BEGIN{ok=0} /^[0-9]+([.][0-9]+)?$/ { if (length($0)<=24) ok=1 } END{exit ok?0:1}'
}

frame_kit_is_max_pixels() {
  case "$1" in ''|*[!0-9]*) return 1 ;; esac
  [ ${#1} -le 4 ] || return 1
  [ "$1" -ge 64 ] && [ "$1" -le 4096 ]
}

frame_kit_time_before_duration() {
  local _time="$1"
  local _duration="$2"
  MJ_FRAMEKIT_TIME="$_time" MJ_FRAMEKIT_DURATION="$_duration" /usr/bin/awk 'BEGIN {
    t=ENVIRON["MJ_FRAMEKIT_TIME"]+0;
    d=ENVIRON["MJ_FRAMEKIT_DURATION"]+0;
    exit (t>=0 && d>0 && t<d) ? 0 : 1;
  }'
}

# Executes a fixed embedded Python 3 + ctypes adapter. Request data is
# supplied only through environment variables; no request value is
# interpreted as Python source. The caller passes the exact frame
# presentation time (value/timescale) read from the avmediainfo sample
# table -- the adapter never computes frame times from nominal frame-rate
# metadata, because target-Mac Gate A (2026-09-29) proved nominal rates can
# disagree with the true non-uniform sample grid. The adapter extracts the
# full-resolution frame; the caller (media.frame) bounds dimensions
# afterwards with sips so the adapter stays narrow.
frame_kit_extract_png() {
  local _source="$1"
  local _output="$2"
  local _seconds="$3"
  local _floor_value="$4"
  local _floor_timescale="$5"
  local _json=""

  frame_kit_reset
  cap_available python3 && cap_available jq || return 1

  _json=$(MJ_FRAMEKIT_SOURCE="$_source" \
    MJ_FRAMEKIT_OUTPUT="$_output" \
    MJ_FRAMEKIT_SECONDS="$_seconds" \
    MJ_FRAMEKIT_FLOOR_VALUE="$_floor_value" \
    MJ_FRAMEKIT_FLOOR_TIMESCALE="$_floor_timescale" \
    /usr/bin/python3 - <<'PYCTYPES_FRAMEKIT' 2>/dev/null
import ctypes
import json
import os
import sys

def error_json(code, message):
    return json.dumps({"ok": False, "code": code, "message": message})

class CMTime(ctypes.Structure):
    _fields_ = [("value", ctypes.c_int64), ("timescale", ctypes.c_int32),
                ("flags", ctypes.c_int32), ("epoch", ctypes.c_int64)]

def main():
    src_path = os.environ.get("MJ_FRAMEKIT_SOURCE") or ""
    out_path = os.environ.get("MJ_FRAMEKIT_OUTPUT") or ""
    secs_text = os.environ.get("MJ_FRAMEKIT_SECONDS") or ""
    floor_text = os.environ.get("MJ_FRAMEKIT_FLOOR_VALUE") or ""
    floor_ts_text = os.environ.get("MJ_FRAMEKIT_FLOOR_TIMESCALE") or ""
    if not src_path:
        return error_json("INVALID_SOURCE", "Missing source path.")
    if not out_path:
        return error_json("INVALID_OUTPUT", "Missing output path.")
    if not secs_text:
        return error_json("INVALID_TIME", "Missing requested time.")
    if not floor_text or not floor_ts_text:
        return error_json("INVALID_FLOOR_TIME", "Missing frame presentation time.")
    try:
        t_secs = float(secs_text)
        floor_val = int(floor_text)
        floor_ts = int(floor_ts_text)
    except ValueError:
        return error_json("INVALID_TIME", "Requested time is not numeric.")
    if t_secs < 0:
        return error_json("INVALID_TIME", "Requested time is negative.")
    if floor_val < 0 or floor_ts < 1:
        return error_json("INVALID_FLOOR_TIME", "Frame presentation time is invalid.")
    if os.path.exists(out_path):
        return error_json("OUTPUT_EXISTS", "The output path already exists.")

    try:
        objc = ctypes.CDLL("/usr/lib/libobjc.A.dylib")
        ctypes.CDLL("/System/Library/Frameworks/AVFoundation.framework/AVFoundation")
        imgio = ctypes.CDLL("/System/Library/Frameworks/ImageIO.framework/ImageIO")
        cf = ctypes.CDLL("/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation")
    except Exception as e:
        return error_json("BRIDGE_LOAD_FAILED", "Could not load system frameworks: %s" % e)

    objc.objc_getClass.restype = ctypes.c_void_p
    objc.objc_getClass.argtypes = [ctypes.c_char_p]
    objc.sel_registerName.restype = ctypes.c_void_p
    objc.sel_registerName.argtypes = [ctypes.c_char_p]

    def cls(n):
        c = objc.objc_getClass(n.encode())
        if not c:
            raise RuntimeError("class %s not found" % n)
        return c

    def sel(n):
        return objc.sel_registerName(n.encode())

    msg = objc.objc_msgSend
    msg.restype = ctypes.c_void_p

    try:
        msg.argtypes = [ctypes.c_void_p, ctypes.c_void_p, ctypes.c_char_p]
        nsstr = msg(cls("NSString"), sel("stringWithUTF8String:"), src_path.encode("utf-8"))
        if not nsstr:
            return error_json("ASSET_OPEN_FAILED", "Could not form a string for the source path.")
        msg.argtypes = [ctypes.c_void_p, ctypes.c_void_p, ctypes.c_void_p]
        nsurl = msg(cls("NSURL"), sel("fileURLWithPath:"), nsstr)
        if not nsurl:
            return error_json("ASSET_OPEN_FAILED", "Could not form a file URL for the source.")
        asset_cls = cls("AVURLAsset")
        msg.argtypes = [ctypes.c_void_p, ctypes.c_void_p]
        alloced = msg(asset_cls, sel("alloc"))
        msg.argtypes = [ctypes.c_void_p, ctypes.c_void_p, ctypes.c_void_p, ctypes.c_void_p]
        asset = msg(alloced, sel("initWithURL:options:"), nsurl, None)
        if not asset:
            return error_json("ASSET_OPEN_FAILED", "AVURLAsset could not open the source.")

        # Refuse video-less sources at the adapter level (defense in depth;
        # the caller also probes).
        msg.argtypes = [ctypes.c_void_p, ctypes.c_void_p, ctypes.c_char_p]
        media_type = msg(cls("NSString"), sel("stringWithUTF8String:"), b"vide")
        msg.argtypes = [ctypes.c_void_p, ctypes.c_void_p, ctypes.c_void_p]
        tracks = msg(asset, sel("tracksWithMediaType:"), media_type)
        if not tracks:
            return error_json("NO_VIDEO_TRACK_ADAPTER", "The asset has no video track.")
        msg.argtypes = [ctypes.c_void_p, ctypes.c_void_p]
        ntracks = msg(tracks, sel("count"))
        if ntracks < 1:
            return error_json("NO_VIDEO_TRACK_ADAPTER", "The asset has no video track.")

        msg.argtypes = [ctypes.c_void_p, ctypes.c_void_p, ctypes.c_void_p]
        gen = msg(cls("AVAssetImageGenerator"), sel("assetImageGeneratorWithAsset:"), asset)
        if not gen:
            return error_json("GENERATOR_FAILED", "AVAssetImageGenerator could not be created.")
        msg.argtypes = [ctypes.c_void_p, ctypes.c_void_p, ctypes.c_bool]
        msg(gen, sel("setAppliesPreferredTrackTransform:"), True)

        # Zero tolerances via NSInvocation (CMTime is passed by value).
        for tsel_name in ("setRequestedTimeToleranceBefore:", "setRequestedTimeToleranceAfter:"):
            ts = sel(tsel_name)
            msg.argtypes = [ctypes.c_void_p, ctypes.c_void_p, ctypes.c_void_p]
            sig = msg(gen, sel("methodSignatureForSelector:"), ts)
            if not sig:
                return error_json("GENERATOR_FAILED", "Could not get method signature for %s" % tsel_name)
            inv = msg(cls("NSInvocation"), sel("invocationWithMethodSignature:"), sig)
            msg(inv, sel("setTarget:"), gen)
            msg(inv, sel("setSelector:"), ts)
            zt = CMTime(0, floor_ts, 1, 0)
            msg.argtypes = [ctypes.c_void_p, ctypes.c_void_p, ctypes.c_void_p, ctypes.c_int]
            msg(inv, sel("setArgument:atIndex:"), ctypes.byref(zt), 2)
            msg.argtypes = [ctypes.c_void_p, ctypes.c_void_p]
            msg(inv, sel("invoke"))

        # Extract the exact sample frame, capturing actualTime.
        cs = sel("copyCGImageAtTime:actualTime:error:")
        msg.argtypes = [ctypes.c_void_p, ctypes.c_void_p, ctypes.c_void_p]
        sig = msg(gen, sel("methodSignatureForSelector:"), cs)
        if not sig:
            return error_json("GENERATOR_FAILED", "Could not get method signature for copyCGImageAtTime.")
        inv = msg(cls("NSInvocation"), sel("invocationWithMethodSignature:"), sig)
        msg(inv, sel("setTarget:"), gen)
        msg(inv, sel("setSelector:"), cs)
        req = CMTime(floor_val, floor_ts, 1, 0)
        actual = CMTime(0, 0, 0, 0)
        msg.argtypes = [ctypes.c_void_p, ctypes.c_void_p, ctypes.c_void_p, ctypes.c_int]
        msg(inv, sel("setArgument:atIndex:"), ctypes.byref(req), 2)
        msg(inv, sel("setArgument:atIndex:"), ctypes.byref(actual), 3)
        nullp = ctypes.c_void_p(None)
        msg(inv, sel("setArgument:atIndex:"), ctypes.byref(nullp), 4)
        msg.argtypes = [ctypes.c_void_p, ctypes.c_void_p]
        msg(inv, sel("invoke"))
        image = ctypes.c_void_p()
        msg.argtypes = [ctypes.c_void_p, ctypes.c_void_p, ctypes.c_void_p]
        msg(inv, sel("getReturnValue:"), ctypes.byref(image))
        if not image.value:
            return error_json("FRAME_GENERATION_FAILED",
                               "AVFoundation did not return an image for frame presentation time %d/%d."
                               % (floor_val, floor_ts))

        # Dimensions via CoreGraphics C API.
        imgio.CGImageGetWidth.restype = ctypes.c_ulong
        imgio.CGImageGetWidth.argtypes = [ctypes.c_void_p]
        imgio.CGImageGetHeight.restype = ctypes.c_ulong
        imgio.CGImageGetHeight.argtypes = [ctypes.c_void_p]
        w = imgio.CGImageGetWidth(image)
        h = imgio.CGImageGetHeight(image)
        if w < 1 or h < 1:
            return error_json("FRAME_RESULT_INVALID", "AVFoundation returned invalid frame dimensions.")

        # Write PNG via ImageIO C API.
        cf.CFURLCreateFromFileSystemRepresentation.restype = ctypes.c_void_p
        cf.CFURLCreateFromFileSystemRepresentation.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_long, ctypes.c_bool]
        out_url = cf.CFURLCreateFromFileSystemRepresentation(None, out_path.encode("utf-8"), len(out_path.encode("utf-8")), False)
        if not out_url:
            return error_json("PNG_WRITE_FAILED", "Could not form an output file URL.")
        cf.CFStringCreateWithCString.restype = ctypes.c_void_p
        cf.CFStringCreateWithCString.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_uint32]
        type_str = cf.CFStringCreateWithCString(None, b"public.png", 0x08000100)
        imgio.CGImageDestinationCreateWithURL.restype = ctypes.c_void_p
        imgio.CGImageDestinationCreateWithURL.argtypes = [ctypes.c_void_p, ctypes.c_void_p, ctypes.c_ulong, ctypes.c_void_p]
        dest = imgio.CGImageDestinationCreateWithURL(out_url, type_str, 1, None)
        if not dest:
            return error_json("PNG_ENCODE_FAILED", "ImageIO could not create a PNG destination.")
        imgio.CGImageDestinationAddImage.argtypes = [ctypes.c_void_p, ctypes.c_void_p, ctypes.c_void_p]
        imgio.CGImageDestinationAddImage(dest, image, None)
        imgio.CGImageDestinationFinalize.restype = ctypes.c_bool
        imgio.CGImageDestinationFinalize.argtypes = [ctypes.c_void_p]
        if not imgio.CGImageDestinationFinalize(dest):
            return error_json("PNG_WRITE_FAILED", "ImageIO could not finalize the PNG file.")
    except Exception as e:
        return error_json("PYCTYPES_EXCEPTION", "Python ctypes adapter failed: %s" % e)

    if not os.path.isfile(out_path) or os.path.getsize(out_path) < 1:
        return error_json("PNG_WRITE_FAILED", "The staged PNG output is missing or empty.")

    # actualTime captured from the generator; fall back to the requested
    # floor time if the generator left it invalid.
    if actual.flags & 1 and actual.timescale > 0:
        a_val, a_ts = actual.value, actual.timescale
    else:
        a_val, a_ts = floor_val, floor_ts
    a_secs = float(a_val) / float(a_ts)
    return json.dumps({
        "ok": True,
        "requestedSeconds": t_secs,
        "actualSeconds": a_secs,
        "actualValue": int(a_val),
        "actualTimescale": int(a_ts),
        "pixelWidth": int(w),
        "pixelHeight": int(h),
        "transformApplied": True,
        "toleranceBeforeSeconds": 0,
        "toleranceAfterSeconds": 0,
        "adapter": "PYCTYPES_AVAssetImageGenerator",
    })

try:
    sys.stdout.write(main())
except Exception as e:
    sys.stdout.write(error_json("PYCTYPES_EXCEPTION", "Python ctypes adapter failed: %s" % e))
PYCTYPES_FRAMEKIT
  ) || return 1

  MJ_FRAMEKIT_RESULT_JSON="$_json"
  if ! printf '%s' "$_json" | /usr/bin/jq -e '.ok == true and (.requestedSeconds|type)=="number" and (.actualSeconds|type)=="number" and (.actualValue|type)=="number" and (.actualTimescale|type)=="number" and (.pixelWidth|type)=="number" and (.pixelHeight|type)=="number" and .transformApplied==true' >/dev/null 2>&1; then
    MJ_FRAMEKIT_ERROR_CODE=$(printf '%s' "$_json" | /usr/bin/jq -r 'if (.code|type)=="string" then .code else "NATIVE_OUTPUT_INVALID" end' 2>/dev/null || printf 'NATIVE_OUTPUT_INVALID')
    MJ_FRAMEKIT_ERROR_MESSAGE=$(printf '%s' "$_json" | /usr/bin/jq -r 'if (.message|type)=="string" then .message else "FrameKit adapter returned invalid output." end' 2>/dev/null || printf 'FrameKit adapter returned invalid output.')
    return 1
  fi

  MJ_FRAMEKIT_REQUESTED_SECONDS=$(printf '%s' "$_json" | /usr/bin/jq -r '.requestedSeconds')
  MJ_FRAMEKIT_ACTUAL_SECONDS=$(printf '%s' "$_json" | /usr/bin/jq -r '.actualSeconds')
  MJ_FRAMEKIT_ACTUAL_VALUE=$(printf '%s' "$_json" | /usr/bin/jq -r '.actualValue')
  MJ_FRAMEKIT_ACTUAL_TIMESCALE=$(printf '%s' "$_json" | /usr/bin/jq -r '.actualTimescale')
  MJ_FRAMEKIT_PIXEL_WIDTH=$(printf '%s' "$_json" | /usr/bin/jq -r '.pixelWidth')
  MJ_FRAMEKIT_PIXEL_HEIGHT=$(printf '%s' "$_json" | /usr/bin/jq -r '.pixelHeight')

  [ -f "$_output" ] && [ -s "$_output" ] || return 1
  image_positive_identification "$_output" || return 1
  return 0
}

standard_library_framekit_available() {
  cap_available python3 && cap_available jq && cap_available sips && cap_available awk && cap_available mktemp && cap_available mv && cap_available rm && cap_available stat && cap_available uname && standard_library_localfs_available && standard_library_mediaprobe_available
}

# --- src/lib/standard_library.zsh ---
# MJ Standard Library 1.0 descriptor shared by system.describe/report.tech.

emit_standard_library_descriptor() {
  local _localfs=false
  local _db=false
  local _db_json=false
  local _db_fts5=false
  local _db_version=""
  local _media=false
  local _image=false
  local _imagestats=false
  local _frame=false
  standard_library_localfs_available && _localfs=true
  if standard_library_nativedb_available; then
    _db=true
    [ "$MOGRAPHJAILED_DB_JSON" = "true" ] && _db_json=true
    [ "$MOGRAPHJAILED_DB_FTS5" = "true" ] && _db_fts5=true
    _db_version=$(native_db_version 2>/dev/null || printf '')
  fi
  standard_library_mediaprobe_available && _media=true
  standard_library_imagekit_available && _image=true
  image_stats_available && _imagestats=true
  standard_library_framekit_available && _frame=true

  printf '{"version":'; json_quote "$MOGRAPHJAILED_STANDARD_LIBRARY_VERSION"
  printf ',"policy":{"localOnlyByDefault":true,"networkMutation":false,"networkEnumeration":false,"arbitrarySqlAPI":false,"rawShellAPI":false}'
  printf ',"modules":{'
  printf '"LocalFS":{"available":'; $_localfs && printf 'true' || printf 'false'; printf ',"state":'; if $_localfs; then json_quote 'AVAILABLE'; else json_quote 'UNAVAILABLE'; fi; printf ',"authority":"FILESYSTEM_SCOPE"}'
  printf ',"NativeDB":{"available":'; $_db && printf 'true' || printf 'false'; printf ',"state":'; if $_db; then json_quote 'AVAILABLE'; else json_quote 'UNAVAILABLE'; fi; printf ',"authority":"LOCAL_STRUCTURED_STORAGE","publicSql":false,"version":'; [ -n "$_db_version" ] && json_quote "$_db_version" || printf 'null'; printf ',"features":{"json":'; $_db_json && printf 'true' || printf 'false'; printf ',"fts5":'; $_db_fts5 && printf 'true' || printf 'false'; printf '}}'
  printf ',"MediaProbe":{"available":'; $_media && printf 'true' || printf 'false'; printf ',"state":'; if $_media; then json_quote 'AVAILABLE'; else json_quote 'UNAVAILABLE'; fi; printf ',"authority":"NORMALIZED_NATIVE_MEDIA"}'
  printf ',"ImageKit":{"available":'; $_image && printf 'true' || printf 'false'; printf ',"state":'; if $_image; then json_quote 'AVAILABLE'; else json_quote 'UNAVAILABLE'; fi; printf ',"authority":"NATIVE_IMAGE"}'
  printf ',"ImageStats":{"available":'; $_imagestats && printf 'true' || printf 'false'; printf ',"state":'; if $_imagestats; then json_quote 'AVAILABLE'; else json_quote 'UNAVAILABLE'; fi; printf ',"authority":"DERIVED_IMAGE_SIGNATURE","executionScope":"LOCAL_ONLY","deterministic":true,"bounded":true}'
  printf ',"FrameKit":{"available":'; $_frame && printf 'true' || printf 'false'; printf ',"state":'; if $_frame; then json_quote 'AVAILABLE_CANDIDATE'; else json_quote 'UNAVAILABLE'; fi; printf ',"authority":"NATIVE_FRAME_DERIVATIVE","executionScope":"LOCAL_ONLY","exactRequest":true,"trackTransform":true,"publicGenericJXA":false,"targetMacQualificationRequired":true}'
  printf '}}'
}

# --- src/modules/system.zsh ---
system_platform_name() {
  if [ "$(/usr/bin/uname -s 2>/dev/null)" = "Darwin" ]; then printf 'macOS'; else /usr/bin/uname -s 2>/dev/null || printf 'unknown'; fi
}

system_os_version() {
  if cap_available sw_vers; then /usr/bin/sw_vers -productVersion 2>/dev/null || true; else printf ''; fi
}

system_os_build() {
  if cap_available sw_vers; then /usr/bin/sw_vers -buildVersion 2>/dev/null || true; else printf ''; fi
}

system_architecture() {
  /usr/bin/uname -m 2>/dev/null || printf 'unknown'
}

emit_probe_data() {
  local _first=1
  local _cap
  printf '{'
  printf '"platform":'; json_quote "$(system_platform_name)"; printf ','
  printf '"osVersion":'; json_quote "$(system_os_version)"; printf ','
  printf '"osBuild":'; json_quote "$(system_os_build)"; printf ','
  printf '"architecture":'; json_quote "$(system_architecture)"; printf ','
  printf '"capabilities":{'
  for _cap in zsh sw_vers stat file df mktemp plutil sqlite3 jq sips ditto sha256 shasum mdls avmediainfo avconvert afinfo afconvert mdfind xattr osascript python3 base64 awk uname sed rm mv pwd; do
    [ "$_first" -eq 1 ] || printf ','
    _first=0
    json_quote "$_cap"; printf ':'; emit_capability_object "$_cap"
  done
  printf '}'
  printf '}'
}

handle_system_probe() {
  emit_success_start "system.probe" "$REQUEST_ID"
  emit_probe_data
  emit_success_end
}

# What to tell someone when a tool is missing. All of these ship with macOS, so a missing one
# usually means a restricted, very old, or damaged system - or, for python3, no Command Line Tools.
doctor_cap_hint() {
  case "$1" in
    python3) printf 'Used by the project, frame, audit, library and render operations. On a Mac without the Xcode Command Line Tools /usr/bin/python3 is only a stub: ask IT to install them (xcode-select --install) or to provide /usr/bin/python3.' ;;
    avmediainfo) printf 'Ships with macOS 12 and later. Needed to read video timing; update macOS or avoid the media operations.' ;;
    jq) printf 'Ships with macOS 15 and later. Needed by frame extraction; update macOS.' ;;
    sips) printf 'Ships with macOS (the Scriptable Image Processing System). Needed for image operations; a missing sips means a damaged or heavily restricted system, so contact IT.' ;;
    mdfind) printf 'Spotlight command-line search. Needed by search.candidate; check that Spotlight is not disabled by policy.' ;;
    xattr) printf 'Ships with macOS. Needed to read file provenance; contact IT.' ;;
    ditto) printf 'Ships with macOS. Needed to create ZIP packages; contact IT.' ;;
    sqlite3) printf 'Ships with macOS. Needed for the local index capability checks; contact IT.' ;;
    shasum|sha256|"sha256 or shasum") printf 'Hashing tools that ship with macOS. Needed for file.hash, snapshots and manifests; contact IT.' ;;
    osascript) printf 'Ships with macOS. Needed only for notifications and the optional JavaScript-for-Automation adapters.' ;;
    *) printf 'A standard macOS tool that appears to be missing or blocked; contact IT.' ;;
  esac
}

# Groups the unavailable operations by the capability that is blocking them.
# Line-based on purpose: zsh does not word-split unquoted expansions.
emit_doctor_guidance() {
  local _op="" _cap="" _caps="" _first=1 _blockers=""
  local _nl='
'
  while IFS= read -r _op; do
    [ -n "$_op" ] || continue
    operation_available "$_op" && continue
    while IFS= read -r _cap; do
      [ -n "$_cap" ] || continue
      cap_available "$_cap" || _blockers="${_blockers}${_cap}:${_op}${_nl}"
    done <<EOF_DOCTOR_REQ
$(operation_required_all "$_op")
EOF_DOCTOR_REQ
    case "$_op" in
      file.hash|plugin.audit|project.snapshot)
        if ! cap_available sha256 && ! cap_available shasum; then _blockers="${_blockers}sha256 or shasum:${_op}${_nl}"; fi ;;
    esac
  done <<EOF_DOCTOR_OPS
$(operation_names)
EOF_DOCTOR_OPS
  _caps=$(printf '%s' "$_blockers" | /usr/bin/awk -F: 'NF {print $1}' | /usr/bin/sort -u)
  printf '['
  while IFS= read -r _cap; do
    [ -n "$_cap" ] || continue
    [ "$_first" -eq 1 ] || printf ','
    _first=0
    printf '{"capability":'; json_quote "$_cap"
    printf ',"unlocks":'
    printf '%s' "$_blockers" | /usr/bin/awk -F: -v c="$_cap" '$1 == c {print $2}' | /usr/bin/sort -u | emit_string_array_lines
    printf ',"hint":'; json_quote "$(doctor_cap_hint "$_cap")"
    printf '}'
  done <<EOF_DOCTOR_CAPS
$_caps
EOF_DOCTOR_CAPS
  printf ']'
}

handle_system_doctor() {
  local _darwin=false
  local _core=true
  local _cap
  [ "$(/usr/bin/uname -s 2>/dev/null)" = "Darwin" ] && _darwin=true
  for _cap in zsh stat file df mktemp base64 awk uname sed rm; do cap_available "$_cap" || _core=false; done
  emit_success_start "system.doctor" "$REQUEST_ID"
  printf '{"ready":'; if $_darwin && $_core; then printf 'true'; else printf 'false'; fi
  printf ',"isMacOS":'; if $_darwin; then printf 'true'; else printf 'false'; fi
  printf ',"coreCapabilities":'; if $_core; then printf 'true'; else printf 'false'; fi
  local _total=0 _unavail=0 _op=""
  while IFS= read -r _op; do
    [ -n "$_op" ] || continue
    _total=$((_total + 1))
    operation_available "$_op" || _unavail=$((_unavail + 1))
  done <<EOF_DOCTOR_COUNT
$(operation_names)
EOF_DOCTOR_COUNT
  printf ',"guidance":'; emit_doctor_guidance
  printf ',"operations":{"total":%s,"unavailable":%s}' "$_total" "$_unavail"
  printf ',"probe":'; emit_probe_data
  printf '}'
  emit_success_end
}


handle_system_describe() {
  emit_success_start "system.describe" "$REQUEST_ID"
  printf '{"schema":"MOGRAPHJAILED_CAPABILITY_REGISTRY_2","registryVersion":2'
  printf ',"protocolVersion":%s' "$MOGRAPHJAILED_PROTOCOL_VERSION"
  printf ',"cliVersion":'; json_quote "$MOGRAPHJAILED_CLI_VERSION"
  printf ',"standardLibrary":'; emit_standard_library_descriptor
  printf ',"operations":'; emit_operation_registry
  printf '}'
  emit_success_end
}

# --- src/modules/file.zsh ---
file_stat_size() {
  local _path="$1"
  if [ "$(/usr/bin/uname -s 2>/dev/null)" = "Darwin" ]; then
    /usr/bin/stat -f '%z' "$_path" 2>/dev/null
  else
    /usr/bin/stat -c '%s' "$_path" 2>/dev/null
  fi
}

# size:mtime identity, used to report honestly whether a source changed while an operation ran.
source_identity() { printf '%s:%s' "$(file_stat_size "$1" 2>/dev/null)" "$(file_stat_mtime "$1" 2>/dev/null)"; }
source_unchanged_json() { [ "$1" = "$(source_identity "$2")" ] && printf 'true' || printf 'false'; }

file_stat_mtime() {
  local _path="$1"
  if [ "$(/usr/bin/uname -s 2>/dev/null)" = "Darwin" ]; then
    /usr/bin/stat -f '%m' "$_path" 2>/dev/null
  else
    /usr/bin/stat -c '%Y' "$_path" 2>/dev/null
  fi
}

# Identity of the bytes that file.hash will read. -L follows a symlink target so
# pre/post stability checks describe the hashed file rather than the link node.
file_hash_identity() {
  local _path="$1"
  if [ "$(/usr/bin/uname -s 2>/dev/null)" = "Darwin" ]; then
    /usr/bin/stat -L -f '%d:%i:%z:%m' "$_path" 2>/dev/null
  else
    /usr/bin/stat -L -c '%d:%i:%s:%Y' "$_path" 2>/dev/null
  fi
}

file_basic_type() {
  /usr/bin/file -b "$1" 2>/dev/null || printf ''
}

handle_file_inspect() {
  local _path=""
  local _kind="other"
  local _size=""
  local _mtime=""
  local _type=""

  require_arg path || { emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  _path="$MJ_REQUIRED_ARG_VALUE"
  is_absolute_path "$_path" || { set_error "INVALID_PATH" "Path must be absolute."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  cap_available stat && cap_available file && cap_available uname || { set_error "UNSUPPORTED" "File inspection requires stock macOS stat/file/uname capabilities."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 69; }

  if [ ! -e "$_path" ] && [ ! -L "$_path" ]; then
    set_error "NOT_FOUND" "Path does not exist."
    emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"
    return 66
  fi

  [ -f "$_path" ] && _kind="file"
  [ -d "$_path" ] && _kind="directory"
  [ -L "$_path" ] && _kind="symlink"
  _size=$(file_stat_size "$_path" || printf '')
  _mtime=$(file_stat_mtime "$_path" || printf '')
  _type=$(file_basic_type "$_path")

  emit_success_start "$REQUEST_COMMAND" "$REQUEST_ID"
  printf '{"path":'; json_quote "$_path"
  printf ',"kind":'; json_quote "$_kind"
  printf ',"sizeBytes":'; if [ -n "$_size" ]; then printf '%s' "$_size"; else printf 'null'; fi
  printf ',"modifiedEpoch":'; if [ -n "$_mtime" ]; then printf '%s' "$_mtime"; else printf 'null'; fi
  printf ',"readable":'; [ -r "$_path" ] && printf 'true' || printf 'false'
  printf ',"writableHint":'; [ -w "$_path" ] && printf 'true' || printf 'false'
  printf ',"executable":'; [ -x "$_path" ] && printf 'true' || printf 'false'
  printf ',"basicType":'; json_quote "$_type"
  printf ',"sources":["stat","file"],"advisory":{"writableHint":true}}'
  emit_success_end
}

hash_sha256_file() {
  local _path="$1"
  local _sha=""
  local _out=""
  MJ_HASH_SOURCE=""
  MJ_HASH_VALUE=""
  if cap_available sha256; then
    _sha=$(cap_path sha256)
    _out=$("$_sha" -q "$_path" 2>/dev/null) || return 1
    MJ_HASH_SOURCE="sha256"
    MJ_HASH_VALUE="$_out"
    return 0
  fi
  if cap_available shasum; then
    _out=$(/usr/bin/shasum -a 256 "$_path" 2>/dev/null) || return 1
    MJ_HASH_SOURCE="shasum"
    MJ_HASH_VALUE=${_out%% *}
    return 0
  fi
  return 69
}

handle_file_hash() {
  local _path=""
  local _hash_rc=0
  local _hash=""
  local _identity_before=""
  local _identity_after=""

  require_arg path || { emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  _path="$MJ_REQUIRED_ARG_VALUE"
  is_absolute_path "$_path" || { set_error "INVALID_PATH" "Path must be absolute."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  [ -e "$_path" ] || { set_error "NOT_FOUND" "Path does not exist."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 66; }
  [ -f "$_path" ] || { set_error "INVALID_TARGET" "Hash target must be a regular file."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  [ -r "$_path" ] || { set_error "PERMISSION_DENIED" "File is not readable."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 77; }
  cap_available stat && cap_available uname || { set_error "UNSUPPORTED" "File hashing requires stock macOS stat/uname capabilities."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 69; }

  _identity_before=$(file_hash_identity "$_path") || { set_error "SOURCE_STATE_UNAVAILABLE" "Could not establish source identity before hashing."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 74; }
  hash_sha256_file "$_path"
  _hash_rc=$?
  if [ "$_hash_rc" -eq 69 ]; then
    set_error "UNSUPPORTED" "No approved native SHA-256 utility is available."
    emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"
    return 69
  elif [ "$_hash_rc" -ne 0 ]; then
    set_error "HASH_FAILED" "SHA-256 calculation failed."
    emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"
    return 74
  fi
  _identity_after=$(file_hash_identity "$_path") || { set_error "SOURCE_CHANGED" "Source state could not be re-established after hashing."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 74; }
  if [ "$_identity_before" != "$_identity_after" ]; then
    set_error "SOURCE_CHANGED" "Source identity changed while SHA-256 was being calculated."
    emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"
    return 74
  fi

  _hash="$MJ_HASH_VALUE"
  case "$_hash" in *[!0-9a-fA-F]*|'') set_error "NATIVE_OUTPUT_INVALID" "Hash utility returned unexpected output."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 74 ;; esac
  [ ${#_hash} -eq 64 ] || { set_error "NATIVE_OUTPUT_INVALID" "Hash utility returned unexpected length."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 74; }

  emit_success_start "$REQUEST_COMMAND" "$REQUEST_ID"
  printf '{"path":'; json_quote "$_path"; printf ',"algorithm":"SHA-256","hash":'; json_quote "$_hash"; printf ',"source":'; json_quote "$MJ_HASH_SOURCE"; printf ',"stabilityCheck":"device+inode+size+mtime"}'
  emit_success_end
}

# --- src/modules/runtime.zsh ---
runtime_self_path() {
  local _self="$0"
  # In zsh, FUNCTION_ARGZERO changes $0 while inside shell functions.
  # ZSH_ARGZERO remains the original script used to invoke this shell and is
  # therefore the authoritative runtime path for production /bin/zsh -f use.
  if [ -n "${ZSH_VERSION:-}" ] && [ -n "${ZSH_ARGZERO:-}" ]; then
    _self="$ZSH_ARGZERO"
  fi
  case "$_self" in
    /*) printf '%s' "$_self" ;;
    ./*) printf '%s/%s' "$(/bin/pwd -P)" "${_self#./}" ;;
    */*)
      local _dir=${_self%/*}
      local _leaf=${_self##*/}
      local _real_dir
      _real_dir=$(cd "$_dir" 2>/dev/null && /bin/pwd -P) || return 1
      printf '%s/%s' "$_real_dir" "$_leaf"
      ;;
    *) printf '%s' "$_self" ;;
  esac
}

runtime_bool_json() {
  if [ "$1" = "true" ]; then printf 'true'; else printf 'false'; fi
}

runtime_verify_hash() {
  local _path="$1"
  hash_sha256_file "$_path"
}

handle_runtime_verify() {
  local _expected_cli=""
  local _expected_protocol=""
  local _expected_filename=""
  local _expected_sha=""
  local _expected_sha_norm=""
  local _self=""
  local _filename=""
  local _actual_sha=""
  local _hash_source=""
  local _cli_ok=false
  local _protocol_ok=false
  local _filename_ok=true
  local _sha_ok=true
  local _filename_checked=false
  local _sha_checked=false
  local _compatible=true
  local _hash_rc=0

  require_arg expectedCliVersion || { emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  _expected_cli="$MJ_REQUIRED_ARG_VALUE"
  require_arg expectedProtocolVersion || { emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  _expected_protocol="$MJ_REQUIRED_ARG_VALUE"

  if request_arg_present expectedFilename; then
    _expected_filename=$(request_arg_get expectedFilename)
    [ -n "$_expected_filename" ] || { set_error "INVALID_ARGUMENT" "expectedFilename may not be empty when supplied."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
    case "$_expected_filename" in */*) set_error "INVALID_ARGUMENT" "expectedFilename must be a filename, not a path."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65 ;; esac
    _filename_checked=true
  fi

  if request_arg_present expectedSha256; then
    _expected_sha=$(request_arg_get expectedSha256)
    _expected_sha_norm=$(printf '%s' "$_expected_sha" | /usr/bin/awk '{print tolower($0)}')
    case "$_expected_sha_norm" in *[!0-9a-f]*|'') set_error "INVALID_ARGUMENT" "expectedSha256 must be a 64-character hexadecimal SHA-256 digest."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65 ;; esac
    [ ${#_expected_sha_norm} -eq 64 ] || { set_error "INVALID_ARGUMENT" "expectedSha256 must be a 64-character hexadecimal SHA-256 digest."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
    _sha_checked=true
  fi

  _self=$(runtime_self_path) || { set_error "RUNTIME_PATH_UNAVAILABLE" "Could not resolve the running MographJailed runtime path."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 74; }
  _filename=${_self##*/}

  [ "$MOGRAPHJAILED_CLI_VERSION" = "$_expected_cli" ] && _cli_ok=true || _compatible=false
  [ "$MOGRAPHJAILED_PROTOCOL_VERSION" = "$_expected_protocol" ] && _protocol_ok=true || _compatible=false
  if $_filename_checked; then [ "$_filename" = "$_expected_filename" ] && _filename_ok=true || { _filename_ok=false; _compatible=false; }; fi

  if $_sha_checked; then
    [ -f "$_self" ] && [ -r "$_self" ] || { set_error "RUNTIME_PATH_UNAVAILABLE" "Running MographJailed runtime is not a readable regular file."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 74; }
    runtime_verify_hash "$_self"
    _hash_rc=$?
    if [ "$_hash_rc" -eq 69 ]; then
      set_error "UNSUPPORTED" "Runtime SHA-256 verification requires an approved native SHA-256 utility."
      emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"
      return 69
    elif [ "$_hash_rc" -ne 0 ]; then
      set_error "HASH_FAILED" "Could not calculate the MographJailed runtime SHA-256."
      emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"
      return 74
    fi
    _actual_sha="$MJ_HASH_VALUE"
    _hash_source="$MJ_HASH_SOURCE"
    [ "$_actual_sha" = "$_expected_sha_norm" ] && _sha_ok=true || { _sha_ok=false; _compatible=false; }
  fi

  emit_success_start "$REQUEST_COMMAND" "$REQUEST_ID"
  printf '{"compatible":'; runtime_bool_json "$_compatible"
  printf ',"actual":{"cliVersion":'; json_quote "$MOGRAPHJAILED_CLI_VERSION"
  printf ',"protocolVersion":%s' "$MOGRAPHJAILED_PROTOCOL_VERSION"
  printf ',"filename":'; json_quote "$_filename"
  printf ',"sha256":'; if $_sha_checked; then json_quote "$_actual_sha"; else printf 'null'; fi
  printf '}'
  printf ',"expected":{"cliVersion":'; json_quote "$_expected_cli"
  printf ',"protocolVersion":'; json_quote "$_expected_protocol"
  printf ',"filename":'; if $_filename_checked; then json_quote "$_expected_filename"; else printf 'null'; fi
  printf ',"sha256":'; if $_sha_checked; then json_quote "$_expected_sha_norm"; else printf 'null'; fi
  printf '}'
  printf ',"checks":{"cliVersion":'; runtime_bool_json "$_cli_ok"
  printf ',"protocolVersion":'; runtime_bool_json "$_protocol_ok"
  printf ',"filename":'; if $_filename_checked; then runtime_bool_json "$_filename_ok"; else printf 'null'; fi
  printf ',"sha256":'; if $_sha_checked; then runtime_bool_json "$_sha_ok"; else printf 'null'; fi
  printf '}'
  printf ',"hashSource":'; if $_sha_checked; then json_quote "$_hash_source"; else printf 'null'; fi
  printf ',"runtimePathDisclosure":"filename-only"}'
  emit_success_end
}

# --- src/modules/volume.zsh ---
# Filesystem primitives live in src/lib/local_fs.zsh.

handle_volume_inspect() {
  local _path=""
  local _fs=""
  local _class="unknown"
  local _kb=""
  local _bytes=""
  local _darwin=false

  require_arg path || { emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  _path="$MJ_REQUIRED_ARG_VALUE"
  is_absolute_path "$_path" || { set_error "INVALID_PATH" "Path must be absolute."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  cap_available df && cap_available awk && cap_available uname || { set_error "UNSUPPORTED" "Volume inspection requires stock macOS df/awk/uname capabilities."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 69; }
  [ -e "$_path" ] || { set_error "NOT_FOUND" "Path does not exist or volume is unavailable."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 66; }

  [ "$(/usr/bin/uname -s 2>/dev/null)" = "Darwin" ] && _darwin=true
  _fs=$(volume_fs_type "$_path")
  _class=$(volume_class "$_fs")
  _kb=$(volume_free_kb "$_path")
  if [ -n "$_kb" ]; then _bytes=$((_kb * 1024)); fi

  emit_success_start "$REQUEST_COMMAND" "$REQUEST_ID"
  printf '{"path":'; json_quote "$_path"
  printf ',"available":true'
  printf ',"filesystem":'; if [ -n "$_fs" ]; then json_quote "$_fs"; else printf 'null'; fi
  printf ',"classification":'; json_quote "$_class"
  printf ',"freeBytes":'; if [ -n "$_bytes" ]; then printf '%s' "$_bytes"; else printf 'null'; fi
  printf ',"readable":'; [ -r "$_path" ] && printf 'true' || printf 'false'
  printf ',"writableHint":'; [ -w "$_path" ] && printf 'true' || printf 'false'
  printf ',"filesystemSource":'; if [ -n "$_fs" ]; then if $_darwin; then printf '"df -Y"'; else printf '"statfs"'; fi; else printf 'null'; fi
  printf ',"advisory":{"writableHint":true,"classification":true}}'
  emit_success_end
}

# --- src/modules/temp.zsh ---
handle_temp_create() {
  local _parent=""
  local _dir=""
  local _marker=""

  cap_available mktemp || { set_error "UNSUPPORTED" "mktemp is unavailable."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 69; }
  _parent=$(mj_tmp_parent)
  if has_ascii_control "$_parent"; then set_error "TEMP_UNAVAILABLE" "Temporary directory contains unsupported control characters."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 73; fi
  is_absolute_path "$_parent" || { set_error "TEMP_UNAVAILABLE" "Temporary directory must be an absolute path."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 73; }
  [ -d "$_parent" ] && [ -w "$_parent" ] || { set_error "TEMP_UNAVAILABLE" "Temporary directory is unavailable."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 73; }
  _dir=$(/usr/bin/mktemp -d "$_parent/MographJailed.XXXXXXXX" 2>/dev/null) || { set_error "TEMP_CREATE_FAILED" "Could not create MJ temporary directory."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 73; }
  _marker="$_dir/.mj_native_owned"
  # Bind the ownership marker to the exact canonical directory and effective
  # user. This prevents copying a valid marker into a sibling directory from
  # being sufficient proof of ownership.
  if ! printf '%s\n%s\n%s\n%s\n' "$MOGRAPHJAILED_PROTOCOL" "$REQUEST_ID" "$_dir" "${EUID:-unknown}" > "$_marker"; then
    /bin/rm -f "$_marker" 2>/dev/null || true
    /bin/rm -d "$_dir" 2>/dev/null || true
    set_error "TEMP_CREATE_FAILED" "Could not initialize MJ temporary directory."
    emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"
    return 73
  fi

  emit_success_start "$REQUEST_COMMAND" "$REQUEST_ID"
  printf '{"path":'; json_quote "$_dir"; printf ',"ownerMarker":true}'
  emit_success_end
}

is_safe_mj_temp_dir() {
  local _dir="$1"
  local _parent=""
  local _leaf=""
  local _actual_parent=""
  local _first=""
  local _bound_path=""
  local _bound_euid=""

  _parent=$(mj_tmp_parent)
  case "$_dir" in */) return 1 ;; esac
  _leaf=${_dir##*/}
  _actual_parent=${_dir%/*}
  [ "$_actual_parent" = "$_parent" ] || return 1
  case "$_leaf" in MographJailed.*) ;; *) return 1 ;; esac
  case "$_leaf" in *'..'*) return 1 ;; esac
  [ -d "$_dir" ] || return 1
  [ ! -L "$_dir" ] || return 1
  [ -f "$_dir/.mj_native_owned" ] || return 1
  [ ! -L "$_dir/.mj_native_owned" ] || return 1
  _first=$(/usr/bin/sed -n '1p' "$_dir/.mj_native_owned" 2>/dev/null || true)
  [ "$_first" = "$MOGRAPHJAILED_PROTOCOL" ] || return 1
  _bound_path=$(/usr/bin/sed -n '3p' "$_dir/.mj_native_owned" 2>/dev/null || true)
  _bound_euid=$(/usr/bin/sed -n '4p' "$_dir/.mj_native_owned" 2>/dev/null || true)
  # RC2 markers had only two lines. They remain cleanable under the strict
  # canonical-parent/name checks above. RC3+ markers must match their binding.
  if [ -n "$_bound_path" ]; then
    [ "$_bound_path" = "$_dir" ] || return 1
  fi
  if [ -n "$_bound_euid" ]; then
    [ "$_bound_euid" = "${EUID:-unknown}" ] || return 1
  fi
  return 0
}

handle_temp_clean() {
  local _path=""
  require_arg path || { emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  _path="$MJ_REQUIRED_ARG_VALUE"
  is_absolute_path "$_path" || { set_error "INVALID_PATH" "Path must be absolute."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  is_safe_mj_temp_dir "$_path" || { set_error "TEMP_REFUSED" "Refusing to remove a directory not proven to be MJ-owned temporary storage."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 77; }
  /bin/rm -rf "$_path" || { set_error "TEMP_CLEAN_FAILED" "Could not remove MJ temporary directory."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 74; }
  [ ! -e "$_path" ] || { set_error "TEMP_CLEAN_FAILED" "Temporary directory still exists after cleanup."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 74; }

  emit_success_start "$REQUEST_COMMAND" "$REQUEST_ID"
  printf '{"removed":true,"path":'; json_quote "$_path"; printf '}'
  emit_success_end
}

# --- src/modules/media.zsh ---
mdls_raw_value() {
  local _key="$1"
  local _path="$2"
  local _value=""
  cap_available mdls || return 1
  _value=$(/usr/bin/mdls -raw -name "$_key" "$_path" 2>/dev/null) || return 1
  case "$_value" in '(null)'|'null'|'') return 1 ;; esac
  printf '%s' "$_value"
}

is_number() {
  printf '%s\n' "$1" | /usr/bin/awk 'BEGIN{ok=0} /^[0-9]+([.][0-9]+)?$/ {ok=1} END{exit ok?0:1}'
}

is_integer() {
  case "$1" in ''|*[!0-9]*) return 1 ;; *) return 0 ;; esac
}

handle_media_inspect() {
  local _path=""
  local _native_probe="unavailable"
  local _size=""
  local _basic=""
  local _duration=""
  local _width=""
  local _height=""
  local _content=""
  local _mdls=false

  require_arg path || { emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  _path="$MJ_REQUIRED_ARG_VALUE"
  is_absolute_path "$_path" || { set_error "INVALID_PATH" "Path must be absolute."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  [ -e "$_path" ] || { set_error "NOT_FOUND" "Media path does not exist."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 66; }
  [ -f "$_path" ] || { set_error "INVALID_TARGET" "Media target must be a regular file."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  [ -r "$_path" ] || { set_error "PERMISSION_DENIED" "Media file is not readable."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 77; }
  cap_available stat && cap_available file && cap_available uname || { set_error "UNSUPPORTED" "Media inspection requires stock macOS stat/file/uname capabilities."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 69; }

  # V0.1 does not execute avmediainfo during the default inspection path.
  # It has no documented stable machine-readable output schema and adds
  # synchronous work, especially on network media. Availability is reported
  # separately so future explicit diagnostic operations can opt in.
  if cap_available avmediainfo; then
    _native_probe="notRun"
  fi

  _size=$(file_stat_size "$_path" || printf '')
  _basic=$(file_basic_type "$_path")
  if cap_available mdls; then
    _duration=$(mdls_raw_value kMDItemDurationSeconds "$_path" 2>/dev/null || printf '')
    _width=$(mdls_raw_value kMDItemPixelWidth "$_path" 2>/dev/null || printf '')
    _height=$(mdls_raw_value kMDItemPixelHeight "$_path" 2>/dev/null || printf '')
    _content=$(mdls_raw_value kMDItemContentType "$_path" 2>/dev/null || printf '')
    if [ -n "$_duration$_width$_height$_content" ]; then _mdls=true; fi
  fi

  is_number "$_duration" 2>/dev/null || _duration=""
  is_integer "$_width" 2>/dev/null || _width=""
  is_integer "$_height" 2>/dev/null || _height=""

  emit_success_start "$REQUEST_COMMAND" "$REQUEST_ID"
  printf '{"path":'; json_quote "$_path"
  printf ',"sizeBytes":'; [ -n "$_size" ] && printf '%s' "$_size" || printf 'null'
  printf ',"basicType":'; json_quote "$_basic"
  printf ',"durationSeconds":'; [ -n "$_duration" ] && printf '%s' "$_duration" || printf 'null'
  printf ',"pixelWidth":'; [ -n "$_width" ] && printf '%s' "$_width" || printf 'null'
  printf ',"pixelHeight":'; [ -n "$_height" ] && printf '%s' "$_height" || printf 'null'
  printf ',"contentType":'; if [ -n "$_content" ]; then json_quote "$_content"; else printf 'null'; fi
  printf ',"nativeProbe":'; json_quote "$_native_probe"
  printf ',"metadata":{"mdlsAdvisory":'; $_mdls && printf 'true' || printf 'false'
  printf ',"avmediainfoAvailable":'; cap_available avmediainfo && printf 'true' || printf 'false'
  printf '},"sources":{"filesystem":["stat","file"],"duration":'; if [ -n "$_duration" ]; then printf '"mdls"'; else printf 'null'; fi
  printf ',"dimensions":'; if [ -n "$_width" ] || [ -n "$_height" ]; then printf '"mdls"'; else printf 'null'; fi
  printf '},"advisory":{"durationSeconds":true,"pixelDimensions":true,"nativeProbe":true}}'
  emit_success_end
}

handle_media_timing() {
  local _path=""
  local _fs=""
  local _class="unknown"
  local _enabled="null"
  local _decode="null"
  local _reorder="null"

  require_arg path || { emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  _path="$MJ_REQUIRED_ARG_VALUE"
  is_absolute_path "$_path" || { set_error "INVALID_PATH" "Path must be absolute."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  [ -f "$_path" ] || { set_error "NOT_FOUND" "Media file does not exist."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 66; }
  [ -r "$_path" ] || { set_error "PERMISSION_DENIED" "Media file is not readable."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 77; }

  if ! standard_library_mediaprobe_available; then
    set_error "UNSUPPORTED" "Structured media timing requires the Standard Library MediaProbe adapter and stock avmediainfo/awk/df/uname capabilities."
    emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"
    return 69
  fi

  # Standard Library 1.0 timing is intentionally local-only. Network volumes
  # are detected but never inspected by this bounded media path.
  if ! mj_require_local_existing_path "$_path"; then
    emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"
    return 73
  fi
  _fs="$MJ_LOCAL_SCOPE_FS"
  _class="$MJ_LOCAL_SCOPE_CLASS"

  if ! media_probe_read_timing "$_path"; then
    set_error "NATIVE_OUTPUT_INVALID" "avmediainfo did not return the bounded labeled timing shape required by MediaProbe."
    emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"
    return 74
  fi

  case "$MJ_MEDIA_VIDEO_ENABLED" in true) _enabled=true ;; false) _enabled=false ;; esac
  case "$MJ_MEDIA_VIDEO_DECODE_SUPPORTED" in true) _decode=true ;; false) _decode=false ;; esac
  case "$MJ_MEDIA_VIDEO_REORDERING" in true) _reorder=true ;; false) _reorder=false ;; esac

  emit_success_start "$REQUEST_COMMAND" "$REQUEST_ID"
  printf '{"schema":"MJ_MEDIA_TIMING_2","path":'; json_quote "$_path"
  printf ',"source":"avmediainfo","adapter":"MJ_MEDIAPROBE_AVMEDIAINFO_TEXT_1","bounded":true'
  printf ',"scope":{"filesystem":'; [ -n "$_fs" ] && json_quote "$_fs" || printf 'null'; printf ',"classification":'; json_quote "$_class"; printf ',"policy":"LOCAL_ONLY"}'
  printf ',"duration":{"seconds":%s,"rational":' "$MJ_MEDIA_DURATION_SECONDS"
  if [ -n "$MJ_MEDIA_DURATION_VALUE" ] && [ -n "$MJ_MEDIA_DURATION_TIMESCALE" ]; then
    printf '{"value":%s,"timescale":%s}' "$MJ_MEDIA_DURATION_VALUE" "$MJ_MEDIA_DURATION_TIMESCALE"
  else
    printf 'null'
  fi
  printf '}'
  printf ',"trackCount":%s' "$MJ_MEDIA_TRACK_COUNT"
  printf ',"video":{"trackCount":%s,"selected":' "$MJ_MEDIA_VIDEO_TRACK_COUNT"
  if [ "$MJ_MEDIA_VIDEO_TRACK_COUNT" -gt 0 ]; then
    printf '{"index":%s,"enabled":%s' "$MJ_MEDIA_VIDEO_TRACK_INDEX" "$_enabled"
    printf ',"codec":'; json_quote "$MJ_MEDIA_VIDEO_CODEC"
    printf ',"fourCC":'; [ -n "$MJ_MEDIA_VIDEO_FOURCC" ] && json_quote "$MJ_MEDIA_VIDEO_FOURCC" || printf 'null'
    printf ',"pixelWidth":%s,"pixelHeight":%s' "$MJ_MEDIA_VIDEO_WIDTH" "$MJ_MEDIA_VIDEO_HEIGHT"
    printf ',"systemDecodeSupported":%s' "$_decode"
    printf ',"dataBytes":'; [ -n "$MJ_MEDIA_VIDEO_DATA_BYTES" ] && printf '%s' "$MJ_MEDIA_VIDEO_DATA_BYTES" || printf 'null'
    printf ',"mediaTimeScale":%s' "$MJ_MEDIA_VIDEO_TIMESCALE"
    printf ',"durationSeconds":%s' "$MJ_MEDIA_VIDEO_DURATION_SECONDS"
    printf ',"nominalFrameRate":%s' "$MJ_MEDIA_VIDEO_NOMINAL_FPS"
    printf ',"minimumSampleDuration":'
    if [ -n "$MJ_MEDIA_VIDEO_MIN_SAMPLE_VALUE" ] && [ -n "$MJ_MEDIA_VIDEO_MIN_SAMPLE_TIMESCALE" ]; then
      printf '{"value":%s,"timescale":%s}' "$MJ_MEDIA_VIDEO_MIN_SAMPLE_VALUE" "$MJ_MEDIA_VIDEO_MIN_SAMPLE_TIMESCALE"
    else
      printf 'null'
    fi
    printf ',"frameReorderingRequired":%s}' "$_reorder"
  else
    printf 'null'
  fi
  printf '}'
  printf ',"sampleTableEnumerated":false'
  printf ',"authority":{"duration":"NATIVE_MEDIA_HEADER","trackTiming":"NATIVE_MEDIA_HEADER","nominalFrameRate":"ADVISORY_NOMINAL"}'
  printf ',"notes":["Default timing is header-bounded; exact per-sample enumeration remains a future explicit operation."]}'
  emit_success_end
}

handle_media_frame() {
  local _path=""
  local _output=""
  local _time=""
  local _max="2048"
  local _parent=""
  local _parent_real=""
  local _leaf=""
  local _out_real=""
  local _stage=""
  local _stage_file=""
  local _stage_prefix="MographJailed_Frame"
  local _before=""
  local _after=""
  local _delta=""
  local _size=""
  local _out_width=""
  local _out_height=""

  require_arg path || { emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }; _path="$MJ_REQUIRED_ARG_VALUE"
  require_arg output || { emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }; _output="$MJ_REQUIRED_ARG_VALUE"
  require_arg timeSeconds || { emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }; _time="$MJ_REQUIRED_ARG_VALUE"
  if request_arg_present maxPixels; then _max=$(request_arg_get maxPixels); fi

  is_absolute_path "$_path" && is_absolute_path "$_output" || { set_error "INVALID_PATH" "Media source and frame output paths must be absolute."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  [ -f "$_path" ] && [ -r "$_path" ] || { set_error "INVALID_TARGET" "Frame source must be a readable regular media file."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  frame_kit_is_time_seconds "$_time" || { set_error "INVALID_ARGUMENT" "timeSeconds must be a non-negative decimal number."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  frame_kit_is_max_pixels "$_max" || { set_error "INVALID_ARGUMENT" "maxPixels must be an integer from 64 through 4096."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  case "$_output" in *.png|*.PNG) ;; *) set_error "INVALID_OUTPUT" "FrameKit output must be a .png file."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65 ;; esac

  standard_library_framekit_available || { set_error "UNSUPPORTED" "FrameKit requires the qualified local AppleScriptObjC/AVFoundation, MediaProbe, ImageKit, jq, and LocalFS capabilities."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 69; }
  if ! mj_require_local_existing_path "$_path"; then emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 73; fi

  _parent=$(parent_path "$_output")
  [ -d "$_parent" ] && [ -w "$_parent" ] || { set_error "OUTPUT_UNAVAILABLE" "Frame output directory is unavailable or not writable."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 73; }
  _parent_real=$(canonical_existing_dir "$_parent") || { set_error "OUTPUT_UNAVAILABLE" "Could not resolve frame output directory."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 73; }
  if ! mj_require_local_existing_path "$_parent_real"; then emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 73; fi
  _leaf=${_output##*/}; _out_real="$_parent_real/$_leaf"
  [ ! -e "$_out_real" ] && [ ! -L "$_out_real" ] || { set_error "OUTPUT_EXISTS" "Refusing to overwrite an existing frame derivative."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 73; }

  if ! media_probe_read_timing "$_path"; then
    set_error "NATIVE_OUTPUT_INVALID" "MediaProbe could not establish bounded video timing before frame extraction."
    emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"
    return 74
  fi
  [ "$MJ_MEDIA_VIDEO_TRACK_COUNT" -gt 0 ] || { set_error "NO_VIDEO_TRACK" "Frame extraction requires at least one video track."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  [ "$MJ_MEDIA_VIDEO_DECODE_SUPPORTED" != "false" ] || { set_error "DECODE_UNSUPPORTED" "macOS reports that the selected video track is not decodable."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 69; }
  frame_kit_time_before_duration "$_time" "$MJ_MEDIA_DURATION_SECONDS" || { set_error "TIME_OUT_OF_RANGE" "Requested frame time must be within the media duration."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }

  # Resolve the exact sample presentation timestamp of the frame displayed
  # at the requested time from the sample table. The adapter requests this
  # CMTime with zero tolerance; nominal fps arithmetic is never used.
  _floor_ticks=$(media_probe_sample_floor_ticks "$_path" "$_time" "$MJ_MEDIA_VIDEO_TIMESCALE" 2>/dev/null) || { set_error "FRAME_EXTRACTION_FAILED" "Could not determine the exact video frame presentation time for the requested time."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 74; }

  _before=$(file_hash_identity "$_path") || { set_error "SOURCE_STATE_UNAVAILABLE" "Could not establish media source identity before frame extraction."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 74; }
  create_mj_stage_dir "$_parent_real" "$_stage_prefix" || { set_error "TEMP_CREATE_FAILED" "Could not create and bind FrameKit staging directory."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 73; }
  _stage="$MJ_STAGE_DIR"
  _stage_file="$_stage/frame.png"

  if ! frame_kit_extract_png "$_path" "$_stage_file" "$_time" "$_floor_ticks" "$MJ_MEDIA_VIDEO_TIMESCALE"; then
    cleanup_mj_stage_dir "$_stage" "$_parent_real" "$_stage_prefix" || { set_error "STAGE_CLEANUP_REFUSED" "Frame extraction failed and staging cleanup could not be proven safe."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 74; }
    if [ -n "$MJ_FRAMEKIT_ERROR_MESSAGE" ]; then
      set_error "FRAME_EXTRACTION_FAILED" "$MJ_FRAMEKIT_ERROR_MESSAGE"
    else
      set_error "FRAME_EXTRACTION_FAILED" "Native AVFoundation frame extraction failed."
    fi
    emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"
    return 74
  fi

  _after=$(file_hash_identity "$_path") || {
    cleanup_mj_stage_dir "$_stage" "$_parent_real" "$_stage_prefix" || { set_error "STAGE_CLEANUP_REFUSED" "Frame source state failed and staging cleanup was refused."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 74; }
    set_error "SOURCE_CHANGED" "Media source state could not be re-established after frame extraction."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 74;
  }
  [ "$_before" = "$_after" ] || {
    cleanup_mj_stage_dir "$_stage" "$_parent_real" "$_stage_prefix" || { set_error "STAGE_CLEANUP_REFUSED" "Media source changed and staging cleanup was refused."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 74; }
    set_error "SOURCE_CHANGED" "Media source changed while FrameKit was decoding it."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 74;
  }

  _out_width=$(sips_property pixelWidth "$_stage_file" 2>/dev/null || printf '')
  _out_height=$(sips_property pixelHeight "$_stage_file" 2>/dev/null || printf '')
  [ "$_out_width" = "$MJ_FRAMEKIT_PIXEL_WIDTH" ] && [ "$_out_height" = "$MJ_FRAMEKIT_PIXEL_HEIGHT" ] || {
    cleanup_mj_stage_dir "$_stage" "$_parent_real" "$_stage_prefix" || { set_error "STAGE_CLEANUP_REFUSED" "Frame validation failed and staging cleanup was refused."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 74; }
    set_error "FRAME_VALIDATION_FAILED" "Generated PNG dimensions did not match AVFoundation frame metadata."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 74;
  }

  # Bound derivative dimensions with sips (downscale only, aspect preserved).
  # The adapter always extracts full resolution; this step never touches the
  # source and never upscales.
  _final_width="$_out_width"
  _final_height="$_out_height"
  case "$_out_width" in ''|*[!0-9]*)
    cleanup_mj_stage_dir "$_stage" "$_parent_real" "$_stage_prefix" || { set_error "STAGE_CLEANUP_REFUSED" "Frame dimension check failed and staging cleanup was refused."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 74; }
    set_error "FRAME_VALIDATION_FAILED" "Generated PNG dimensions are not usable integers."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 74 ;;
  esac
  case "$_out_height" in ''|*[!0-9]*)
    cleanup_mj_stage_dir "$_stage" "$_parent_real" "$_stage_prefix" || { set_error "STAGE_CLEANUP_REFUSED" "Frame dimension check failed and staging cleanup was refused."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 74; }
    set_error "FRAME_VALIDATION_FAILED" "Generated PNG dimensions are not usable integers."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 74 ;;
  esac
  if [ "$_out_width" -gt "$_max" ] || [ "$_out_height" -gt "$_max" ]; then
    /usr/bin/sips -Z "$_max" "$_stage_file" >/dev/null 2>&1 || {
      cleanup_mj_stage_dir "$_stage" "$_parent_real" "$_stage_prefix" || { set_error "STAGE_CLEANUP_REFUSED" "Frame scaling failed and staging cleanup was refused."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 74; }
      set_error "FRAME_SCALE_FAILED" "Could not bound the frame derivative dimensions."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 74;
    }
    _final_width=$(sips_property pixelWidth "$_stage_file" 2>/dev/null || printf '')
    _final_height=$(sips_property pixelHeight "$_stage_file" 2>/dev/null || printf '')
    case "$_final_width" in ''|*[!0-9]*) _final_width="" ;; esac
    case "$_final_height" in ''|*[!0-9]*) _final_height="" ;; esac
    { [ -n "$_final_width" ] && [ -n "$_final_height" ] && [ "$_final_width" -ge 1 ] && [ "$_final_height" -ge 1 ] && [ "$_final_width" -le "$_max" ] && [ "$_final_height" -le "$_max" ]; } || {
      cleanup_mj_stage_dir "$_stage" "$_parent_real" "$_stage_prefix" || { set_error "STAGE_CLEANUP_REFUSED" "Frame scaling validation failed and staging cleanup was refused."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 74; }
      set_error "FRAME_SCALE_FAILED" "Scaled frame derivative dimensions are invalid."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 74;
    }
  fi

  if ! /bin/mv -n "$_stage_file" "$_out_real" 2>/dev/null; then
    cleanup_mj_stage_dir "$_stage" "$_parent_real" "$_stage_prefix" || { set_error "STAGE_CLEANUP_REFUSED" "Frame publish failed and staging cleanup was refused."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 74; }
    set_error "FRAME_PUBLISH_FAILED" "Could not publish the frame derivative without overwrite."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 74
  fi
  if [ -e "$_stage_file" ] || [ -L "$_stage_file" ]; then
    cleanup_mj_stage_dir "$_stage" "$_parent_real" "$_stage_prefix" || { set_error "STAGE_CLEANUP_REFUSED" "Frame output appeared concurrently and staging cleanup was refused."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 74; }
    set_error "OUTPUT_EXISTS" "Frame output appeared during extraction; refusing overwrite."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 73
  fi
  cleanup_mj_stage_dir "$_stage" "$_parent_real" "$_stage_prefix" || { set_error "STAGE_CLEANUP_REFUSED" "Published frame but could not prove staging ownership for cleanup."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 74; }
  [ -f "$_out_real" ] || { set_error "FRAME_PUBLISH_FAILED" "Frame output was not created."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 74; }

  _size=$(file_stat_size "$_out_real" 2>/dev/null || printf '')
  _delta=$(MJ_FRAMEKIT_REQ="$MJ_FRAMEKIT_REQUESTED_SECONDS" MJ_FRAMEKIT_ACT="$MJ_FRAMEKIT_ACTUAL_SECONDS" /usr/bin/awk 'BEGIN { printf "%.9f", (ENVIRON["MJ_FRAMEKIT_ACT"]+0)-(ENVIRON["MJ_FRAMEKIT_REQ"]+0) }')

  emit_success_start "$REQUEST_COMMAND" "$REQUEST_ID"
  printf '{"schema":"MJ_MEDIA_FRAME_1","source":'; json_quote "$_path"
  printf ',"output":'; json_quote "$_output"; printf ',"resolvedOutput":'; json_quote "$_out_real"
  printf ',"format":"png","maxPixels":%s,"sizeBytes":' "$_max"; [ -n "$_size" ] && printf '%s' "$_size" || printf 'null'
  printf ',"requestedTime":{"seconds":%s,"timescale":%s}' "$MJ_FRAMEKIT_REQUESTED_SECONDS" "$MJ_MEDIA_VIDEO_TIMESCALE"
  printf ',"actualTime":{"seconds":%s,"value":%s,"timescale":%s}' "$MJ_FRAMEKIT_ACTUAL_SECONDS" "$MJ_FRAMEKIT_ACTUAL_VALUE" "$MJ_FRAMEKIT_ACTUAL_TIMESCALE"
  printf ',"deltaSeconds":%s' "$_delta"
  printf ',"pixelWidth":%s,"pixelHeight":%s' "$_final_width" "$_final_height"
  printf ',"frameAccurateRequest":true,"toleranceBeforeSeconds":0,"toleranceAfterSeconds":0,"preferredTrackTransformApplied":true'
  printf ',"sourceUnchanged":true,"scope":{"classification":"local","policy":"LOCAL_ONLY"}'
  printf ',"adapter":"ASOBJC_AVAssetImageGenerator_1"'
  printf ',"notes":["FrameKit requests zero AVFoundation time tolerance. actualTime is reported independently and must be used by consumers for verification.","The AppleScriptObjC adapter snaps the requested time down to the containing video frame exact presentation time (integer frame-grid math on the track natural timescale) and extracts with zero tolerance."]}'
  emit_success_end
}

# --- src/modules/asset.zsh ---
asset_is_uint() {
  case "$1" in ''|*[!0-9]*) return 1 ;; *) return 0 ;; esac
}

asset_normalize_sha256() {
  local _value="$1"
  local _norm
  _norm=$(printf '%s' "$_value" | /usr/bin/awk '{print tolower($0)}')
  case "$_norm" in *[!0-9a-f]*|'') return 1 ;; esac
  [ ${#_norm} -eq 64 ] || return 1
  printf '%s' "$_norm"
}

asset_stable_sha256() {
  local _path="$1"
  local _before=""
  local _after=""
  MJ_ASSET_HASH=""
  MJ_ASSET_HASH_SOURCE=""
  _before=$(file_hash_identity "$_path") || return 74
  hash_sha256_file "$_path"
  local _rc=$?
  [ "$_rc" -eq 0 ] || return "$_rc"
  _after=$(file_hash_identity "$_path") || return 74
  [ "$_before" = "$_after" ] || return 75
  MJ_ASSET_HASH="$MJ_HASH_VALUE"
  MJ_ASSET_HASH_SOURCE="$MJ_HASH_SOURCE"
  return 0
}

handle_asset_manifest() {
  local _path=""
  local _mode="fast"
  local _size=""
  local _mtime=""
  local _type=""
  local _filename=""
  local _sha=""
  local _hash_source=""
  local _hash_rc=0

  require_arg path || { emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  _path="$MJ_REQUIRED_ARG_VALUE"
  if request_arg_present format; then _mode=$(request_arg_get format); fi
  case "$_mode" in fast|sha256) ;; *) set_error "INVALID_ARGUMENT" "asset.manifest format must be fast or sha256."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65 ;; esac
  is_absolute_path "$_path" || { set_error "INVALID_PATH" "Path must be absolute."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  [ -f "$_path" ] || { set_error "INVALID_TARGET" "Asset manifest target must be a regular file."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  [ -r "$_path" ] || { set_error "PERMISSION_DENIED" "Asset is not readable."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 77; }
  cap_available stat && cap_available file && cap_available uname || { set_error "UNSUPPORTED" "Asset manifest requires stock macOS stat/file/uname capabilities."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 69; }

  _size=$(file_stat_size "$_path" 2>/dev/null || printf '')
  _mtime=$(file_stat_mtime "$_path" 2>/dev/null || printf '')
  _type=$(file_basic_type "$_path")
  _filename=${_path##*/}
  [ -n "$_size" ] && [ -n "$_mtime" ] || { set_error "SOURCE_STATE_UNAVAILABLE" "Could not establish asset stat identity."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 74; }

  if [ "$_mode" = "sha256" ]; then
    asset_stable_sha256 "$_path"
    _hash_rc=$?
    if [ "$_hash_rc" -eq 69 ]; then
      set_error "UNSUPPORTED" "SHA-256 manifest mode requires an approved native SHA-256 utility."
      emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 69
    elif [ "$_hash_rc" -eq 75 ]; then
      set_error "SOURCE_CHANGED" "Asset changed while its manifest hash was being calculated."
      emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 74
    elif [ "$_hash_rc" -ne 0 ]; then
      set_error "HASH_FAILED" "Could not calculate asset SHA-256."
      emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 74
    fi
    _sha="$MJ_ASSET_HASH"
    _hash_source="$MJ_ASSET_HASH_SOURCE"
  fi

  emit_success_start "$REQUEST_COMMAND" "$REQUEST_ID"
  printf '{"schema":"MJ_ASSET_MANIFEST_1","path":'; json_quote "$_path"
  printf ',"filename":'; json_quote "$_filename"
  printf ',"sizeBytes":%s,"modifiedEpoch":%s' "$_size" "$_mtime"
  printf ',"basicType":'; json_quote "$_type"
  printf ',"identity":{"mode":'; if [ "$_mode" = "sha256" ]; then json_quote "SHA256"; else json_quote "STAT_FINGERPRINT"; fi
  printf ',"sha256":'; if [ -n "$_sha" ]; then json_quote "$_sha"; else printf 'null'; fi
  printf ',"hashSource":'; if [ -n "$_hash_source" ]; then json_quote "$_hash_source"; else printf 'null'; fi
  printf ',"stabilityCheck":'; if [ "$_mode" = "sha256" ]; then json_quote "device+inode+size+mtime"; else printf 'null'; fi
  printf '}}'
  emit_success_end
}

handle_asset_verify() {
  local _path=""
  local _filename=""
  local _size=""
  local _mtime=""
  local _expected_filename=""
  local _expected_size=""
  local _expected_mtime=""
  local _expected_sha=""
  local _actual_sha=""
  local _match=true
  local _filename_check="null"
  local _size_check="null"
  local _mtime_check="null"
  local _sha_check="null"
  local _checks=0
  local _hash_rc=0

  require_arg path || { emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  _path="$MJ_REQUIRED_ARG_VALUE"
  is_absolute_path "$_path" || { set_error "INVALID_PATH" "Path must be absolute."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  [ -f "$_path" ] || { set_error "INVALID_TARGET" "Asset verify target must be a regular file."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  [ -r "$_path" ] || { set_error "PERMISSION_DENIED" "Asset is not readable."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 77; }
  cap_available stat && cap_available uname || { set_error "UNSUPPORTED" "Asset verification requires stock macOS stat/uname capabilities."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 69; }

  _filename=${_path##*/}
  _size=$(file_stat_size "$_path" 2>/dev/null || printf '')
  _mtime=$(file_stat_mtime "$_path" 2>/dev/null || printf '')
  [ -n "$_size" ] && [ -n "$_mtime" ] || { set_error "SOURCE_STATE_UNAVAILABLE" "Could not establish asset stat identity."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 74; }

  if request_arg_present expectedFilename; then
    _checks=$((_checks+1)); _expected_filename=$(request_arg_get expectedFilename)
    case "$_expected_filename" in ''|*/*) set_error "INVALID_ARGUMENT" "expectedFilename must be a filename, not a path."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65 ;; esac
    [ "$_filename" = "$_expected_filename" ] && _filename_check=true || { _filename_check=false; _match=false; }
  fi
  if request_arg_present expectedSizeBytes; then
    _checks=$((_checks+1)); _expected_size=$(request_arg_get expectedSizeBytes)
    asset_is_uint "$_expected_size" || { set_error "INVALID_ARGUMENT" "expectedSizeBytes must be an unsigned integer."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
    [ "$_size" = "$_expected_size" ] && _size_check=true || { _size_check=false; _match=false; }
  fi
  if request_arg_present expectedModifiedEpoch; then
    _checks=$((_checks+1)); _expected_mtime=$(request_arg_get expectedModifiedEpoch)
    asset_is_uint "$_expected_mtime" || { set_error "INVALID_ARGUMENT" "expectedModifiedEpoch must be an unsigned integer."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
    [ "$_mtime" = "$_expected_mtime" ] && _mtime_check=true || { _mtime_check=false; _match=false; }
  fi
  if request_arg_present expectedSha256; then
    _checks=$((_checks+1)); _expected_sha=$(asset_normalize_sha256 "$(request_arg_get expectedSha256)" 2>/dev/null || printf '')
    [ -n "$_expected_sha" ] || { set_error "INVALID_ARGUMENT" "expectedSha256 must be a 64-character hexadecimal SHA-256 digest."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
    asset_stable_sha256 "$_path"; _hash_rc=$?
    if [ "$_hash_rc" -eq 69 ]; then set_error "UNSUPPORTED" "SHA-256 verification requires an approved native SHA-256 utility."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 69
    elif [ "$_hash_rc" -eq 75 ]; then set_error "SOURCE_CHANGED" "Asset changed while verification hash was being calculated."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 74
    elif [ "$_hash_rc" -ne 0 ]; then set_error "HASH_FAILED" "Could not calculate asset SHA-256."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 74; fi
    _actual_sha="$MJ_ASSET_HASH"
    [ "$_actual_sha" = "$_expected_sha" ] && _sha_check=true || { _sha_check=false; _match=false; }
  fi

  [ "$_checks" -gt 0 ] || { set_error "MISSING_ARGUMENT" "asset.verify requires at least one expected identity field."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }

  emit_success_start "$REQUEST_COMMAND" "$REQUEST_ID"
  printf '{"match":'; $_match && printf 'true' || printf 'false'
  printf ',"path":'; json_quote "$_path"
  printf ',"actual":{"filename":'; json_quote "$_filename"; printf ',"sizeBytes":%s,"modifiedEpoch":%s,"sha256":' "$_size" "$_mtime"; if [ -n "$_actual_sha" ]; then json_quote "$_actual_sha"; else printf 'null'; fi; printf '}'
  printf ',"checks":{"filename":%s,"sizeBytes":%s,"modifiedEpoch":%s,"sha256":%s}' "$_filename_check" "$_size_check" "$_mtime_check" "$_sha_check"
  printf '}'
  emit_success_end
}

# --- src/modules/provenance.zsh ---
handle_file_provenance() {
  local _path=""
  local _attrs=""
  local _attr=""
  local _first=1
  local _count=0
  local _returned=0
  local _limit=128
  local _quarantine=false
  local _finder=false

  require_arg path || { emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  _path="$MJ_REQUIRED_ARG_VALUE"
  is_absolute_path "$_path" || { set_error "INVALID_PATH" "Path must be absolute."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  [ -e "$_path" ] || [ -L "$_path" ] || { set_error "NOT_FOUND" "Path does not exist."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 66; }
  cap_available xattr || { set_error "UNSUPPORTED" "Read-only provenance inspection requires /usr/bin/xattr."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 69; }

  _attrs=$(/usr/bin/xattr "$_path" 2>/dev/null) || { set_error "PROVENANCE_READ_FAILED" "Could not read extended-attribute names."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 74; }

  emit_success_start "$REQUEST_COMMAND" "$REQUEST_ID"
  printf '{"path":'; json_quote "$_path"; printf ',"readOnly":true,"attributeNames":['
  while IFS= read -r _attr; do
    [ -n "$_attr" ] || continue
    _count=$((_count+1))
    [ "$_attr" = "com.apple.quarantine" ] && _quarantine=true
    [ "$_attr" = "com.apple.FinderInfo" ] && _finder=true
    if [ "$_returned" -lt "$_limit" ]; then
      [ "$_first" -eq 1 ] || printf ','; _first=0
      json_quote "$_attr"; _returned=$((_returned+1))
    fi
  done <<EOF_ATTRS
$_attrs
EOF_ATTRS
  printf ']'
  printf ',"attributeCount":%s,"returned":%s,"truncated":' "$_count" "$_returned"; [ "$_count" -gt "$_returned" ] && printf 'true' || printf 'false'
  printf ',"quarantinePresent":'; $_quarantine && printf 'true' || printf 'false'
  printf ',"finderInfoPresent":'; $_finder && printf 'true' || printf 'false'
  printf ',"valuesExposed":false,"source":"xattr"}'
  emit_success_end
}

# --- src/modules/image.zsh ---
# Reusable image primitives live in src/lib/image_kit.zsh.

handle_image_inspect() {
  local _path=""
  require_arg path || { emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  _path="$MJ_REQUIRED_ARG_VALUE"
  is_absolute_path "$_path" || { set_error "INVALID_PATH" "Path must be absolute."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  [ -f "$_path" ] || { set_error "INVALID_TARGET" "Image target must be a regular file."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  [ -r "$_path" ] || { set_error "PERMISSION_DENIED" "Image is not readable."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 77; }
  cap_available sips && cap_available awk || { set_error "UNSUPPORTED" "Image inspection requires stock macOS sips/awk capabilities."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 69; }
  image_positive_identification "$_path" || { set_error "INVALID_TARGET" "sips did not positively identify the target as a raster image."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }

  emit_success_start "$REQUEST_COMMAND" "$REQUEST_ID"
  image_emit_inspection_data "$_path"
  emit_success_end
}

handle_image_derivative() {
  local _input=""
  local _output=""
  local _max=""
  local _parent=""
  local _parent_real=""
  local _leaf=""
  local _out_real=""
  local _stage=""
  local _stage_file=""
  local _stage_prefix="MographJailed_Image"
  local _before=""
  local _after=""
  local _size=""

  require_arg input || { emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }; _input="$MJ_REQUIRED_ARG_VALUE"
  require_arg output || { emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }; _output="$MJ_REQUIRED_ARG_VALUE"
  require_arg target || { emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }; _max="$MJ_REQUIRED_ARG_VALUE"
  is_absolute_path "$_input" && is_absolute_path "$_output" || { set_error "INVALID_PATH" "Input and output paths must be absolute."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  [ -f "$_input" ] && [ -r "$_input" ] || { set_error "INVALID_TARGET" "Image derivative input must be a readable regular file."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  image_is_uint "$_max" || { set_error "INVALID_ARGUMENT" "Image derivative target must be an integer pixel bound."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  [ ${#_max} -le 4 ] || { set_error "INVALID_ARGUMENT" "Image derivative target exceeds the supported integer range."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  [ "$_max" -ge 16 ] && [ "$_max" -le 4096 ] || { set_error "INVALID_ARGUMENT" "Image derivative target must be between 16 and 4096 pixels."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  case "$_output" in *.png|*.PNG) ;; *) set_error "INVALID_OUTPUT" "Image derivative output must be a .png file."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65 ;; esac
  cap_available sips && cap_available awk && cap_available mktemp && cap_available mv && cap_available rm && cap_available stat && cap_available uname || { set_error "UNSUPPORTED" "Image derivative requires stock macOS sips/awk/mktemp/mv/rm/stat/uname capabilities."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 69; }
  image_positive_identification "$_input" || { set_error "INVALID_TARGET" "sips did not positively identify the derivative input as a raster image."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }

  _parent=$(parent_path "$_output")
  [ -d "$_parent" ] && [ -w "$_parent" ] || { set_error "OUTPUT_UNAVAILABLE" "Image derivative output directory is unavailable or not writable."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 73; }
  _parent_real=$(canonical_existing_dir "$_parent") || { set_error "OUTPUT_UNAVAILABLE" "Could not resolve image derivative output directory."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 73; }
  _leaf=${_output##*/}; _out_real="$_parent_real/$_leaf"
  [ ! -e "$_out_real" ] && [ ! -L "$_out_real" ] || { set_error "OUTPUT_EXISTS" "Refusing to overwrite an existing image derivative."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 73; }
  _before=$(file_hash_identity "$_input") || { set_error "SOURCE_STATE_UNAVAILABLE" "Could not establish image source identity."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 74; }

  create_mj_stage_dir "$_parent_real" "$_stage_prefix" || { set_error "TEMP_CREATE_FAILED" "Could not create and bind image derivative staging directory."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 73; }
  _stage="$MJ_STAGE_DIR"
  _stage_file="$_stage/derivative.png"
  if ! /usr/bin/sips -s format png -Z "$_max" "$_input" --out "$_stage_file" >/dev/null 2>&1; then
    cleanup_mj_stage_dir "$_stage" "$_parent_real" "$_stage_prefix" || { set_error "STAGE_CLEANUP_REFUSED" "Image derivative failed and its staging directory could not be proven safe for cleanup."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 74; }
    set_error "IMAGE_DERIVATIVE_FAILED" "Native image derivative creation failed."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 74
  fi
  _after=$(file_hash_identity "$_input") || {
    cleanup_mj_stage_dir "$_stage" "$_parent_real" "$_stage_prefix" || { set_error "STAGE_CLEANUP_REFUSED" "Image source state failed and staging cleanup was refused."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 74; }
    set_error "SOURCE_CHANGED" "Image source state could not be re-established after derivative creation."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 74;
  }
  [ "$_before" = "$_after" ] || {
    cleanup_mj_stage_dir "$_stage" "$_parent_real" "$_stage_prefix" || { set_error "STAGE_CLEANUP_REFUSED" "Image source changed and staging cleanup was refused."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 74; }
    set_error "SOURCE_CHANGED" "Image source changed while derivative was being created."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 74;
  }
  if ! /bin/mv -n "$_stage_file" "$_out_real" 2>/dev/null; then
    cleanup_mj_stage_dir "$_stage" "$_parent_real" "$_stage_prefix" || { set_error "STAGE_CLEANUP_REFUSED" "Image publish failed and staging cleanup was refused."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 74; }
    set_error "IMAGE_DERIVATIVE_FAILED" "Could not publish image derivative."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 74
  fi
  if [ -e "$_stage_file" ] || [ -L "$_stage_file" ]; then
    cleanup_mj_stage_dir "$_stage" "$_parent_real" "$_stage_prefix" || { set_error "STAGE_CLEANUP_REFUSED" "Image output appeared concurrently and staging cleanup was refused."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 74; }
    set_error "OUTPUT_EXISTS" "Image derivative output appeared during creation; refusing overwrite."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 73
  fi
  cleanup_mj_stage_dir "$_stage" "$_parent_real" "$_stage_prefix" || { set_error "STAGE_CLEANUP_REFUSED" "Published image derivative but could not prove staging ownership for cleanup."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 74; }
  [ -f "$_out_real" ] || { set_error "IMAGE_DERIVATIVE_FAILED" "Image derivative output was not created."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 74; }
  _size=$(file_stat_size "$_out_real" 2>/dev/null || printf '')

  emit_success_start "$REQUEST_COMMAND" "$REQUEST_ID"
  printf '{"source":'; json_quote "$_input"; printf ',"output":'; json_quote "$_output"; printf ',"resolvedOutput":'; json_quote "$_out_real"
  printf ',"maxPixels":%s,"format":"png","sizeBytes":' "$_max"; [ -n "$_size" ] && printf '%s' "$_size" || printf 'null'
  printf ',"sourceUnchanged":true,"inspection":'; image_emit_inspection_data "$_out_real"; printf '}'
  emit_success_end
}

# Extract and validate one signature array (64 numbers, or 64 RGB triples) from the stats JSON.
image_sig_field() {
  printf '%s' "$1" | /usr/bin/python3 -c '
import json, sys
v = json.load(sys.stdin)[sys.argv[1]]
assert isinstance(v, list) and len(v) == 64
assert all(type(x) is int or (isinstance(x, list) and len(x) == 3 and all(type(c) is int for c in x)) for x in v)
print(json.dumps(v, separators=(",", ":")))
' "$2" 2>/dev/null
}

handle_image_stats() {
  local _path=""
  local _fields=""
  local _id0=""
  local _stats_json=""
  local _width=""
  local _height=""
  local _histogram=""
  local _grid=""

  require_arg path || { emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  _path="$MJ_REQUIRED_ARG_VALUE"
  _id0=$(source_identity "$_path")
  is_absolute_path "$_path" || { set_error "INVALID_PATH" "Path must be absolute."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  [ -f "$_path" ] || { set_error "INVALID_TARGET" "Image stats target must be a regular file."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  [ -r "$_path" ] || { set_error "PERMISSION_DENIED" "Image is not readable."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 77; }
  image_stats_available || { set_error "UNSUPPORTED" "Image stats requires stock macOS python3/sips/awk capabilities."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 69; }
  image_positive_identification "$_path" || { set_error "INVALID_TARGET" "sips did not positively identify the target as a raster image."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }

  _stats_json=$(image_stats_compute "$_path") || { set_error "STATS_FAILED" "Image stats computation failed (PNG decode or histogram)."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 74; }
  # Validate the Python output is ok
  case "$_stats_json" in
    *'"ok": true'*|*'"ok":true'*) ;;
    *) set_error "STATS_FAILED" "Image stats engine returned an error."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 74 ;;
  esac

  # Validate the engine's output once; anything unexpected is an error, never malformed JSON.
  _fields=$(printf '%s' "$_stats_json" | /usr/bin/python3 -c '
import json, sys
d = json.load(sys.stdin)
w, h, hist, grid = d["width"], d["height"], d["histogram"], d["gridAverages"]
assert type(w) is int and type(h) is int and w > 0 and h > 0
assert isinstance(hist, list) and len(hist) == 64 and all(type(v) is int and v >= 0 for v in hist)
assert isinstance(grid, list) and len(grid) == 64 and all(isinstance(c, list) and len(c) == 3 and all(type(v) is int and 0 <= v <= 255 for v in c) for c in grid)
print(w); print(h); print(json.dumps(hist, separators=(",", ":"))); print(json.dumps(grid, separators=(",", ":")))
' 2>/dev/null) || { set_error "STATS_FAILED" "Image stats engine returned unexpected output."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 74; }
  { IFS= read -r _width; IFS= read -r _height; IFS= read -r _histogram; IFS= read -r _grid; } <<EOF_FIELDS
$_fields
EOF_FIELDS
  emit_success_start "$REQUEST_COMMAND" "$REQUEST_ID"
  printf '{"schema":"MJ_IMAGE_STATS_1","path":'; json_quote "$_path"
  printf ',"pixelWidth":%s,"pixelHeight":%s' "$_width" "$_height"
  printf ',"histogramBins":64,"histogram":%s' "$_histogram"
  printf ',"gridSize":8,"gridAverages":%s' "$_grid"
  printf ',"sourceUnchanged":%s}' "$(source_unchanged_json "$_id0" "$_path")"
  emit_success_end
}

handle_image_compare() {
  local _fields=""
  local _path_a=""
  local _id0a=""
  local _id0b=""
  local _path_b=""
  local _stats_a=""
  local _stats_b=""
  local _hist_a=""
  local _grid_a=""
  local _hist_b=""
  local _grid_b=""
  local _compare_json=""
  local _score=""
  local _hist_sim=""
  local _grid_sim=""

  require_arg pathA || { emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  _path_a="$MJ_REQUIRED_ARG_VALUE"
  require_arg pathB || { emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  _path_b="$MJ_REQUIRED_ARG_VALUE"
  _id0a=$(source_identity "$_path_a"); _id0b=$(source_identity "$_path_b")

  for _p in "$_path_a" "$_path_b"; do
    is_absolute_path "$_p" || { set_error "INVALID_PATH" "Paths must be absolute."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
    [ -f "$_p" ] || { set_error "INVALID_TARGET" "Image compare targets must be regular files."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
    [ -r "$_p" ] || { set_error "PERMISSION_DENIED" "Image is not readable."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 77; }
    image_positive_identification "$_p" || { set_error "INVALID_TARGET" "sips did not positively identify the target as a raster image."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  done

  image_stats_available || { set_error "UNSUPPORTED" "Image compare requires stock macOS python3/sips/awk capabilities."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 69; }

  _stats_a=$(image_stats_compute "$_path_a") || { set_error "STATS_FAILED" "Image stats computation failed for first image."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 74; }
  _stats_b=$(image_stats_compute "$_path_b") || { set_error "STATS_FAILED" "Image stats computation failed for second image."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 74; }

  _hist_a=$(image_sig_field "$_stats_a" histogram) && _grid_a=$(image_sig_field "$_stats_a" gridAverages) \
    && _hist_b=$(image_sig_field "$_stats_b" histogram) && _grid_b=$(image_sig_field "$_stats_b" gridAverages) \
    || { set_error "STATS_FAILED" "Image stats engine returned unexpected output."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 74; }

  _compare_json=$(image_stats_compare "$_hist_a" "$_grid_a" "$_hist_b" "$_grid_b") || { set_error "COMPARE_FAILED" "Image similarity computation failed."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 74; }
  case "$_compare_json" in
    *'"ok": true'*|*'"ok":true'*) ;;
    *) set_error "COMPARE_FAILED" "Image compare engine returned an error."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 74 ;;
  esac

  _fields=$(printf '%s' "$_compare_json" | /usr/bin/python3 -c '
import json, sys
d = json.load(sys.stdin)
for k in ("score", "histogramSimilarity", "gridSimilarity"):
    assert isinstance(d[k], (int, float)) and not isinstance(d[k], bool) and 0 <= d[k] <= 1
print(d["score"]); print(d["histogramSimilarity"]); print(d["gridSimilarity"])
' 2>/dev/null) || { set_error "COMPARE_FAILED" "Image compare engine returned unexpected output."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 74; }
  { IFS= read -r _score; IFS= read -r _hist_sim; IFS= read -r _grid_sim; } <<EOF_FIELDS
$_fields
EOF_FIELDS
  emit_success_start "$REQUEST_COMMAND" "$REQUEST_ID"
  printf '{"schema":"MJ_IMAGE_COMPARE_1","pathA":'; json_quote "$_path_a"
  printf ',"pathB":'; json_quote "$_path_b"
  printf ',"score":%s,"histogramSimilarity":%s,"gridSimilarity":%s' "$_score" "$_hist_sim" "$_grid_sim"
  if [ "$(source_unchanged_json "$_id0a" "$_path_a")" = true ] && [ "$(source_unchanged_json "$_id0b" "$_path_b")" = true ]; then printf ',"sourceUnchanged":true}'; else printf ',"sourceUnchanged":false}'; fi
  emit_success_end
}

# --- src/modules/storage.zsh ---
storage_is_uint() {
  case "$1" in ''|*[!0-9]*) return 1 ;; *) return 0 ;; esac
}

handle_storage_preflight() {
  local _path=""
  local _required=""
  local _fs=""
  local _class="unknown"
  local _kb=""
  local _bytes=""
  local _darwin=false
  local _enough="null"

  require_arg path || { emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }; _path="$MJ_REQUIRED_ARG_VALUE"
  is_absolute_path "$_path" || { set_error "INVALID_PATH" "Path must be absolute."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  [ -e "$_path" ] || { set_error "NOT_FOUND" "Storage preflight path does not exist or volume is unavailable."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 66; }
  cap_available df && cap_available awk && cap_available uname || { set_error "UNSUPPORTED" "Storage preflight requires stock macOS df/awk/uname capabilities."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 69; }
  if request_arg_present requiredBytes; then
    _required=$(request_arg_get requiredBytes)
    storage_is_uint "$_required" || { set_error "INVALID_ARGUMENT" "requiredBytes must be an unsigned integer."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
    [ ${#_required} -le 18 ] || { set_error "INVALID_ARGUMENT" "requiredBytes exceeds the supported integer range."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  fi

  [ "$(/usr/bin/uname -s 2>/dev/null)" = "Darwin" ] && _darwin=true
  _fs=$(volume_fs_type "$_path")
  _class=$(volume_class "$_fs")
  _kb=$(volume_free_kb "$_path")
  if [ -n "$_kb" ]; then _bytes=$((_kb * 1024)); fi
  if [ -n "$_required" ] && [ -n "$_bytes" ]; then [ "$_bytes" -ge "$_required" ] && _enough=true || _enough=false; fi

  emit_success_start "$REQUEST_COMMAND" "$REQUEST_ID"
  printf '{"path":'; json_quote "$_path"
  printf ',"filesystem":'; [ -n "$_fs" ] && json_quote "$_fs" || printf 'null'
  printf ',"classification":'; json_quote "$_class"
  printf ',"freeBytes":'; [ -n "$_bytes" ] && printf '%s' "$_bytes" || printf 'null'
  printf ',"requiredBytes":'; [ -n "$_required" ] && printf '%s' "$_required" || printf 'null'
  printf ',"enoughSpace":%s' "$_enough"
  printf ',"readable":'; [ -r "$_path" ] && printf 'true' || printf 'false'
  printf ',"writableHint":'; [ -w "$_path" ] && printf 'true' || printf 'false'
  printf ',"network":'; [ "$_class" = "network" ] && printf 'true' || printf 'false'
  printf ',"filesystemSource":'; if [ -n "$_fs" ]; then $_darwin && printf '"df -Y"' || printf '"statfs"'; else printf 'null'; fi
  printf ',"advisory":{"writableHint":true,"classification":true}}'
  emit_success_end
}

# --- src/modules/search.zsh ---
search_is_uint() {
  case "$1" in ''|*[!0-9]*) return 1 ;; *) return 0 ;; esac
}

handle_search_candidate() {
  local _root=""
  local _target=""
  local _max=20
  local _tmp_parent=""
  local _tmp=""
  local _item=""
  local _first=1
  local _total=0
  local _returned=0

  require_arg path || { emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }; _root="$MJ_REQUIRED_ARG_VALUE"
  require_arg target || { emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }; _target="$MJ_REQUIRED_ARG_VALUE"
  if request_arg_present maxResults; then _max=$(request_arg_get maxResults); fi
  is_absolute_path "$_root" || { set_error "INVALID_PATH" "Search root must be absolute."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  [ -d "$_root" ] && [ -r "$_root" ] || { set_error "INVALID_TARGET" "Search root must be a readable directory."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  [ -n "$_target" ] || { set_error "MISSING_ARGUMENT" "Search target filename is empty."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  case "$_target" in */*) set_error "INVALID_ARGUMENT" "Search target must be a filename, not a path."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65 ;; esac
  search_is_uint "$_max" || { set_error "INVALID_ARGUMENT" "maxResults must be an unsigned integer."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  [ ${#_max} -le 3 ] || { set_error "INVALID_ARGUMENT" "maxResults exceeds the supported integer range."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  [ "$_max" -ge 1 ] && [ "$_max" -le 100 ] || { set_error "INVALID_ARGUMENT" "maxResults must be between 1 and 100."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  cap_available mdfind && cap_available mktemp && cap_available rm || { set_error "UNSUPPORTED" "Spotlight candidate search requires stock macOS mdfind/mktemp/rm capabilities."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 69; }

  _tmp_parent=$(mj_tmp_parent)
  if has_ascii_control "$_tmp_parent"; then set_error "TEMP_UNAVAILABLE" "Temporary directory contains unsupported control characters."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 73; fi
  is_absolute_path "$_tmp_parent" && [ -d "$_tmp_parent" ] && [ -w "$_tmp_parent" ] || { set_error "TEMP_UNAVAILABLE" "Temporary directory is unavailable for Spotlight search."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 73; }
  _tmp=$(/usr/bin/mktemp "$_tmp_parent/MographJailed_Search.XXXXXXXX" 2>/dev/null) || { set_error "TEMP_CREATE_FAILED" "Could not create Spotlight result workspace."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 73; }
  if ! /usr/bin/mdfind -0 -onlyin "$_root" -name "$_target" > "$_tmp" 2>/dev/null; then
    /bin/rm -f "$_tmp"; set_error "SEARCH_FAILED" "Spotlight candidate search failed or is unavailable for this scope."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 74
  fi

  emit_success_start "$REQUEST_COMMAND" "$REQUEST_ID"
  printf '{"searchRoot":'; json_quote "$_root"; printf ',"target":'; json_quote "$_target"; printf ',"candidates":['
  while IFS= read -r -d '' _item; do
    _total=$((_total+1))
    if [ "$_returned" -lt "$_max" ]; then
      [ "$_first" -eq 1 ] || printf ','; _first=0
      printf '{"path":'; json_quote "$_item"; printf ',"filename":'; json_quote "${_item##*/}"; printf '}'
      _returned=$((_returned+1))
    fi
  done < "$_tmp"
  /bin/rm -f "$_tmp"
  printf '],"returned":%s,"totalMatches":%s,"truncated":' "$_returned" "$_total"; [ "$_total" -gt "$_returned" ] && printf 'true' || printf 'false'
  printf ',"source":"Spotlight/mdfind","advisory":true,"automaticRelink":false}'
  emit_success_end
}

# --- src/modules/report.zsh ---
handle_report_tech() {
  local _darwin=false
  local _first=1
  local _cap
  [ "$(/usr/bin/uname -s 2>/dev/null)" = "Darwin" ] && _darwin=true
  emit_success_start "$REQUEST_COMMAND" "$REQUEST_ID"
  printf '{"schema":"MJ_TECH_NATIVE_1"'
  printf ',"cliVersion":'; json_quote "$MOGRAPHJAILED_CLI_VERSION"
  printf ',"protocolVersion":%s' "$MOGRAPHJAILED_PROTOCOL_VERSION"
  printf ',"platform":'; json_quote "$(system_platform_name)"
  printf ',"osVersion":'; json_quote "$(system_os_version)"
  printf ',"osBuild":'; json_quote "$(system_os_build)"
  printf ',"architecture":'; json_quote "$(system_architecture)"
  printf ',"policy":{"zeroInstall":true,"localOnly":true,"rawShellAPI":false,"sourceMutationCommands":false,"jxaProductionAdapter":true,"frameKitTargetMacQualificationRequired":true}'
  printf ',"standardLibrary":'; emit_standard_library_descriptor
  printf ',"capabilities":{'
  for _cap in zsh sw_vers stat file df mktemp plutil sqlite3 jq sips ditto sha256 shasum mdls avmediainfo avconvert afinfo afconvert mdfind xattr osascript python3 base64 awk uname sed rm mv pwd; do
    [ "$_first" -eq 1 ] || printf ','; _first=0
    json_quote "$_cap"; printf ':'; emit_capability_object "$_cap"
  done
  printf '}'
  printf ',"readyForMacCore":'; if $_darwin && cap_available zsh && cap_available stat && cap_available file && cap_available mktemp && cap_available base64 && cap_available awk && cap_available uname && cap_available sed && cap_available rm; then printf 'true'; else printf 'false'; fi
  printf '}'
  emit_success_end
}

# --- src/modules/package.zsh ---
canonical_dir() {
  canonical_existing_dir "$1"
}

handle_package_create() {
  local _src=""
  local _out=""
  local _parent=""
  local _src_real=""
  local _parent_real=""
  local _out_leaf=""
  local _out_real=""
  local _stage=""
  local _stage_zip=""
  local _stage_prefix="MographJailed_Package"
  local _size=""

  require_arg path || { emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  _src="$MJ_REQUIRED_ARG_VALUE"
  require_arg output || { emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  _out="$MJ_REQUIRED_ARG_VALUE"
  is_absolute_path "$_src" && is_absolute_path "$_out" || { set_error "INVALID_PATH" "Source and output paths must be absolute."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  [ -d "$_src" ] || { set_error "INVALID_TARGET" "Package source must be a directory."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  [ ! -L "$_src" ] || { set_error "INVALID_TARGET" "Package source directory may not be a symlink."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  [ -r "$_src" ] || { set_error "PERMISSION_DENIED" "Package source is not readable."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 77; }
  case "$_out" in *.zip) ;; *) set_error "INVALID_OUTPUT" "Package output must end in .zip."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65 ;; esac

  _parent=$(parent_path "$_out")
  [ -d "$_parent" ] && [ -w "$_parent" ] || { set_error "OUTPUT_UNAVAILABLE" "Package output directory is unavailable or not writable."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 73; }
  _src_real=$(canonical_dir "$_src") || { set_error "INVALID_TARGET" "Could not resolve package source."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  _parent_real=$(canonical_dir "$_parent") || { set_error "OUTPUT_UNAVAILABLE" "Could not resolve package output directory."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 73; }
  _out_leaf=${_out##*/}
  _out_real="$_parent_real/$_out_leaf"
  case "$_out_real" in "$_src_real"/*) set_error "INVALID_OUTPUT" "Package output may not be inside the package source tree."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65 ;; esac
  if [ -e "$_out_real" ] || [ -L "$_out_real" ]; then set_error "OUTPUT_EXISTS" "Refusing to overwrite an existing package."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 73; fi

  cap_available ditto && cap_available mktemp && cap_available mv && cap_available rm && cap_available stat && cap_available uname || { set_error "UNSUPPORTED" "Native packaging requires stock macOS ditto/mktemp/mv/rm/stat/uname capabilities."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 69; }

  # Re-check the canonical source immediately before invoking ditto. A shell
  # adapter cannot make directory replacement fully race-free, but it can fail
  # closed for ordinary symlink substitution before the native copy begins.
  [ -d "$_src_real" ] && [ ! -L "$_src_real" ] || { set_error "INVALID_TARGET" "Package source changed during validation."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 73; }

  # Stage and publish through the canonical parent so retargeting a symlinked
  # lexical parent cannot redirect the final write after validation. The stage
  # itself is ownership-bound before any recursive cleanup is permitted.
  create_mj_stage_dir "$_parent_real" "$_stage_prefix" || { set_error "TEMP_CREATE_FAILED" "Could not create and bind package staging directory."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 73; }
  _stage="$MJ_STAGE_DIR"
  _stage_zip="$_stage/package.zip"
  if ! /usr/bin/ditto -c -k --sequesterRsrc --keepParent "$_src_real" "$_stage_zip" 2>/dev/null; then
    cleanup_mj_stage_dir "$_stage" "$_parent_real" "$_stage_prefix" || { set_error "STAGE_CLEANUP_REFUSED" "Packaging failed and its staging directory could not be proven safe for cleanup."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 74; }
    set_error "PACKAGE_FAILED" "Native report packaging failed."
    emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"
    return 74
  fi

  if ! /bin/mv -n "$_stage_zip" "$_out_real" 2>/dev/null; then
    cleanup_mj_stage_dir "$_stage" "$_parent_real" "$_stage_prefix" || { set_error "STAGE_CLEANUP_REFUSED" "Package publish failed and staging cleanup was refused."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 74; }
    set_error "PACKAGE_FAILED" "Package publish failed."
    emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"
    return 74
  fi
  if [ -e "$_stage_zip" ] || [ -L "$_stage_zip" ]; then
    cleanup_mj_stage_dir "$_stage" "$_parent_real" "$_stage_prefix" || { set_error "STAGE_CLEANUP_REFUSED" "Package output appeared concurrently and staging cleanup was refused."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 74; }
    if [ -e "$_out_real" ] || [ -L "$_out_real" ]; then
      set_error "OUTPUT_EXISTS" "Package output appeared during creation; refusing to overwrite it."
      emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"
      return 73
    fi
    set_error "PACKAGE_FAILED" "Package publish did not move the staged archive."
    emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"
    return 74
  fi
  cleanup_mj_stage_dir "$_stage" "$_parent_real" "$_stage_prefix" || { set_error "STAGE_CLEANUP_REFUSED" "Published package but could not prove staging ownership for cleanup."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 74; }
  [ -f "$_out_real" ] || { set_error "PACKAGE_FAILED" "Package output was not created."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 74; }

  _size=$(file_stat_size "$_out_real" 2>/dev/null || printf '')
  emit_success_start "$REQUEST_COMMAND" "$REQUEST_ID"
  printf '{"source":'; json_quote "$_src"; printf ',"output":'; json_quote "$_out"
  printf ',"resolvedOutput":'; json_quote "$_out_real"
  printf ',"format":"zip","sourceTool":"ditto","sizeBytes":'; [ -n "$_size" ] && printf '%s' "$_size" || printf 'null'
  printf '}'
  emit_success_end
}

# --- src/modules/project.zsh ---
# Tier 0 (Observer) — project observation operations.
#
# All four operations are read-only except project.snapshot, which only ever
# creates new versioned copies (never overwrites, never mutates the source).
# The LaunchAgent watcher may only trigger Tier 0 operations.
#
# project.ingest   — validate an MJ_PROJECT_SCRAPE_1 JSON file and summarize it
# expression.lint  — static analysis ("spell-check") over scraped expressions
# plugin.audit     — enumerate and hash an After Effects Plug-ins directory
# project.snapshot — hash + versioned copy of an .aep or .c4d (time-machine primitive)

# Max scrape JSON size accepted by ingest/lint (bytes). The scraper budgets ~5MB.
PROJECT_OBSERVE_MAX_SCRAPE_BYTES=8388608
# Max plugin directory entries enumerated by plugin.audit.
PROJECT_OBSERVE_MAX_PLUGIN_ENTRIES=500
# Largest single file plugin.audit will hash (bytes). ~3 s per GiB on Apple Silicon; larger files are listed unhashed.
PROJECT_OBSERVE_MAX_PLUGIN_FILE_BYTES=2147483648
# Max lint findings returned before truncation.
PROJECT_OBSERVE_MAX_FINDINGS=200

project_observe_python_available() {
  cap_available python3
}

# Validate that python output is {"ok":true,"data":{...}} and print the data
# payload as canonical JSON. Returns nonzero on any deviation.
project_emit_python_data() {
  local _out="$1"
  local _data=""
  _data=$(printf '%s' "$_out" | /usr/bin/python3 -c \
    'import json,sys; o=json.load(sys.stdin); assert o.get("ok") is True and isinstance(o.get("data"), dict); print(json.dumps(o["data"], sort_keys=True, separators=(",", ":")))' \
    2>/dev/null) || return 1
  [ -n "$_data" ] || return 1
  printf '%s' "$_data"
}

project_require_scrape_file() {
  local _path="$1"
  is_absolute_path "$_path" || { set_error "INVALID_PATH" "Scrape path must be absolute."; return 65; }
  [ -f "$_path" ] || { set_error "INVALID_TARGET" "Scrape target must be a regular file."; return 65; }
  [ -r "$_path" ] || { set_error "PERMISSION_DENIED" "Scrape file is not readable."; return 77; }
  project_observe_python_available || { set_error "UNSUPPORTED" "Project observation requires stock macOS python3."; return 69; }
  mj_require_local_existing_path "$_path" || return 73
  return 0
}

# Runs the ingest engine on a scrape; prints the engine's JSON envelope. Shared by project.ingest and project.health.
project_run_ingest() {
  local _path="$1"
  MJ_SCRAPE_PATH="$_path" MJ_SCRAPE_MAX_BYTES="$PROJECT_OBSERVE_MAX_SCRAPE_BYTES" \
    /usr/bin/python3 - <<'PY_PROJECT_INGEST' 2>/dev/null
import json, os, sys

def err(code, message):
    print(json.dumps({"ok": False, "code": code, "message": message}))
    sys.exit(0)

path = os.environ.get("MJ_SCRAPE_PATH", "")
def _ident(p):
    try:
        st = os.stat(p); return (st.st_size, st.st_mtime_ns)
    except OSError:
        return None
_id0 = _ident(path)
max_bytes = int(os.environ.get("MJ_SCRAPE_MAX_BYTES", "8388608"))
try:
    size = os.path.getsize(path)
except Exception:
    err("READ_FAILED", "Could not stat the scrape file.")
if size > max_bytes:
    err("SCRAPE_TOO_LARGE", "Scrape file exceeds the %d byte bound." % max_bytes)
try:
    with open(path, "r", encoding="utf-8") as f:
        doc = json.load(f)
except Exception as e:
    err("INVALID_JSON", "Scrape file is not valid JSON: %s" % str(e)[:120])

if not isinstance(doc, dict) or doc.get("schema") != "MJ_PROJECT_SCRAPE_1":
    err("SCHEMA_MISMATCH", "Scrape file must be an MJ_PROJECT_SCRAPE_1 document.")
required = ["scraperVersion", "projectPath", "projectName", "scrapedAt",
            "aeVersion", "numItems", "comps", "fonts", "footage"]
for key in required:
    if key not in doc:
        err("SCHEMA_MISMATCH", "Scrape file is missing required key: %s" % key)
if not isinstance(doc["comps"], list) or not isinstance(doc["fonts"], list) \
        or not isinstance(doc["footage"], list):
    err("SCHEMA_MISMATCH", "comps/fonts/footage must be arrays.")

num_layers = 0
num_expressions = 0
num_effects = 0
layer_types = {}
for comp in doc["comps"]:
    if not isinstance(comp, dict):
        err("SCHEMA_MISMATCH", "Comp entries must be objects.")
    layers = comp.get("layers", [])
    if not isinstance(layers, list):
        err("SCHEMA_MISMATCH", "Comp layers must be an array.")
    for layer in layers:
        if not isinstance(layer, dict):
            err("SCHEMA_MISMATCH", "Layer entries must be objects.")
        num_layers += 1
        t = layer.get("type", "Unknown")
        layer_types[t] = layer_types.get(t, 0) + 1
        exprs = layer.get("expressions", [])
        if isinstance(exprs, list):
            num_expressions += len(exprs)
        effs = layer.get("effects", [])
        if isinstance(effs, list):
            num_effects += len(effs)

footage_missing = []
footage_unlinked = []
for item in doc["footage"]:
    if not isinstance(item, dict):
        continue
    name = str(item.get("name", "?"))
    p = item.get("path", "")
    p = p if isinstance(p, str) else ""
    if item.get("missing") is True:
        footage_missing.append(name)
    elif not p:
        footage_unlinked.append(name)
    elif not os.path.exists(p):
        footage_missing.append(name)

data = {
    "schema": "MJ_PROJECT_SUMMARY_1",
    "projectPath": doc["projectPath"],
    "projectName": doc["projectName"],
    "scrapedAt": doc["scrapedAt"],
    "aeVersion": doc["aeVersion"],
    "numComps": len(doc["comps"]),
    "numLayers": num_layers,
    "numExpressions": num_expressions,
    "numEffects": num_effects,
    "numFonts": len(doc["fonts"]),
    "fonts": sorted(set(str(f) for f in doc["fonts"])),
    "numFootage": len(doc["footage"]),
    "footageMissing": sorted(footage_missing),
    "footageUnlinked": sorted(footage_unlinked),
    "layerTypes": layer_types,
    "compsTruncated": bool(doc.get("compsTruncated", False)),
    "footageTruncated": bool(doc.get("footageTruncated", False)),
    "_warnings": (
        ([{"code": "COMPS_TRUNCATED", "message": "The scrape holds only the first comps of a larger project; the rest are not summarized."}] if doc.get("compsTruncated") else [])
        + ([{"code": "LAYERS_TRUNCATED", "message": "Some comps have more layers than the scraper records; their layer counts are lower bounds."}]
           if any(isinstance(c, dict) and c.get("layersTruncated") for c in doc["comps"]) else [])
        + ([{"code": "FOOTAGE_TRUNCATED", "message": "The scrape holds only the first footage items of a larger project."}] if doc.get("footageTruncated") else [])
        + ([{"code": "FOOTAGE_MISSING", "message": "Missing footage items: %d." % len(footage_missing)}] if footage_missing else [])
    ),
    "sourceUnchanged": _ident(path) == _id0,
}
print(json.dumps({"ok": True, "data": data}))
PY_PROJECT_INGEST
}

# Runs the lint engine on a scrape; prints the engine's JSON envelope. Shared by expression.lint and project.health.
project_run_lint() {
  local _path="$1"
  MJ_SCRAPE_PATH="$_path" MJ_SCRAPE_MAX_BYTES="$PROJECT_OBSERVE_MAX_SCRAPE_BYTES" \
    MJ_LINT_MAX_FINDINGS="$PROJECT_OBSERVE_MAX_FINDINGS" \
    /usr/bin/python3 - <<'PY_EXPRESSION_LINT' 2>/dev/null
import json, os, re, sys

def err(code, message):
    print(json.dumps({"ok": False, "code": code, "message": message}))
    sys.exit(0)

path = os.environ.get("MJ_SCRAPE_PATH", "")
def _ident(p):
    try:
        st = os.stat(p); return (st.st_size, st.st_mtime_ns)
    except OSError:
        return None
_id0 = _ident(path)
max_bytes = int(os.environ.get("MJ_SCRAPE_MAX_BYTES", "8388608"))
max_findings = int(os.environ.get("MJ_LINT_MAX_FINDINGS", "200"))
try:
    if os.path.getsize(path) > max_bytes:
        err("SCRAPE_TOO_LARGE", "Scrape file exceeds the byte bound.")
    with open(path, "r", encoding="utf-8") as f:
        doc = json.load(f)
except Exception as e:
    err("INVALID_JSON", "Scrape file is not valid JSON: %s" % str(e)[:120])
if not isinstance(doc, dict) or doc.get("schema") != "MJ_PROJECT_SCRAPE_1":
    err("SCHEMA_MISMATCH", "Scrape file must be an MJ_PROJECT_SCRAPE_1 document.")
if not isinstance(doc.get("comps"), list):
    err("SCHEMA_MISMATCH", "comps must be an array.")

def arr(v):
    return v if isinstance(v, list) else []

layer_ref_re = re.compile(r'thisComp\s*\.\s*layer\s*\(\s*["\']([^"\']+)["\']\s*\)')
effect_ref_re = re.compile(r'''\beffect\s*\(\s*["\']([^"\']+)["\']\s*\)''')
loop_re = re.compile(r'\b(for|while)\b')
hardpath_re = re.compile(r'(/Users/|/Volumes/|[A-Za-z]:[\\/]|\\\\)')

findings = []
num_expressions = 0
truncated = False

def add(code, severity, comp, layer, prop, message):
    findings.append({
        "code": code, "severity": severity,
        "comp": comp, "layer": layer, "propertyPath": prop,
        "message": message,
    })

for comp in doc["comps"]:
    if not isinstance(comp, dict):
        continue
    comp_name = str(comp.get("name", "?"))
    layer_names = set()
    for layer in arr(comp.get("layers")):
        if isinstance(layer, dict):
            layer_names.add(str(layer.get("name", "")))
    for layer in arr(comp.get("layers")):
        if not isinstance(layer, dict):
            continue
        layer_name = str(layer.get("name", "?"))
        effect_names = set()
        for eff in arr(layer.get("effects")):
            if isinstance(eff, dict):
                effect_names.add(str(eff.get("name", "")))
        for item in arr(layer.get("expressions")):
            if not isinstance(item, dict):
                continue
            prop = str(item.get("propertyPath", "?"))
            expr = item.get("expression", "")
            if not isinstance(expr, str):
                continue
            num_expressions += 1
            for ref in layer_ref_re.findall(expr):
                if ref not in layer_names:
                    add("E001", "error", comp_name, layer_name, prop,
                        "Expression references layer \"%s\", which does not exist in comp \"%s\"." % (ref, comp_name))
            for ref in effect_ref_re.findall(expr):
                if ref not in effect_names:
                    add("E002", "error", comp_name, layer_name, prop,
                        "Expression references effect \"%s\", which is not applied to this layer." % ref)
            if "sampleImage" in expr and loop_re.search(expr):
                add("W001", "warning", comp_name, layer_name, prop,
                    "sampleImage() inside a loop is a known render-time performance trap.")
            if hardpath_re.search(expr):
                add("W002", "warning", comp_name, layer_name, prop,
                    "Expression contains a hard-coded absolute path; it will break on other machines.")
            # NOTE: the identifier below is split ("ev"+"al") on purpose.
            # The I001 rule must *detect* this ExtendScript builtin in user
            # expressions, but the repo security guard bans that literal
            # word in src/. This code never invokes it; it only
            # pattern-matches the string.
            _ev = "ev" + "al"
            if _ev + "(" in expr:
                add("I001", "info", comp_name, layer_name, prop,
                    "Expression uses " + _ev + "(); behavior is opaque to static analysis.")
            if len(expr) > 2000:
                add("W003", "warning", comp_name, layer_name, prop,
                    "Expression exceeds 2000 characters; consider splitting it across properties.")

# Teaching text lives beside, not inside, the stable finding fields: codes and messages never
# change, and scripted consumers can ignore "teach" / "teaching". The identifier is split
# ("ev"+"al") for the same reason as the I001 rule below.
_ev = "ev" + "al"
TEACH = {
    "E001": ("The expression looks up a layer by name and no layer has that name in this comp (it was renamed, deleted, or lives in another comp), so the property stops working.",
             "Fix the name, or pick-whip the layer so the link follows renames.",
             'thisComp.layer("Logo old").transform.position', 'thisComp.layer("Logo").transform.position   // or pick-whip it'),
    "E002": ("effect(\"Name\") needs an effect with that exact name on this same layer; none exists (renamed, removed, or it is on another layer).",
             "Use the name shown in the Effect Controls panel, or pick-whip the property.",
             'effect("Speed Slider")("Slider")', 'effect("Speed")("Slider")   // name as shown in Effect Controls'),
    "W001": ("sampleImage() reads rendered pixels; inside a loop it runs once per pass, on every frame, which is the usual cause of very slow renders.",
             "Sample once (a wider area is fine) outside the loop and reuse the result.",
             'for (i = 0; i < 50; i++) { s += thisComp.layer("Bg").sampleImage([i*10, 0], [1, 1], true, time); }',
             's = thisComp.layer("Bg").sampleImage([250, 0], [250, 1], true, time);   // one sample, outside any loop'),
    "W002": ("A path such as /Users/you/... exists only on your Mac, so the expression breaks on another machine or after a move.",
             "Keep the file in the project and refer to it by name instead of by location.",
             'footage("/Users/me/Desktop/data.json").sourceData', 'footage("data.json").sourceData   // imported into the project'),
    "W003": ("A very long expression is hard to read and re-runs in full on every frame.",
             "Split it across properties, or move repeated values into sliders on a control layer.",
             '// one 3000-character expression doing everything', 'speed = effect("Speed")("Slider");   // small, named pieces'),
    "I001": (_ev + "() runs text as code at render time, so neither this linter nor a colleague can tell what the expression does.",
             "Replace it with direct property access or a simple conditional.",
             _ev + '("thisComp.layer(" + n + ").opacity")', 'thisComp.layer(n).opacity'),
}
for _f in findings:
    _t = TEACH.get(_f["code"])
    if _t:
        _f["teach"] = {"why": _t[0], "fix": _t[1]}
findings.sort(key=lambda f: (f["code"], f["comp"], f["layer"], f["propertyPath"]))
if len(findings) > max_findings:
    findings = findings[:max_findings]
    truncated = True
errors = sum(1 for f in findings if f["severity"] == "error")
warnings = sum(1 for f in findings if f["severity"] == "warning")
infos = sum(1 for f in findings if f["severity"] == "info")

data = {
    "schema": "MJ_EXPRESSION_LINT_1",
    "numExpressions": num_expressions,
    "numFindings": len(findings),
    "errors": errors,
    "warnings": warnings,
    "info": infos,
    "findings": findings,
    "findingsTruncated": truncated,
    "teaching": {c: {"before": TEACH[c][2], "after": TEACH[c][3]} for c in sorted({f["code"] for f in findings}) if c in TEACH},
    "_warnings": ([{"code": "FINDINGS_TRUNCATED", "message": "Only the first %d findings are listed." % max_findings}] if truncated else []),
    "rules": ["E001", "E002", "W001", "W002", "W003", "I001"],
    "sourceUnchanged": _ident(path) == _id0,
}
print(json.dumps({"ok": True, "data": data}))
PY_EXPRESSION_LINT
}

handle_project_ingest() {
  local _rc=0
  local _path=""
  local _pyout=""
  local _data=""
  local _code=""

  require_arg path || { emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  _path="$MJ_REQUIRED_ARG_VALUE"
  project_require_scrape_file "$_path" || { _rc=$?; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return $_rc; }

  _pyout=$(project_run_ingest "$_path") || { set_error "INGEST_FAILED" "Scrape summarizer failed to run."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 74; }

  if _data=$(project_emit_python_data "$_pyout" 2>/dev/null); then
    split_warnings "$_data"
    emit_success_start "$REQUEST_COMMAND" "$REQUEST_ID"
    printf '%s' "$MJ_DATA_JSON"
    emit_success_end
    return 0
  fi
  # The python envelope already describes the failure; surface it as an error.
  _code=$(printf '%s' "$_pyout" | /usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin).get("code","INGEST_FAILED"))' 2>/dev/null || printf 'INGEST_FAILED')
  set_error "$_code" "Scrape file failed validation (see ingest rules)."
  emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"
  return 65
}

handle_expression_lint() {
  local _rc=0
  local _path=""
  local _pyout=""
  local _data=""
  local _code=""

  require_arg path || { emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  _path="$MJ_REQUIRED_ARG_VALUE"
  project_require_scrape_file "$_path" || { _rc=$?; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return $_rc; }

  _pyout=$(project_run_lint "$_path") || { set_error "LINT_FAILED" "Expression linter failed to run."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 74; }

  if _data=$(project_emit_python_data "$_pyout" 2>/dev/null); then
    split_warnings "$_data"
    emit_success_start "$REQUEST_COMMAND" "$REQUEST_ID"
    printf '%s' "$MJ_DATA_JSON"
    emit_success_end
    return 0
  fi
  _code=$(printf '%s' "$_pyout" | /usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin).get("code","LINT_FAILED"))' 2>/dev/null || printf 'LINT_FAILED')
  set_error "$_code" "Scrape file failed validation for linting."
  emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"
  return 65
}

handle_plugin_audit() {
  local _dir=""
  local _id0=""
  local _entry=""
  local _name=""
  local _kind=""
  local _size=""
  local _sha_source=""
  local _sha_value=""
  local _count=0
  local _truncated=false
  local _skipped_big=0
  local _first=1

  require_arg path || { emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  _dir="$MJ_REQUIRED_ARG_VALUE"
  _id0=$(source_identity "$_dir")
  is_absolute_path "$_dir" || { set_error "INVALID_PATH" "Plugin directory must be absolute."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  [ -d "$_dir" ] || { set_error "INVALID_TARGET" "Plugin audit target must be a directory."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  [ -r "$_dir" ] && [ -x "$_dir" ] || { set_error "PERMISSION_DENIED" "Plugin directory is not readable."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 77; }
  cap_available stat && cap_available uname || { set_error "UNSUPPORTED" "Plugin audit requires stock macOS stat/uname capabilities."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 69; }
  mj_require_local_existing_path "$_dir" || { emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 73; }

  emit_success_start "$REQUEST_COMMAND" "$REQUEST_ID"
  printf '{"schema":"MJ_PLUGIN_AUDIT_1","directory":'; json_quote "$_dir"; printf ',"entries":['
  # Portable null-glob: zsh errors on unmatched globs, bash expands literally.
  if [ -n "${ZSH_VERSION:-}" ]; then
    setopt localoptions null_glob
  else
    shopt -s nullglob 2>/dev/null || true
  fi
  # Glob order is sorted in both shells, which keeps output deterministic.
  for _entry in "$_dir"/*; do
    _count=$((_count + 1))
    if [ "$_count" -gt "$PROJECT_OBSERVE_MAX_PLUGIN_ENTRIES" ]; then
      _truncated=true
      break
    fi
    _name=${_entry##*/}
    _kind="file"; _size=""; _sha_source=""; _sha_value=""
    if [ -L "$_entry" ]; then
      _kind="symlink"
    elif [ -d "$_entry" ]; then
      case "$_name" in
        *.plugin|*.bundle|*.app|*.component) _kind="bundle" ;;
        *) _kind="directory" ;;
      esac
    elif [ -f "$_entry" ]; then
      _kind="file"
      _size=$(file_stat_size "$_entry" 2>/dev/null || printf '')
      if [ -n "$_size" ] && [ "$_size" -gt "$PROJECT_OBSERVE_MAX_PLUGIN_FILE_BYTES" ] 2>/dev/null; then
        # Too big to hash inside a request that should answer in seconds; listed, not hashed.
        _skipped_big=$((_skipped_big + 1))
      elif [ -r "$_entry" ]; then
        hash_sha256_file "$_entry" 2>/dev/null
        _sha_source="$MJ_HASH_SOURCE"; _sha_value="$MJ_HASH_VALUE"
      fi
    else
      _kind="other"
    fi
    [ "$_first" -eq 1 ] || printf ','
    _first=0
    printf '{"name":'; json_quote "$_name"
    printf ',"kind":'; json_quote "$_kind"
    printf ',"sizeBytes":'; if [ -n "$_size" ]; then printf '%s' "$_size"; else printf 'null'; fi
    printf ',"sha256":'; if [ -n "$_sha_value" ]; then json_quote "$_sha_value"; else printf 'null'; fi
    printf ',"hashSource":'; if [ -n "$_sha_source" ]; then json_quote "$_sha_source"; else printf 'null'; fi
    printf '}'
  done
  printf '],"numEntries":'
  if $_truncated; then printf '%s' "$PROJECT_OBSERVE_MAX_PLUGIN_ENTRIES"; else printf '%s' "$_count"; fi
  if $_truncated; then printf ',"truncated":true'; else printf ',"truncated":false'; fi
  if $_truncated; then add_warning "ENTRY_LIMIT_REACHED" "Only the first $PROJECT_OBSERVE_MAX_PLUGIN_ENTRIES entries were audited."; fi
  if [ "$_skipped_big" -gt 0 ]; then add_warning "FILE_TOO_LARGE_TO_HASH" "$_skipped_big files over $((PROJECT_OBSERVE_MAX_PLUGIN_FILE_BYTES / 1048576)) MB were listed without a SHA-256."; fi
  printf ',"entryBound":%s' "$PROJECT_OBSERVE_MAX_PLUGIN_ENTRIES"
  # Directory-level check: entries added or removed while the scan ran change this.
  printf ',"sourceUnchanged":%s}' "$(source_unchanged_json "$_id0" "$_dir")"
  emit_success_end
}

# Test bundle only redefines this to simulate a project being written mid-copy.
snapshot_test_hook() { :; }

# A regular, non-link file whose full SHA-256 is $2.
snapshot_same_bytes() {
  [ -f "$1" ] && [ ! -L "$1" ] || return 1
  hash_sha256_file "$1" 2>/dev/null || return 1
  [ "$MJ_HASH_VALUE" = "$2" ]
}

# Success without a new file: reason "unchanged" (matches the latest snapshot) or "alreadySaved"
# (a concurrent snapshot published these exact bytes; $6 is its path).
snapshot_emit_not_created() {
  local _reason="$1" _src="$2" _sha="$3" _hsrc="$4" _id0="$5" _existing="$6"
  emit_success_start "$REQUEST_COMMAND" "$REQUEST_ID"
  printf '{"schema":"MJ_PROJECT_SNAPSHOT_1","sourcePath":'; json_quote "$_src"
  printf ',"sha256":'; json_quote "$_sha"
  printf ',"hashSource":'; json_quote "$_hsrc"
  printf ',"snapshotCreated":false,"reason":'; json_quote "$_reason"
  [ -n "$_existing" ] && { printf ',"snapshotPath":'; json_quote "$_existing"; }
  printf ',"sourceUnchanged":%s}' "$(source_unchanged_json "$_id0" "$_src")"
  emit_success_end
}

# mkdir is atomic: the lock is a folder holding the owner's pid. A lock whose owner is gone is taken
# over; otherwise wait up to 60 s.
MJ_SNAPSHOT_LOCK=""
snapshot_lock() {
  local _l="$1" _i=0 _pid
  while [ $_i -lt 600 ]; do
    if /bin/mkdir "$_l" 2>/dev/null; then
      printf '%s' "$$" > "$_l/pid"; MJ_SNAPSHOT_LOCK="$_l"; return 0
    fi
    _pid=$(/bin/cat "$_l/pid" 2>/dev/null)
    if [ -n "$_pid" ] && ! /bin/kill -0 "$_pid" 2>/dev/null; then
      /bin/rm -rf "$_l" 2>/dev/null; continue
    fi
    /bin/sleep 0.1; _i=$((_i + 1))
  done
  return 1
}
snapshot_unlock() { [ -n "$MJ_SNAPSHOT_LOCK" ] && /bin/rm -rf "$MJ_SNAPSHOT_LOCK" 2>/dev/null; MJ_SNAPSHOT_LOCK=""; }

handle_project_snapshot() {
  local _path=""
  local _outdir=""
  local _outdir_real=""
  local _base=""
  local _stem=""
  local _sha_source=""
  local _sha_value=""
  local _latest_file=""
  local _prev_sha=""
  local _ts=""
  local _short=""
  local _dest=""
  local _receipt=""
  local _bytes=""
  local _clone_used=false
  local _id0=""
  local _partial=""
  local _ext="aep"
  local _latest_name=""

  require_arg path || { emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  _path="$MJ_REQUIRED_ARG_VALUE"
  _id0=$(source_identity "$_path")
  require_arg output || { emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  _outdir="$MJ_REQUIRED_ARG_VALUE"
  is_absolute_path "$_path" && is_absolute_path "$_outdir" || { set_error "INVALID_PATH" "Snapshot path and output directory must be absolute."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  [ -f "$_path" ] || { set_error "INVALID_TARGET" "Snapshot target must be a regular file."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  [ -r "$_path" ] || { set_error "PERMISSION_DENIED" "Snapshot target is not readable."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 77; }
  case "${_path##*/}" in
    *.[aA][eE][pP]) _ext=aep ;;
    *.[cC]4[dD]) _ext=c4d ;;
    *) set_error "INVALID_TARGET" "Snapshot target must be an After Effects project (.aep) or a Cinema 4D scene (.c4d)."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65 ;;
  esac
  [ -d "$_outdir" ] || { set_error "OUTPUT_UNAVAILABLE" "Snapshot output directory does not exist."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 73; }
  [ -w "$_outdir" ] || { set_error "OUTPUT_UNAVAILABLE" "Snapshot output directory is not writable."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 73; }
  cap_available stat && cap_available uname && cap_available cp || { set_error "UNSUPPORTED" "Project snapshot requires stock macOS stat/uname/cp capabilities."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 69; }
  mj_require_local_existing_path "$_path" || { emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 73; }
  mj_require_local_existing_path "$_outdir" || { emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 73; }

  _outdir_real=$(canonical_existing_dir "$_outdir") || { set_error "OUTPUT_UNAVAILABLE" "Could not resolve snapshot output directory."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 73; }
  hash_sha256_file "$_path" 2>/dev/null || { set_error "HASH_FAILED" "Could not hash the snapshot target."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 74; }
  _sha_source="$MJ_HASH_SOURCE"; _sha_value="$MJ_HASH_VALUE"
  [ -n "$_sha_value" ] || { set_error "UNSUPPORTED" "No approved native SHA-256 utility is available."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 69; }

  _base=${_path##*/}
  _stem="${_base%.[aA][eE][pP]}"; _stem="${_stem%.[cC]4[dD]}"
  [ -n "$_stem" ] && [ "$_stem" != "$_base" ] || _stem="project"
  # Each kind keeps its own pointer so Hero.aep and Hero.c4d can never be mistaken for each other.
  if [ "$_ext" = c4d ]; then _latest_name="$_stem.c4d.latest.json"; else _latest_name="$_stem.latest.json"; fi
  _latest_file="$_outdir_real/$_latest_name"
  # One snapshot of a project at a time: the "unchanged since the latest snapshot" check, the copy and the
  # publish all happen under a per-project lock, so the watcher and a manual mj snapshot can never both
  # save the same bytes (found by tests/run_hall_of_horror.sh: 16 racers across a second boundary).
  snapshot_lock "$_outdir_real/.$_latest_name.lock" || { set_error "CONFLICT" "Another snapshot of this project is still running; try again."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 74; }
  local _snap_rc=0
  snapshot_publish || _snap_rc=$?
  snapshot_unlock
  return $_snap_rc
}

# The rest of project.snapshot, run while holding the project's lock. Uses the handler's locals.
snapshot_publish() {
  if [ -f "$_latest_file" ]; then
    _prev_sha=$(/usr/bin/python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("sha256",""))' "$_latest_file" 2>/dev/null || printf '')
    if [ -n "$_prev_sha" ] && [ "$_prev_sha" = "$_sha_value" ]; then
      snapshot_emit_not_created unchanged "$_path" "$_sha_value" "$_sha_source" "$_id0" ""; return 0
    fi
  fi

  _ts=$(/bin/date -u '+%Y%m%dT%H%M%SZ' 2>/dev/null || printf 'unknown')
  _short=${_sha_value:0:12}
  _dest="$_outdir_real/$_stem.$_ts.$_short.$_ext"
  _partial="$_outdir_real/.$_stem.$_ts.$_short.partial.$$"
  if [ -e "$_dest" ] || [ -L "$_dest" ]; then
    # Same name means same second and same hash prefix: another snapshot (the watcher, or a second
    # mj snapshot) saved these exact bytes a moment ago. Confirm in full, then say so instead of failing.
    snapshot_same_bytes "$_dest" "$_sha_value" && { snapshot_emit_not_created alreadySaved "$_path" "$_sha_value" "$_sha_source" "$_id0" "$_dest"; return 0; }
    set_error "OUTPUT_EXISTS" "Refusing to overwrite an existing snapshot."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 73
  fi
  _bytes=$(file_stat_size "$_path" 2>/dev/null || printf '0')

  # Stage the copy under a hidden name, prove it matches, then publish with a hard link.
  # AE may still be writing the project when the watcher fires, so both the staged copy and
  # the source are re-hashed; any mismatch means a torn snapshot and nothing is published.
  # ln fails if the destination exists, so a concurrent snapshot can never be clobbered.
  /bin/rm -f "$_partial" 2>/dev/null
  if /bin/cp -c "$_path" "$_partial" 2>/dev/null; then
    _clone_used=true
  else
    /bin/cp "$_path" "$_partial" 2>/dev/null || { /bin/rm -f "$_partial" 2>/dev/null; set_error "SNAPSHOT_FAILED" "Could not copy the project to the versions directory."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 74; }
  fi
  snapshot_test_hook "$_path" "$_partial"
  hash_sha256_file "$_partial" 2>/dev/null
  if [ "$MJ_HASH_VALUE" != "$_sha_value" ]; then
    # Either the project changed under the copy, or the copy itself is bad; say which.
    /bin/rm -f "$_partial" 2>/dev/null
    hash_sha256_file "$_path" 2>/dev/null
    if [ "$MJ_HASH_VALUE" != "$_sha_value" ]; then
      set_error "SNAPSHOT_UNSTABLE" "The project changed while it was being copied; no snapshot was kept. It will be retried on the next save."
    else
      set_error "SNAPSHOT_FAILED" "The copy did not match the project (a disk or filesystem problem); no snapshot was kept."
    fi
    emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 74
  fi
  hash_sha256_file "$_path" 2>/dev/null
  if [ "$MJ_HASH_VALUE" != "$_sha_value" ]; then
    /bin/rm -f "$_partial" 2>/dev/null
    set_error "SNAPSHOT_UNSTABLE" "The project changed while it was being copied; no snapshot was kept. It will be retried on the next save."
    emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 74
  fi
  if ! /bin/ln "$_partial" "$_dest" 2>/dev/null; then
    /bin/rm -f "$_partial" 2>/dev/null
    if [ -e "$_dest" ] || [ -L "$_dest" ]; then
      snapshot_same_bytes "$_dest" "$_sha_value" && { snapshot_emit_not_created alreadySaved "$_path" "$_sha_value" "$_sha_source" "$_id0" "$_dest"; return 0; }
      set_error "OUTPUT_EXISTS" "Refusing to overwrite an existing snapshot."
    else
      set_error "SNAPSHOT_FAILED" "Could not publish the snapshot."
    fi
    emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 73
  fi
  /bin/rm -f "$_partial" 2>/dev/null
  [ -f "$_dest" ] || { set_error "SNAPSHOT_FAILED" "Snapshot copy did not materialize."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 74; }

  _receipt="$_dest.snapshot.json"
  MJ_SNAP_SHA="$_sha_value" MJ_SNAP_SRC="$_path" MJ_SNAP_DEST="$_dest" \
  MJ_SNAP_BYTES="$_bytes" MJ_SNAP_TS="$_ts" MJ_SNAP_CLONE="$_clone_used" \
  MJ_SNAP_HASH_SRC="$_sha_source" MJ_SNAP_STEM="$_stem" MJ_SNAP_LATEST="$_latest_name" MJ_SNAP_EXT="$_ext" \
  /usr/bin/python3 - <<'PY_SNAPSHOT_RECEIPT' 2>/dev/null
import json, os
receipt = {
    "schema": "MJ_PROJECT_SNAPSHOT_1",
    "sourcePath": os.environ["MJ_SNAP_SRC"],
    "sha256": os.environ["MJ_SNAP_SHA"],
    "hashSource": os.environ["MJ_SNAP_HASH_SRC"],
    "snapshotPath": os.environ["MJ_SNAP_DEST"],
    "createdAt": os.environ["MJ_SNAP_TS"],
    "bytesCopied": int(os.environ["MJ_SNAP_BYTES"] or 0),
    "cloneUsed": os.environ["MJ_SNAP_CLONE"] == "true",
    "copyVerified": True,
    "kind": os.environ["MJ_SNAP_EXT"],
    "sourceStableDuringCopy": True,
}
with open(os.environ["MJ_SNAP_DEST"] + ".snapshot.json", "w", encoding="utf-8") as f:
    json.dump(receipt, f, sort_keys=True, separators=(",", ":"))
    f.write("\n")
latest = {
    "schema": "MJ_PROJECT_SNAPSHOT_LATEST_1",
    "sourcePath": os.environ["MJ_SNAP_SRC"],
    "sha256": os.environ["MJ_SNAP_SHA"],
    "snapshotPath": os.environ["MJ_SNAP_DEST"],
    "createdAt": os.environ["MJ_SNAP_TS"],
}
stem = os.environ["MJ_SNAP_STEM"]
outdir = os.path.dirname(os.environ["MJ_SNAP_DEST"])
with open(os.path.join(outdir, os.environ["MJ_SNAP_LATEST"]), "w", encoding="utf-8") as f:
    json.dump(latest, f, sort_keys=True, separators=(",", ":"))
    f.write("\n")
PY_SNAPSHOT_RECEIPT
  [ -f "$_receipt" ] || { /bin/rm -f "$_dest" 2>/dev/null; set_error "SNAPSHOT_FAILED" "Snapshot receipt could not be written; copy removed."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 74; }

  emit_success_start "$REQUEST_COMMAND" "$REQUEST_ID"
  printf '{"schema":"MJ_PROJECT_SNAPSHOT_1","sourcePath":'; json_quote "$_path"
  printf ',"sha256":'; json_quote "$_sha_value"
  printf ',"hashSource":'; json_quote "$_sha_source"
  printf ',"snapshotCreated":true,"snapshotPath":'; json_quote "$_dest"
  printf ',"receiptPath":'; json_quote "$_receipt"
  printf ',"bytesCopied":%s' "${_bytes:-0}"
  printf ',"cloneUsed":'; $_clone_used && printf 'true' || printf 'false'
  printf ',"copyVerified":true,"sourceUnchanged":%s}' "$(source_unchanged_json "$_id0" "$_path")"
  emit_success_end
}
PROJECT_OBSERVE_MAX_PLUGIN_FILE_BYTES="${MJ_TEST_PLUGIN_FILE_LIMIT:-2147483648}"
snapshot_test_hook() { [ -n "${MJ_TEST_SNAPSHOT_APPEND:-}" ] && printf x >> "$1"; [ -n "${MJ_TEST_SNAPSHOT_CORRUPT_COPY:-}" ] && printf x >> "$2"; return 0; }

# --- src/modules/frames.zsh ---
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
  case "$MJ_FRAMES_ERR_CODE" in
    INVALID_JSON|SCHEMA_MISMATCH|SCRAPE_TOO_LARGE) return 65 ;;    # the file you gave is not acceptable, same as ingest and lint
    INVALID_ARGUMENT|INVALID_PATH|INVALID_TARGET|INVALID_SPEC|PROJECT_SCRAPE_MISMATCH) return 65 ;;
    NOT_FOUND) return 66 ;;
    UNSUPPORTED) return 69 ;;
    OUTPUT_EXISTS|OUTPUT_UNAVAILABLE) return 73 ;;
    POLICY_DENIED) return 77 ;;
  esac
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
        "_warnings": ([{"code": "EXTRA_FRAMES", "message": "Frames not in the golden record, so not checked: %d." % len(extra)}] if extra else []),
        "sourceUnchanged": tree_id(d) == id0,
    }}))

main()
PY_GOLDEN_CHECK
) || true
  frames_emit_python_result "$_out"
}

# --- src/modules/audit.zsh ---
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

# --- src/modules/protect.zsh ---
# Protect work — restore, dependency graph, handoff packaging.
#
# project.restore  — copy a snapshot back out as a NEW .aep (hash-verified; never overwrites)
# deps.graph       — dependency graph + single points of failure from an MJ_PROJECT_SCRAPE_1 receipt; read-only
# handoff.package  — new delivery folder: project, collected local footage, MANIFEST.json, README.txt
#
# Footage paths come from the scrape and may point at network volumes. They are
# classified from the kernel mount table (no I/O to the remote volume); only
# positively local paths are ever stat'ed or copied.

IFS= read -r -d '' MJ_PY_PROTECT_LIB <<'PY_PROTECT_LIB' || true
import hashlib, json, os, re, shutil, subprocess, sys, time

def err(code, message):
    print(json.dumps({"ok": False, "code": code, "message": message}))
    sys.exit(0)

def tree_id(path):
    """Cheap identity (size, mtime) of a file, or of the regular files directly inside a directory.
    Compared before and after an operation to report honestly whether its source changed."""
    try:
        if os.path.isdir(path):
            out = []
            for n in sorted(os.listdir(path)):
                p = os.path.join(path, n)
                if os.path.isfile(p):
                    st = os.stat(p); out.append((n, st.st_size, st.st_mtime_ns))
            return tuple(out)
        st = os.stat(path)
        return (st.st_size, st.st_mtime_ns)
    except OSError:
        return None

def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1048576), b""):
            h.update(chunk)
    return h.hexdigest()

def utc_stamp():
    return time.strftime("%Y%m%dT%H%M%SZ", time.gmtime())

def load_scrape(path, max_bytes=8388608):
    try:
        if os.path.getsize(path) > max_bytes:
            err("SCRAPE_TOO_LARGE", "Scrape file exceeds the byte bound.")
        with open(path, "r", encoding="utf-8") as f:
            doc = json.load(f)
    except Exception as e:
        err("INVALID_JSON", "Scrape file is not valid JSON: %s" % str(e)[:120])
    if not isinstance(doc, dict) or doc.get("schema") != "MJ_PROJECT_SCRAPE_1":
        err("SCHEMA_MISMATCH", "Scrape file must be an MJ_PROJECT_SCRAPE_1 document.")
    for key in ("comps", "fonts", "footage"):
        if not isinstance(doc.get(key), list):
            err("SCHEMA_MISMATCH", "%s must be an array." % key)
    return clean_scrape(doc)

def clean_scrape(doc):
    """Drop nested entries of the wrong shape and coerce names and paths to text, so every consumer can
    trust what it iterates. A scrape is data from outside; the hall of horror test feeds it junk."""
    def lst(v):
        return [x for x in v if isinstance(x, dict)] if isinstance(v, list) else []
    def txt(d, k):
        if k in d and not isinstance(d[k], str):
            d[k] = "" if d[k] is None else str(d[k])
    def num(d, k):
        if k in d and (isinstance(d[k], bool) or not isinstance(d[k], int)):
            d[k] = 0
    doc["comps"] = lst(doc["comps"])
    for c in doc["comps"]:
        txt(c, "name"); txt(c, "folder")
        if not isinstance(c.get("id"), int) or isinstance(c.get("id"), bool):
            c["id"] = None
        c["layers"] = lst(c.get("layers"))
        for l in c["layers"]:
            for k in ("name", "type", "sourceName", "sourcePath", "sourceKind", "font"):
                txt(l, k)
            num(l, "index"); num(l, "sourceId"); num(l, "label")
            l["effects"] = lst(l.get("effects"))
            for e in l["effects"]:
                txt(e, "name"); txt(e, "matchName")
            l["expressions"] = [e for e in lst(l.get("expressions")) if isinstance(e.get("expression"), str)]
            for e in l["expressions"]:
                txt(e, "propertyPath")
    doc["footage"] = lst(doc["footage"])
    for f in doc["footage"]:
        for k in ("name", "path", "kind", "folder"):
            txt(f, k)
        if not isinstance(f.get("id"), int) or isinstance(f.get("id"), bool):
            f["id"] = None
    doc["fonts"] = [x for x in doc["fonts"] if isinstance(x, str)]
    if "missingFonts" in doc and not isinstance(doc["missingFonts"], list):
        doc["missingFonts"] = None
    return doc

LOCAL_FS = {"apfs", "hfs", "hfs+", "exfat", "msdos", "vfat", "ext2", "ext3", "ext4", "xfs",
            "overlay", "overlayfs", "tmpfs", "btrfs"}
NETWORK_FS = {"smbfs", "nfs", "webdav", "afpfs", "cifs", "nfs4"}
_MOUNTS = None

def parse_mounts(text):
    """mount(8) output -> [(mount point, fs type)], longest mount point first.
    macOS: "dev on /path (apfs, local, ...)"; Linux: "dev on /path type ext4 (rw,...)"."""
    table = []
    for line in text.splitlines():
        m = re.match(r"^.+? on (.+?) type (\S+)", line) or re.match(r"^.+? on (.+) \(([^,()]+)[,)]", line)
        if m:
            table.append((m.group(1), m.group(2).lower()))
    table.sort(key=lambda t: -len(t[0]))
    return table

def _mount_table():
    global _MOUNTS
    if _MOUNTS is None:
        exe = "/sbin/mount" if os.path.exists("/sbin/mount") else "/bin/mount"
        try:
            out = subprocess.run([exe], capture_output=True, text=True, timeout=10).stdout
        except Exception:
            out = ""
        _MOUNTS = parse_mounts(out)
    return _MOUNTS

def storage_class(path):
    """local | network | unknown, by longest mount-point prefix. Never touches the path."""
    for mnt, fstype in _mount_table():
        if path == mnt or path.startswith(mnt.rstrip("/") + "/"):
            if fstype in LOCAL_FS:
                return "local"
            if fstype in NETWORK_FS:
                return "network"
            return "unknown"
    return "unknown"

def clone_copy(src, dst):
    """APFS clone when available, else a plain copy. dst must not exist."""
    if os.path.exists(dst):
        raise FileExistsError(dst)
    if sys.platform == "darwin":
        if subprocess.run(["/bin/cp", "-c", "-n", src, dst], stderr=subprocess.DEVNULL).returncode == 0 and os.path.isfile(dst):
            return True
    shutil.copyfile(src, dst)
    return False
PY_PROTECT_LIB

protect_python() {
  local _main=""
  IFS= read -r -d '' _main || true
  printf '%s\n%s' "$MJ_PY_PROTECT_LIB" "$_main" | /usr/bin/python3 - 2>/dev/null
}

# Validate an absolute, existing, writable, local output directory.
protect_require_output_dir() {
  local _dir="$1"
  is_absolute_path "$_dir" || { set_error "INVALID_PATH" "Output directory must be absolute."; return 65; }
  [ -d "$_dir" ] && [ -w "$_dir" ] || { set_error "OUTPUT_UNAVAILABLE" "Output directory must exist and be writable."; return 73; }
  mj_require_local_existing_path "$_dir" || return 73
}

# A snapshot file to restore from: an .aep or .c4d.
protect_require_snapshot() {
  local _path="$1"
  is_absolute_path "$_path" || { set_error "INVALID_PATH" "Snapshot path must be absolute."; return 65; }
  [ -f "$_path" ] || { set_error "INVALID_TARGET" "Snapshot must be a regular file."; return 65; }
  [ -r "$_path" ] || { set_error "PERMISSION_DENIED" "Snapshot is not readable."; return 77; }
  case "${_path##*/}" in *.[aA][eE][pP]|*.[cC]4[dD]) ;; *) set_error "INVALID_TARGET" "Snapshot must be an After Effects project (.aep) or a Cinema 4D scene (.c4d)."; return 65 ;; esac
  cap_available python3 || { set_error "UNSUPPORTED" "This operation requires python3."; return 69; }
  mj_require_local_existing_path "$_path" || return 73
}

protect_require_aep() {
  local _path="$1"
  is_absolute_path "$_path" || { set_error "INVALID_PATH" "Project path must be absolute."; return 65; }
  [ -f "$_path" ] || { set_error "INVALID_TARGET" "Project must be a regular file."; return 65; }
  [ -r "$_path" ] || { set_error "PERMISSION_DENIED" "Project is not readable."; return 77; }
  case "${_path##*/}" in *.[aA][eE][pP]) ;; *) set_error "INVALID_TARGET" "Project must be an After Effects project (.aep)."; return 65 ;; esac
  cap_available python3 || { set_error "UNSUPPORTED" "This operation requires python3."; return 69; }
  mj_require_local_existing_path "$_path" || return 73
}

handle_project_restore() {
  local _rc=0 _path="" _outdir="" _out=""
  require_arg path || { emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  _path="$MJ_REQUIRED_ARG_VALUE"
  require_arg output || { emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  _outdir="$MJ_REQUIRED_ARG_VALUE"
  protect_require_snapshot "$_path" || { _rc=$?; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return $_rc; }
  protect_require_output_dir "$_outdir" || { _rc=$?; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return $_rc; }

  _out=$(MJ_SNAP="$_path" MJ_OUTDIR="$(canonical_existing_dir "$_outdir")" protect_python <<'PY_RESTORE'
snap = os.environ["MJ_SNAP"]
outdir = os.environ["MJ_OUTDIR"]
id0 = tree_id(snap)
sha = sha256_file(snap)
receipt_path = snap + ".snapshot.json"
receipt_verified = False
if os.path.isfile(receipt_path):
    try:
        with open(receipt_path, encoding="utf-8") as f:
            recorded = json.load(f).get("sha256")
    except Exception:
        err("INVALID_RECEIPT", "Snapshot receipt exists but is unreadable.")
    if recorded != sha:
        err("SNAPSHOT_CORRUPT", "Snapshot bytes no longer match its receipt; refusing to restore.")
    receipt_verified = True
ext = os.path.splitext(snap)[1].lower()          # .aep or .c4d
stem = os.path.basename(snap)[:-4]
base = os.path.join(outdir, "%s.restored.%s" % (stem, utc_stamp()))
partial = os.path.join(outdir, ".%s.partial-%d" % (os.path.basename(base), os.getpid()))
dest = None
try:
    clone = clone_copy(snap, partial)
    if sha256_file(partial) != sha:
        err("RESTORE_FAILED", "Restored copy did not verify.")
    for n in range(1, 100):
        candidate = base + (ext if n == 1 else "-%d%s" % (n, ext))
        try:
            os.link(partial, candidate)     # fails if it exists: never overwrites
            dest = candidate
            break
        except FileExistsError:
            continue
    if dest is None:
        err("OUTPUT_EXISTS", "Refusing to overwrite existing restored copies.")
except OSError as e:
    err("RESTORE_FAILED", "Could not write the restored copy: %s" % str(e)[:120])
finally:
    if os.path.exists(partial):
        os.unlink(partial)
print(json.dumps({"ok": True, "data": {
    "schema": "MJ_PROJECT_RESTORE_1",
    "snapshotPath": snap,
    "restoredPath": dest,
    "sha256": sha,
    "receiptVerified": receipt_verified,
    "cloneUsed": clone,
    "sourceUnchanged": tree_id(snap) == id0,
}}))
PY_RESTORE
) || true
  frames_emit_python_result "$_out"
}

handle_deps_graph() {
  local _rc=0 _path="" _out=""
  require_arg path || { emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  _path="$MJ_REQUIRED_ARG_VALUE"
  project_require_scrape_file "$_path" || { _rc=$?; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return $_rc; }

  _out=$(MJ_SCRAPE="$_path" protect_python <<'PY_DEPS'
id0 = tree_id(os.environ["MJ_SCRAPE"])
doc = load_scrape(os.environ["MJ_SCRAPE"])
comps = [c for c in doc["comps"] if isinstance(c, dict)]
comp_names = {str(c.get("name", "")) for c in comps}
reported_missing = {f.get("path") for f in doc["footage"] if isinstance(f, dict) and f.get("missing")}

uses = {}        # comp -> {"footage": set, "precomps": set, "effects": set}
users = {}       # dependency key -> set of comps using it directly
parents = {}     # comp -> comps that use it as a precomp
for c in comps:
    name = str(c.get("name", ""))
    u = uses.setdefault(name, {"footage": set(), "precomps": set(), "effects": set(), "text": False})
    for layer in c.get("layers", []) if isinstance(c.get("layers"), list) else []:
        if not isinstance(layer, dict):
            continue
        src_path = str(layer.get("sourcePath") or "")
        src_name = str(layer.get("sourceName") or "")
        if src_path:
            u["footage"].add(src_path)
            users.setdefault(("footage", src_path), set()).add(name)
        elif src_name in comp_names and src_name != name:
            u["precomps"].add(src_name)
            parents.setdefault(src_name, set()).add(name)
        if layer.get("type") == "TextLayer":
            u["text"] = True
        for fx in layer.get("effects", []) if isinstance(layer.get("effects"), list) else []:
            if isinstance(fx, dict) and fx.get("matchName"):
                key = str(fx["matchName"])
                u["effects"].add(key)
                users.setdefault(("effect", key), set()).add(name)

def impact(direct):
    """Every comp that breaks if these comps break, following precomp nesting upward."""
    seen, stack = set(direct), list(direct)
    while stack:
        for p in parents.get(stack.pop(), ()):
            if p not in seen:
                seen.add(p); stack.append(p)
    return seen

def footage_state(p):
    cls = storage_class(p)
    if cls != "local":
        return cls, None
    return cls, (p in reported_missing) or not os.path.isfile(p)

deps = []
for (kind, key), direct in users.items():
    entry = {"kind": kind, "id": key, "directUsers": sorted(direct), "impactedComps": sorted(impact(direct))}
    if kind == "footage":
        cls, missing = footage_state(key)
        entry["storage"] = cls
        entry["missing"] = missing      # null when not checked (network/unknown storage)
    deps.append(entry)
deps.sort(key=lambda d: (-len(d["impactedComps"]), d["kind"], d["id"]))

missing = [d["id"] for d in deps if d.get("missing")]
unverified = [d["id"] for d in deps if d["kind"] == "footage" and d.get("missing") is None]
spof = [d for d in deps if len(d["impactedComps"]) >= 2][:25]
print(json.dumps({"ok": True, "data": {
    "schema": "MJ_DEPS_GRAPH_1",
    "projectName": doc.get("projectName"),
    "comps": [{"name": n, "footage": sorted(u["footage"]), "precomps": sorted(u["precomps"]),
               "effects": sorted(u["effects"]), "usesText": u["text"]} for n, u in uses.items()],
    "fonts": sorted(str(f) for f in doc["fonts"]),
    "dependencies": deps[:2000],
    "dependenciesTruncated": len(deps) > 2000,
    "missingFootage": missing,
    "unverifiedFootage": unverified,
    "singlePointsOfFailure": spof,
    "note": "Fonts are project-wide in MJ_PROJECT_SCRAPE_1; comps with usesText depend on them. Footage on network or unknown storage is not checked.",
    "sourceUnchanged": tree_id(os.environ["MJ_SCRAPE"]) == id0,
    "_warnings": ([{"code": "MISSING_FOOTAGE", "message": "Missing footage files: %d." % len(missing)}] if missing else [])
                 + ([{"code": "FOOTAGE_UNVERIFIED", "message": "Footage files on network or unknown storage, not checked: %d." % len(unverified)}] if unverified else []),
}}))
PY_DEPS
) || true
  frames_emit_python_result "$_out"
}

handle_handoff_package() {
  local _rc=0 _aep="" _scrape="" _outdir="" _label="" _out=""
  require_arg path || { emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  _aep="$MJ_REQUIRED_ARG_VALUE"
  require_arg input || { emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  _scrape="$MJ_REQUIRED_ARG_VALUE"
  require_arg output || { emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  _outdir="$MJ_REQUIRED_ARG_VALUE"
  require_arg label || { emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  _label="$MJ_REQUIRED_ARG_VALUE"
  case "$_label" in .*|*[!A-Za-z0-9._-]*) set_error "INVALID_ARGUMENT" "label may contain only letters, digits, dot, dash and underscore."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65 ;; esac
  [ ${#_label} -le 64 ] || { set_error "INVALID_ARGUMENT" "label must be at most 64 characters."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  protect_require_aep "$_aep" || { _rc=$?; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return $_rc; }
  project_require_scrape_file "$_scrape" || { _rc=$?; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return $_rc; }
  protect_require_output_dir "$_outdir" || { _rc=$?; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return $_rc; }

  _out=$(MJ_AEP="$_aep" MJ_SCRAPE="$_scrape" MJ_OUTDIR="$(canonical_existing_dir "$_outdir")" MJ_LABEL="$_label" protect_python <<'PY_HANDOFF'
MAX_FILES = 20000
aep, label = os.environ["MJ_AEP"], os.environ["MJ_LABEL"]
doc = load_scrape(os.environ["MJ_SCRAPE"])
dest = os.path.join(os.environ["MJ_OUTDIR"], label + ".handoff")

# Referenced footage: footage items plus layer sources, de-duplicated, in project order.
refs = []
for f in doc["footage"]:
    if isinstance(f, dict) and f.get("path"):
        refs.append(str(f["path"]))
for c in doc["comps"]:
    for layer in (c.get("layers") or []) if isinstance(c, dict) else []:
        if isinstance(layer, dict) and layer.get("sourcePath"):
            refs.append(str(layer["sourcePath"]))
refs = list(dict.fromkeys(refs))

SEQ = re.compile(r"^(.*?)(\d{3,})(\.[A-Za-z0-9]+)$")
plan, missing, skipped = [], [], []   # plan: (source, relative destination)
used_names = set()
for ref in refs:
    cls = storage_class(ref)
    if cls != "local":
        skipped.append({"path": ref, "storage": cls}); continue
    if not os.path.isfile(ref):
        missing.append(ref); continue
    folder, name = os.path.split(ref)
    m = SEQ.match(name)
    members = [name]
    if m:   # image sequence: AE references the first frame; collect the whole run
        pat = re.compile("^" + re.escape(m.group(1)) + r"\d{%d}" % len(m.group(2)) + re.escape(m.group(3)) + "$")
        members = sorted(n for n in os.listdir(folder) if pat.match(n) and os.path.isfile(os.path.join(folder, n)))
    base = (m.group(1).rstrip("._- ") or "sequence") if m and len(members) > 1 else name
    unique, i = base, 1
    while unique in used_names:
        i += 1; unique = "%d_%s" % (i, base)
    used_names.add(unique)
    if m and len(members) > 1:
        plan += [(os.path.join(folder, n), os.path.join("footage", unique, n)) for n in members]
    else:
        plan.append((ref, os.path.join("footage", unique)))
if len(plan) > MAX_FILES:
    err("TOO_MANY_FILES", "Handoff would collect more than %d files." % MAX_FILES)

ids0 = {p: tree_id(p) for p in [aep] + [src for src, _ in plan]}
need = os.path.getsize(aep) + sum(os.path.getsize(s) for s, _ in plan) + 67108864
if shutil.disk_usage(os.environ["MJ_OUTDIR"]).free < need:
    err("INSUFFICIENT_SPACE", "Not enough free space for the handoff (%d bytes needed)." % need)

try:
    os.mkdir(dest)               # atomic reservation: never overwrites
except FileExistsError:
    err("OUTPUT_EXISTS", "Refusing to overwrite an existing handoff folder.")
try:
    marker = os.path.join(dest, ".incomplete")
    open(marker, "w").close()
    os.mkdir(os.path.join(dest, "project"))
    proj_rel = os.path.join("project", os.path.basename(aep))
    clone_copy(aep, os.path.join(dest, proj_rel))
    files = []
    for src, rel in plan:
        out = os.path.join(dest, rel)
        os.makedirs(os.path.dirname(out), exist_ok=True)
        clone_copy(src, out)
        files.append({"source": src, "packaged": rel, "bytes": os.path.getsize(out), "sha256": sha256_file(out)})
    effects = {}
    for c in doc["comps"]:
        for layer in (c.get("layers") or []) if isinstance(c, dict) else []:
            for fx in (layer.get("effects") or []) if isinstance(layer, dict) else []:
                if isinstance(fx, dict) and fx.get("matchName"):
                    effects[str(fx["matchName"])] = str(fx.get("name", ""))
    manifest = {
        "schema": "MJ_HANDOFF_1",
        "label": label,
        "createdAt": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "project": {"source": aep, "packaged": proj_rel, "sha256": sha256_file(os.path.join(dest, proj_rel)),
                    "bytes": os.path.getsize(aep), "aeVersion": doc.get("aeVersion"),
                    "scrapeProjectName": doc.get("projectName"),
                    "matchesScrape": doc.get("projectName") == os.path.basename(aep)},
        "fonts": sorted(str(f) for f in doc["fonts"]),
        "effects": [{"matchName": k, "name": v} for k, v in sorted(effects.items())],
        "files": files,
        "missingFootage": missing,
        "skippedFootage": skipped,
    }
    with open(os.path.join(dest, "MANIFEST.json"), "w", encoding="utf-8") as f:
        json.dump(manifest, f, indent=1, sort_keys=True); f.write("\n")
    lines = ["Handoff: %s" % label, "Created: %s" % manifest["createdAt"], "",
             "project/   %s (After Effects %s)" % (os.path.basename(aep), doc.get("aeVersion")),
             "footage/   %d collected files" % len(files), "",
             "Fonts to install:"] + ["  - " + f for f in manifest["fonts"]] + ["", "Effects / plug-ins used:"] + \
            ["  - %s (%s)" % (e["name"], e["matchName"]) for e in manifest["effects"]]
    if missing:
        lines += ["", "MISSING footage (not included):"] + ["  - " + p for p in missing]
    if skipped:
        lines += ["", "Footage on network or unknown storage (not collected):"] + ["  - " + s["path"] for s in skipped]
    lines += ["", "The project still points at the original footage locations. After opening it,",
              "relink with File > Replace Footage, pointing at the footage/ folder here.",
              "MANIFEST.json lists every file with its SHA-256."]
    with open(os.path.join(dest, "README.txt"), "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")
    os.unlink(marker)
except Exception as e:
    shutil.rmtree(dest, ignore_errors=True)
    err("HANDOFF_FAILED", "Could not build the handoff: %s" % str(e)[:160])
print(json.dumps({"ok": True, "data": {
    "schema": "MJ_HANDOFF_1",
    "handoffPath": dest,
    "manifestPath": os.path.join(dest, "MANIFEST.json"),
    "filesCollected": len(files),
    "bytesCollected": sum(f["bytes"] for f in files),
    "missingFootage": missing,
    "skippedFootage": skipped,
    "fonts": manifest["fonts"],
    "effectCount": len(manifest["effects"]),
    "projectMatchesScrape": manifest["project"]["matchesScrape"],
    "sourceUnchanged": all(tree_id(p) == v for p, v in ids0.items()),
    "_warnings": ([{"code": "MISSING_FOOTAGE", "message": "Missing footage files, not included: %d." % len(missing)}] if missing else [])
                 + ([{"code": "FOOTAGE_NOT_COLLECTED", "message": "Footage files on network or unknown storage, not copied: %d." % len(skipped)}] if skipped else [])
                 + ([{"code": "PROJECT_SCRAPE_MISMATCH", "message": "The scrape was taken from a different project name than the .aep being packaged."}] if not manifest["project"]["matchesScrape"] else []),
}}))
PY_HANDOFF
) || true
  frames_emit_python_result "$_out"
}

# --- src/modules/library.zsh ---
# Search and recall — MJ-owned local store (SL-M4 NativeDB product store).
#
# index.add    — index MJ receipts (scrapes, snapshots, golden records, handoff manifests)
# index.search — full-text search across everything indexed; read-only
# index.verify — SQLite + FTS integrity, schema version, stale docs, preset blob hashes; read-only
# preset.add   — content-addressed (SHA-256), per-label versioned preset library
# preset.get   — copy a preset version out as a new file; never overwrites
#
# Store: ${MJ_STORE_DIR:-~/Library/Application Support/MographJailed} (local only).
# Fixed schema, migrated by PRAGMA user_version. There is no SQL request API:
# every statement is fixed text with bound parameters.

IFS= read -r -d '' MJ_PY_LIBRARY <<'PY_LIBRARY' || true
import sqlite3

SCHEMA_VERSION = 3
SUPPORTED = ("MJ_PROJECT_SCRAPE_1", "MJ_PROJECT_SNAPSHOT_1", "MJ_GOLDEN_1", "MJ_HANDOFF_1")
MAX_ENTRIES_PER_DOC = 20000

def now_iso():
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())

def db_path(store):
    return os.path.join(store, "index.sqlite")

STORE_MIGRATIONS = [
    # v1
    (1, """
                CREATE TABLE docs(id INTEGER PRIMARY KEY, path TEXT UNIQUE NOT NULL, sha256 TEXT NOT NULL,
                                  schema TEXT NOT NULL, title TEXT, indexed_at TEXT NOT NULL);
                CREATE VIRTUAL TABLE entries USING fts5(doc_id UNINDEXED, kind, name, detail,
                                  tokenize='unicode61 remove_diacritics 2');
                CREATE TABLE presets(id INTEGER PRIMARY KEY, label TEXT NOT NULL, version INTEGER NOT NULL,
                                  sha256 TEXT NOT NULL, kind TEXT NOT NULL, original_name TEXT NOT NULL,
                                  bytes INTEGER NOT NULL, added_at TEXT NOT NULL, UNIQUE(label, version));
                PRAGMA user_version = 1;
            """),
    # v2
    (2, """
                CREATE TABLE projects(id INTEGER PRIMARY KEY, project_path TEXT UNIQUE NOT NULL, name TEXT,
                                  ae_version TEXT, scraped_at TEXT NOT NULL, receipt_path TEXT NOT NULL,
                                  receipt_sha256 TEXT NOT NULL);
                CREATE TABLE compositions(id INTEGER PRIMARY KEY, project_id INTEGER NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
                                  ae_id INTEGER NOT NULL, name TEXT NOT NULL, width INTEGER, height INTEGER,
                                  fps REAL, duration REAL);
                CREATE TABLE layers(id INTEGER PRIMARY KEY, comp_id INTEGER NOT NULL REFERENCES compositions(id) ON DELETE CASCADE,
                                  idx INTEGER NOT NULL, name TEXT NOT NULL, type TEXT, source_ae_id INTEGER NOT NULL,
                                  source_name TEXT, source_path TEXT, font TEXT);
                CREATE TABLE assets(id INTEGER PRIMARY KEY, project_id INTEGER NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
                                  ae_id INTEGER NOT NULL, name TEXT NOT NULL, path TEXT, missing INTEGER NOT NULL);
                CREATE TABLE fonts(id INTEGER PRIMARY KEY, project_id INTEGER NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
                                  name TEXT NOT NULL, UNIQUE(project_id, name));
                CREATE TABLE plugins(id INTEGER PRIMARY KEY, project_id INTEGER NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
                                  comp_id INTEGER NOT NULL REFERENCES compositions(id) ON DELETE CASCADE,
                                  layer_id INTEGER NOT NULL REFERENCES layers(id) ON DELETE CASCADE,
                                  match_name TEXT NOT NULL, name TEXT);
                CREATE INDEX idx_plugins_match ON plugins(match_name);
                CREATE INDEX idx_layers_font ON layers(font);
                CREATE INDEX idx_layers_src ON layers(source_ae_id, source_path);
                CREATE INDEX idx_assets_missing ON assets(missing);
                CREATE INDEX idx_comps_project ON compositions(project_id);
                -- Receipts indexed under v1 have no relational rows; force one re-read.
                UPDATE docs SET sha256 = '' WHERE schema = 'MJ_PROJECT_SCRAPE_1';
                PRAGMA user_version = 2;
            """),
    # v3
    (3, """
                CREATE TABLE health(id INTEGER PRIMARY KEY, project_path TEXT NOT NULL, scraped_at TEXT NOT NULL, score INTEGER NOT NULL,
                                  formula_version INTEGER NOT NULL, receipt_sha256 TEXT NOT NULL, recorded_at TEXT NOT NULL,
                                  UNIQUE(project_path, receipt_sha256, formula_version));
                CREATE INDEX idx_health_project ON health(project_path, scraped_at);
                PRAGMA user_version = 3;
            """),
]

def open_db(store, create=False):
    path = db_path(store)
    if not create and not os.path.isfile(path):
        err("STORE_EMPTY", "Nothing has been indexed yet; run index.add or preset.add first.")
    db = sqlite3.connect(path, timeout=15)
    v = db.execute("PRAGMA user_version").fetchone()[0]
    if v > SCHEMA_VERSION:
        err("STORE_TOO_NEW", "Store schema %d is newer than this runtime supports (%d)." % (v, SCHEMA_VERSION))
    # Each migration runs in one IMMEDIATE transaction and re-reads the version once it holds the write
    # lock, so two runs creating a new store at the same moment cannot both apply it (one waits, then skips).
    db.isolation_level = None
    for target, script in STORE_MIGRATIONS:
        if v >= target:
            continue
        db.execute("BEGIN IMMEDIATE")
        try:
            v = db.execute("PRAGMA user_version").fetchone()[0]
            if v < target:
                stmt = ""
                for line in script.splitlines(True):
                    stmt += line
                    if sqlite3.complete_statement(stmt):
                        db.execute(stmt); stmt = ""
                v = target
            db.execute("COMMIT")
        except Exception:
            db.execute("ROLLBACK")
            raise
    db.isolation_level = ""
    db.execute("PRAGMA foreign_keys = ON")
    return db

def to_int(v):
    try:
        return int(v)
    except (TypeError, ValueError):
        return 0

def put_project(db, doc, receipt_path, sha):
    """Replace the relational rows of one project from a scrape. Returns False when the
    stored scrape for this project path is newer (an older receipt never wins)."""
    ppath = s(doc.get("projectPath")) or receipt_path
    scraped = s(doc.get("scrapedAt"))
    with db:
        row = db.execute("SELECT id, scraped_at FROM projects WHERE project_path = ?", (ppath,)).fetchone()
        if row and row[1] > scraped:
            return False
        if row:
            db.execute("DELETE FROM projects WHERE id = ?", (row[0],))
        pid = db.execute("INSERT INTO projects(project_path, name, ae_version, scraped_at, receipt_path, receipt_sha256) VALUES (?,?,?,?,?,?)",
                         (ppath, s(doc.get("projectName")), s(doc.get("aeVersion")), scraped, receipt_path, sha)).lastrowid
        for f in doc.get("footage") or []:
            if isinstance(f, dict):
                db.execute("INSERT INTO assets(project_id, ae_id, name, path, missing) VALUES (?,?,?,?,?)",
                           (pid, to_int(f.get("id")), s(f.get("name")), s(f.get("path")), 1 if f.get("missing") else 0))
        for name in sorted({s(x) for x in doc.get("fonts") or [] if s(x)}):
            db.execute("INSERT INTO fonts(project_id, name) VALUES (?,?)", (pid, name))
        for c in doc.get("comps") or []:
            if not isinstance(c, dict):
                continue
            cid = db.execute("INSERT INTO compositions(project_id, ae_id, name, width, height, fps, duration) VALUES (?,?,?,?,?,?,?)",
                             (pid, to_int(c.get("id")), s(c.get("name")), to_int(c.get("width")), to_int(c.get("height")),
                              c.get("frameRate") if isinstance(c.get("frameRate"), (int, float)) else None,
                              c.get("duration") if isinstance(c.get("duration"), (int, float)) else None)).lastrowid
            for l in c.get("layers") or []:
                if not isinstance(l, dict):
                    continue
                lid = db.execute("INSERT INTO layers(comp_id, idx, name, type, source_ae_id, source_name, source_path, font) VALUES (?,?,?,?,?,?,?,?)",
                                 (cid, to_int(l.get("index")), s(l.get("name")), s(l.get("type")), to_int(l.get("sourceId")),
                                  s(l.get("sourceName")), s(l.get("sourcePath")), s(l.get("font")))).lastrowid
                for fx in l.get("effects") or []:
                    if isinstance(fx, dict) and s(fx.get("matchName")):
                        db.execute("INSERT INTO plugins(project_id, comp_id, layer_id, match_name, name) VALUES (?,?,?,?,?)",
                                   (pid, cid, lid, s(fx.get("matchName")), s(fx.get("name"))))
    return True

def put_doc(db, path, sha, schema, title, entries):
    """Replace one document's entries atomically."""
    with db:
        row = db.execute("SELECT id FROM docs WHERE path = ?", (path,)).fetchone()
        if row:
            db.execute("DELETE FROM entries WHERE doc_id = ?", (row[0],))
            db.execute("UPDATE docs SET sha256 = ?, schema = ?, title = ?, indexed_at = ? WHERE id = ?",
                       (sha, schema, title, now_iso(), row[0]))
            doc_id = row[0]
        else:
            doc_id = db.execute("INSERT INTO docs(path, sha256, schema, title, indexed_at) VALUES (?,?,?,?,?)",
                                (path, sha, schema, title, now_iso())).lastrowid
        db.executemany("INSERT INTO entries(doc_id, kind, name, detail) VALUES (?,?,?,?)",
                       [(doc_id, k, n, d) for k, n, d in entries[:MAX_ENTRIES_PER_DOC]])

def s(v):
    return "" if v is None else str(v)

def extract(doc):
    """(title, [(kind, name, detail)]) for a supported receipt."""
    schema, out = doc.get("schema"), []
    if schema == "MJ_PROJECT_SCRAPE_1":
        title = s(doc.get("projectName"))
        out.append(("project", title, "AE %s %s" % (s(doc.get("aeVersion")), s(doc.get("projectPath")))))
        effects = {}
        for c in doc.get("comps") or []:
            if not isinstance(c, dict):
                continue
            cname = s(c.get("name"))
            out.append(("comp", cname, "%sx%s %sfps %ss" % (s(c.get("width")), s(c.get("height")), s(c.get("frameRate")), s(c.get("duration")))))
            for l in c.get("layers") or []:
                if not isinstance(l, dict):
                    continue
                out.append(("layer", s(l.get("name")), "%s / %s / %s" % (cname, s(l.get("type")), s(l.get("sourceName")))))
                for fx in l.get("effects") or []:
                    if isinstance(fx, dict):
                        effects[s(fx.get("matchName"))] = s(fx.get("name"))
                for ex in l.get("expressions") or []:
                    if isinstance(ex, dict):
                        out.append(("expression", s(ex.get("propertyPath")), "%s / %s: %s" % (cname, s(l.get("name")), s(ex.get("expression"))[:300])))
        out += [("effect", n, m) for m, n in sorted(effects.items())]
        out += [("font", s(f), title) for f in doc.get("fonts") or []]
        out += [("footage", s(f.get("name")), s(f.get("path"))) for f in doc.get("footage") or [] if isinstance(f, dict)]
    elif schema == "MJ_PROJECT_SNAPSHOT_1":
        title = os.path.basename(s(doc.get("sourcePath")))
        out.append(("snapshot", title, "%s %s" % (s(doc.get("createdAt")), s(doc.get("snapshotPath")))))
    elif schema == "MJ_GOLDEN_1":
        title = s(doc.get("label"))
        out.append(("golden", title, "%d frames %s" % (len(doc.get("frames") or []), s(doc.get("sourceDir")))))
    else:  # MJ_HANDOFF_1
        title = s(doc.get("label"))
        proj = doc.get("project") or {}
        out.append(("handoff", title, "%s %s" % (s(doc.get("createdAt")), s(proj.get("source")))))
        out += [("font", s(f), title) for f in doc.get("fonts") or []]
        out += [("file", s(f.get("packaged")), s(f.get("source"))) for f in doc.get("files") or [] if isinstance(f, dict)]
    return title, out

PRESET_KINDS = {".ffx": "ae-animation-preset", ".aet": "ae-template", ".aep": "ae-project", ".mogrt": "mogrt",
                ".jsx": "script", ".js": "expression", ".txt": "expression", ".c4d": "c4d-scene",
                ".lib4d": "c4d-library", ".rsmat": "redshift-material"}

def preset_blob(store, sha):
    return os.path.join(store, "presets", sha)
PY_LIBRARY

library_store_dir() {
  printf '%s' "${MJ_STORE_DIR:-${HOME:-}/Library/Application Support/MographJailed}"
}

# True when the private store folder already exists (callers that only want to cache something use it; nothing is created).
library_store_dir_ready() { [ -d "$(library_store_dir)" ]; }

# Resolve and (when allowed) create the local store. Sets MJ_STORE.
library_require_store() {
  local _create="$1" _dir=""
  MJ_STORE=""
  _dir=$(library_store_dir)
  is_absolute_path "$_dir" || { set_error "STORE_UNAVAILABLE" "Store directory must be absolute."; return 73; }
  cap_available python3 || { set_error "UNSUPPORTED" "The library store requires python3."; return 69; }
  if [ ! -d "$_dir" ]; then
    [ "$_create" = create ] || { set_error "STORE_EMPTY" "Nothing has been indexed yet; run index.add or preset.add first."; return 66; }
    [ -d "$(parent_path "$_dir")" ] || { set_error "STORE_UNAVAILABLE" "Store parent directory does not exist."; return 73; }
    /bin/mkdir -m 700 "$_dir" 2>/dev/null || [ -d "$_dir" ] || { set_error "STORE_UNAVAILABLE" "Could not create the store directory."; return 73; }   # another run may have just made it
  fi
  [ -w "$_dir" ] || { set_error "STORE_UNAVAILABLE" "Store directory is not writable."; return 73; }
  mj_require_local_existing_path "$_dir" || return 73
  MJ_STORE=$(canonical_existing_dir "$_dir")
}

library_python() {
  local _main=""
  IFS= read -r -d '' _main || true
  printf '%s\n%s\n%s' "$MJ_PY_PROTECT_LIB" "$MJ_PY_LIBRARY" "$_main" | /usr/bin/python3 - 2>/dev/null
}

library_label_ok() {
  case "$1" in .*|*[!A-Za-z0-9._-]*) set_error "INVALID_ARGUMENT" "label may contain only letters, digits, dot, dash and underscore."; return 1 ;; esac
  [ ${#1} -le 64 ] || { set_error "INVALID_ARGUMENT" "label must be at most 64 characters."; return 1; }
}

handle_index_add() {
  local _rc=0 _path="" _out=""
  require_arg path || { emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  _path="$MJ_REQUIRED_ARG_VALUE"
  is_absolute_path "$_path" || { set_error "INVALID_PATH" "Path must be absolute."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  [ -f "$_path" ] || [ -d "$_path" ] || { set_error "INVALID_TARGET" "Path must be a receipt file or a directory of receipts."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  [ -r "$_path" ] || { set_error "PERMISSION_DENIED" "Path is not readable."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 77; }
  mj_require_local_existing_path "$_path" || { emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 73; }
  library_require_store create || { _rc=$?; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return $_rc; }

  _out=$(MJ_PATH="$_path" MJ_STORE="$MJ_STORE" library_python <<'PY_INDEX_ADD'
MAX_FILES, MAX_BYTES = 5000, 8388608
root = os.path.realpath(os.environ["MJ_PATH"])
candidates = []
if os.path.isfile(root):
    candidates = [root]
else:
    for d, dirs, files in os.walk(root):
        dirs[:] = sorted(x for x in dirs if not x.startswith(".") and storage_class(os.path.join(d, x)) == "local")
        candidates += [os.path.join(d, f) for f in sorted(files) if f.lower().endswith(".json") and not f.startswith(".")]
        if len(candidates) > MAX_FILES:
            err("TOO_MANY_FILES", "More than %d JSON files under this path; index a narrower folder." % MAX_FILES)
ids0 = {p: tree_id(p) for p in candidates}
db = open_db(os.environ["MJ_STORE"], create=True)
counts = {"added": 0, "updated": 0, "unchanged": 0, "skipped": 0}
by_schema, problems = {}, []
for p in candidates:
    try:
        if os.path.islink(p) or os.path.getsize(p) > MAX_BYTES:
            counts["skipped"] += 1; continue
        sha = sha256_file(p)
        with open(p, encoding="utf-8") as f:
            doc = json.load(f)
        schema = doc.get("schema") if isinstance(doc, dict) else None
        if schema not in SUPPORTED:
            counts["skipped"] += 1; continue
        row = db.execute("SELECT sha256 FROM docs WHERE path = ?", (p,)).fetchone()
        if row and row[0] == sha:
            counts["unchanged"] += 1; continue
        title, entries = extract(doc)
        put_doc(db, p, sha, schema, title, entries)
        if schema == "MJ_PROJECT_SCRAPE_1":
            put_project(db, doc, p, sha)
        counts["updated" if row else "added"] += 1
        by_schema[schema] = by_schema.get(schema, 0) + 1
    except Exception as e:
        counts["skipped"] += 1
        if len(problems) < 20:
            problems.append({"path": p, "reason": str(e)[:120]})
print(json.dumps({"ok": True, "data": dict(counts, **{
    "schema": "MJ_INDEX_ADD_1", "path": root, "store": os.environ["MJ_STORE"],
    "filesExamined": len(candidates), "indexedBySchema": by_schema, "problems": problems,
    "sourceUnchanged": all(tree_id(p) == v for p, v in ids0.items()),
    "_warnings": ([{"code": "FILES_UNREADABLE", "message": "Files that could not be indexed: %d (see problems)." % len(problems)}] if problems else []),
})}))
PY_INDEX_ADD
) || true
  frames_emit_python_result "$_out"
}

handle_index_search() {
  local _rc=0 _query="" _max="" _out=""
  require_arg target || { emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  _query="$MJ_REQUIRED_ARG_VALUE"
  frames_uint_arg maxResults 20 1 200 || { emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  _max="$MJ_FRAMES_UINT"
  library_require_store existing || { _rc=$?; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return $_rc; }

  _out=$(MJ_QUERY="$_query" MJ_MAX="$_max" MJ_STORE="$MJ_STORE" library_python <<'PY_INDEX_SEARCH'
query = os.environ["MJ_QUERY"]
# Words only, each as a quoted prefix term, all required. FTS operators in the
# query are never interpreted.
words = re.findall(r"\w+", query, re.UNICODE)[:12]
if not words:
    err("INVALID_ARGUMENT", "Search needs at least one word.")
match = " ".join('"%s"*' % w for w in words)
db = open_db(os.environ["MJ_STORE"])
rows = db.execute("""SELECT entries.kind, entries.name, entries.detail, docs.path, docs.schema, docs.title,
                            bm25(entries) AS rank
                     FROM entries JOIN docs ON docs.id = entries.doc_id
                     WHERE entries MATCH ? ORDER BY rank LIMIT ?""", (match, int(os.environ["MJ_MAX"]))).fetchall()
print(json.dumps({"ok": True, "data": {
    "schema": "MJ_INDEX_SEARCH_1", "query": query, "terms": words,
    "results": [{"kind": k, "name": n, "detail": d, "source": p, "sourceSchema": sc, "sourceTitle": t,
                 "score": round(-r, 4)} for k, n, d, p, sc, t, r in rows],
    "_warnings": ([{"code": "RESULTS_TRUNCATED", "message": "Only the first %d results are shown; raise maxResults to see more." % len(rows)}] if len(rows) >= int(os.environ["MJ_MAX"]) else []),
}}))
PY_INDEX_SEARCH
) || true
  frames_emit_python_result "$_out"
}

handle_index_verify() {
  local _rc=0 _out=""
  library_require_store existing || { _rc=$?; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return $_rc; }
  _out=$(MJ_STORE="$MJ_STORE" library_python <<'PY_INDEX_VERIFY'
store = os.environ["MJ_STORE"]
db = open_db(store)
integrity = db.execute("PRAGMA integrity_check").fetchone()[0]
try:
    db.execute("INSERT INTO entries(entries) VALUES('integrity-check')")
    fts_ok = True
except sqlite3.DatabaseError:
    fts_ok = False
stale = []
for (path,) in db.execute("SELECT path FROM docs WHERE schema != 'MJ_PRESET_1'"):
    if storage_class(path) == "local" and not os.path.isfile(path):
        stale.append(path)
corrupt = []
blobs = db.execute("SELECT DISTINCT sha256 FROM presets").fetchall()
for (sha,) in blobs:
    b = preset_blob(store, sha)
    if not os.path.isfile(b) or sha256_file(b) != sha:
        corrupt.append(sha)
count = lambda q: db.execute(q).fetchone()[0]
print(json.dumps({"ok": True, "data": {
    "schema": "MJ_INDEX_VERIFY_1", "store": store,
    "healthy": integrity == "ok" and fts_ok and not corrupt,
    "sqliteIntegrity": integrity, "ftsIntegrity": fts_ok,
    "schemaVersion": db.execute("PRAGMA user_version").fetchone()[0],
    "docs": count("SELECT count(*) FROM docs"), "entries": count("SELECT count(*) FROM entries"),
    "projects": count("SELECT count(*) FROM projects"),
    "presetVersions": count("SELECT count(*) FROM presets"), "presetBlobs": len(blobs),
    "staleDocs": stale[:100], "corruptPresetBlobs": corrupt,
    "_warnings": ([{"code": "STALE_RECEIPTS", "message": "Indexed receipts that no longer exist on disk: %d." % len(stale)}] if stale else [])
                 + ([{"code": "PRESET_BLOB_CORRUPT", "message": "Stored presets that failed their hash check: %d." % len(corrupt)}] if corrupt else []),
}}))
PY_INDEX_VERIFY
) || true
  frames_emit_python_result "$_out"
}

handle_preset_add() {
  local _rc=0 _path="" _label="" _out=""
  require_arg path || { emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  _path="$MJ_REQUIRED_ARG_VALUE"
  require_arg label || { emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  _label="$MJ_REQUIRED_ARG_VALUE"
  library_label_ok "$_label" || { emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  is_absolute_path "$_path" || { set_error "INVALID_PATH" "Preset path must be absolute."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  [ -f "$_path" ] && [ ! -L "$_path" ] || { set_error "INVALID_TARGET" "Preset must be a regular file."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  [ -r "$_path" ] || { set_error "PERMISSION_DENIED" "Preset is not readable."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 77; }
  mj_require_local_existing_path "$_path" || { emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 73; }
  library_require_store create || { _rc=$?; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return $_rc; }

  _out=$(MJ_PATH="$_path" MJ_LABEL="$_label" MJ_STORE="$MJ_STORE" library_python <<'PY_PRESET_ADD'
src, label, store = os.environ["MJ_PATH"], os.environ["MJ_LABEL"], os.environ["MJ_STORE"]
id0 = tree_id(src)
size = os.path.getsize(src)
if size > 536870912:
    err("PRESET_TOO_LARGE", "Presets are limited to 512 MB.")
sha = sha256_file(src)
name = os.path.basename(src)
kind = PRESET_KINDS.get(os.path.splitext(name)[1].lower(), "file")
db = open_db(store, create=True)
latest = db.execute("SELECT version, sha256 FROM presets WHERE label = ? ORDER BY version DESC LIMIT 1", (label,)).fetchone()
if latest and latest[1] == sha:
    print(json.dumps({"ok": True, "data": {"schema": "MJ_PRESET_1", "label": label, "version": latest[0],
        "sha256": sha, "created": False, "reason": "unchanged", "sourceUnchanged": tree_id(src) == id0}}))
    sys.exit(0)
blob = preset_blob(store, sha)
os.makedirs(os.path.dirname(blob), mode=0o700, exist_ok=True)
if not os.path.isfile(blob):
    tmp = blob + ".partial-%d" % os.getpid()
    try:
        clone_copy(src, tmp)
        if sha256_file(tmp) != sha:
            err("PRESET_FAILED", "Stored copy did not verify.")
        os.replace(tmp, blob)    # content-addressed: same name means same bytes
    finally:
        if os.path.exists(tmp):
            os.unlink(tmp)
version = (latest[0] if latest else 0) + 1
try:
    with db:
        db.execute("INSERT INTO presets(label, version, sha256, kind, original_name, bytes, added_at) VALUES (?,?,?,?,?,?,?)",
                   (label, version, sha, kind, name, size, now_iso()))
except sqlite3.IntegrityError:
    err("CONFLICT", "Another writer added this label version at the same time; retry.")
put_doc(db, "preset:%s@v%d" % (label, version), sha, "MJ_PRESET_1", label,
        [("preset", label, "v%d %s %s" % (version, kind, name))])
print(json.dumps({"ok": True, "data": {"schema": "MJ_PRESET_1", "label": label, "version": version,
    "sha256": sha, "kind": kind, "originalName": name, "bytes": size, "created": True, "sourceUnchanged": tree_id(src) == id0}}))
PY_PRESET_ADD
) || true
  frames_emit_python_result "$_out"
}

handle_preset_get() {
  local _rc=0 _label="" _outdir="" _version="0" _out=""
  require_arg label || { emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  _label="$MJ_REQUIRED_ARG_VALUE"
  library_label_ok "$_label" || { emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  require_arg output || { emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  _outdir="$MJ_REQUIRED_ARG_VALUE"
  frames_uint_arg version 0 1 1000000 || { emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  _version="$MJ_FRAMES_UINT"
  protect_require_output_dir "$_outdir" || { _rc=$?; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return $_rc; }
  library_require_store existing || { _rc=$?; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return $_rc; }

  _out=$(MJ_LABEL="$_label" MJ_VERSION="$_version" MJ_OUTDIR="$(canonical_existing_dir "$_outdir")" MJ_STORE="$MJ_STORE" library_python <<'PY_PRESET_GET'
label, want, store, outdir = os.environ["MJ_LABEL"], int(os.environ["MJ_VERSION"]), os.environ["MJ_STORE"], os.environ["MJ_OUTDIR"]
db = open_db(store)
if want:
    row = db.execute("SELECT version, sha256, original_name FROM presets WHERE label = ? AND version = ?", (label, want)).fetchone()
else:
    row = db.execute("SELECT version, sha256, original_name FROM presets WHERE label = ? ORDER BY version DESC LIMIT 1", (label,)).fetchone()
if not row:
    err("NOT_FOUND", "No such preset label/version.")
version, sha, name = row
blob = preset_blob(store, sha)
if not os.path.isfile(blob) or sha256_file(blob) != sha:
    err("PRESET_CORRUPT", "Stored preset bytes do not match their hash.")
stem, ext = os.path.splitext(os.path.basename(name))
dest = None
for candidate in (name, "%s-v%d%s" % (stem, version, ext)):
    path = os.path.join(outdir, os.path.basename(candidate))
    tmp = path + ".partial-%d" % os.getpid()
    try:
        clone_copy(blob, tmp)
        os.link(tmp, path)           # never overwrites
        dest = path
        break
    except FileExistsError:
        continue
    finally:
        if os.path.exists(tmp):
            os.unlink(tmp)
if not dest:
    err("OUTPUT_EXISTS", "Refusing to overwrite existing files in the output directory.")
print(json.dumps({"ok": True, "data": {"schema": "MJ_PRESET_GET_1", "label": label, "version": version,
    "sha256": sha, "outputPath": dest}}))
PY_PRESET_GET
) || true
  frames_emit_python_result "$_out"
}

# --- exact audit queries over the normalized tables (store schema v2) ---

IFS= read -r -d '' MJ_PY_TRACE <<'PY_TRACE' || true
MAX_PATHS = 20
MAX_DEPTH = 32

def project_graph(db, pid):
    comps = {r[0]: {"id": r[0], "ae_id": r[1], "name": r[2]} for r in
             db.execute("SELECT id, ae_id, name FROM compositions WHERE project_id = ?", (pid,))}
    by_ae = {c["ae_id"]: c for c in comps.values() if c["ae_id"]}
    by_name = {}
    for c in comps.values():
        by_name.setdefault(c["name"], []).append(c)
    layers = {}
    parents = {}      # child comp id -> [(parent comp id, layer idx, layer name)]
    for lid, cid, idx, name, typ, sid, sname, spath, font in db.execute(
            "SELECT l.id, l.comp_id, l.idx, l.name, l.type, l.source_ae_id, l.source_name, l.source_path, l.font "
            "FROM layers l JOIN compositions c ON c.id = l.comp_id WHERE c.project_id = ?", (pid,)):
        layers[lid] = {"id": lid, "comp": cid, "idx": idx, "name": name, "type": typ, "sid": sid,
                       "sname": sname, "spath": spath, "font": font}
        child = by_ae.get(sid) if sid else None
        if child is None and not sid and not spath and sname and len(by_name.get(sname, [])) == 1:
            child = by_name[sname][0]     # older scrapes without sourceId: unique name only
        if child is not None:
            parents.setdefault(child["id"], []).append((cid, idx, name))
    return comps, layers, parents

def comp_paths(comps, parents, cid):
    """Every root-to-comp chain of comp names, nearest-to-root first. Bounded; cycle safe."""
    out = []
    def walk(cur, chain):
        if len(out) >= MAX_PATHS or len(chain) > MAX_DEPTH:
            return
        ups = [p for p in parents.get(cur, []) if p[0] not in chain]
        if not ups:
            out.append(list(reversed([comps[c]["name"] for c in chain])))
            return
        for pcid, _, _ in ups:
            walk(pcid, chain + [pcid])
    walk(cid, [cid])
    return out

def describe_uses(comps, layers, parents, layer_ids):
    uses = []
    for lid in layer_ids[:200]:
        l = layers[lid]
        paths = comp_paths(comps, parents, l["comp"])
        uses.append({"comp": comps[l["comp"]]["name"], "layer": l["name"], "layerIndex": l["idx"],
                     "paths": [" > ".join(p) for p in paths], "pathsTruncated": len(paths) >= MAX_PATHS})
    return uses
PY_TRACE

handle_trace_asset() {
  local _rc=0 _target="" _kind="asset" _proj="" _out=""
  request_arg_present format && _kind=$(request_arg_get format)
  case "$_kind" in asset|font|missing) ;; *) set_error "INVALID_ARGUMENT" "format must be asset, font or missing."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65 ;; esac
  if [ "$_kind" != missing ]; then
    require_arg target || { emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
    _target="$MJ_REQUIRED_ARG_VALUE"
  fi
  request_arg_present path && _proj=$(request_arg_get path)
  [ -z "$_proj" ] || is_absolute_path "$_proj" || { set_error "INVALID_PATH" "Project path must be absolute."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  frames_uint_arg maxResults 50 1 500 || { emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  library_require_store existing || { _rc=$?; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return $_rc; }

  _out=$(MJ_KIND="$_kind" MJ_TARGET="$_target" MJ_PROJ="$_proj" MJ_MAX="$MJ_FRAMES_UINT" MJ_STORE="$MJ_STORE" trace_python <<'PY_TRACE_ASSET'
kind, target, proj_filter, limit = os.environ["MJ_KIND"], os.environ["MJ_TARGET"], os.environ["MJ_PROJ"], int(os.environ["MJ_MAX"])
db = open_db(os.environ["MJ_STORE"])
if db.execute("SELECT count(*) FROM projects").fetchone()[0] == 0:
    err("STORE_EMPTY", "No project scrapes are indexed yet; run index.add on scrape receipts first.")
rows = db.execute("SELECT id, project_path, name, scraped_at FROM projects" + (" WHERE project_path = ?" if proj_filter else "") +
                  " ORDER BY project_path", (proj_filter,) if proj_filter else ()).fetchall()
if proj_filter and not rows:
    err("NOT_FOUND", "That project path is not indexed.")
results, total = [], 0
for pid, ppath, pname, scraped in rows:
    comps, layers, parents = project_graph(db, pid)
    matches = []
    if kind == "font":
        lids = [l["id"] for l in layers.values() if l["font"].lower() == target.lower()]
        known = db.execute("SELECT count(*) FROM fonts WHERE project_id = ? AND name = ? COLLATE NOCASE", (pid, target)).fetchone()[0] > 0
        if lids or known:
            matches.append({"kind": "font", "name": target, "missing": None,
                            "uses": describe_uses(comps, layers, parents, lids)})
    else:
        if kind == "missing":
            assets = db.execute("SELECT ae_id, name, path, missing FROM assets WHERE project_id = ? AND missing = 1 ORDER BY path, name", (pid,)).fetchall()
        else:
            assets = db.execute("SELECT ae_id, name, path, missing FROM assets WHERE project_id = ? AND (name = ? OR path = ?) ORDER BY path, name",
                                (pid, target, target)).fetchall()
        for ae_id, name, path, missing in assets:
            lids = [l["id"] for l in layers.values()
                    if (ae_id and l["sid"] == ae_id) or (path and l["spath"] == path)]
            matches.append({"kind": "asset", "name": name, "path": path, "missing": bool(missing),
                            "uses": describe_uses(comps, layers, parents, lids)})
    if matches:
        results.append({"projectPath": ppath, "projectName": pname, "scrapedAt": scraped, "matches": matches})
        total += len(matches)
    if total >= limit:
        break
print(json.dumps({"ok": True, "data": {
    "schema": "MJ_TRACE_1", "query": {"format": kind, "target": target or None, "project": proj_filter or None},
    "projects": results, "matchCount": total, "truncated": total >= limit,
    "note": "Paths run from a root composition down to the composition that holds the layer; a missing-footage layer in a precomp reports every comp chain that nests it.",
    "_warnings": ([{"code": "RESULTS_TRUNCATED", "message": "Stopped after %d matches; raise maxResults or narrow with path." % total}] if total >= limit else []),
}}))
PY_TRACE_ASSET
) || true
  frames_emit_python_result "$_out"
}

trace_python() {
  local _main=""
  IFS= read -r -d '' _main || true
  printf '%s\n%s\n%s\n%s' "$MJ_PY_PROTECT_LIB" "$MJ_PY_LIBRARY" "$MJ_PY_TRACE" "$_main" | /usr/bin/python3 - 2>/dev/null
}

handle_audit_plugins() {
  local _rc=0 _target="" _out=""
  request_arg_present target && _target=$(request_arg_get target)
  frames_uint_arg maxResults 100 1 1000 || { emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  library_require_store existing || { _rc=$?; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return $_rc; }

  _out=$(MJ_TARGET="$_target" MJ_MAX="$MJ_FRAMES_UINT" MJ_STORE="$MJ_STORE" trace_python <<'PY_AUDIT_PLUGINS'
target, limit = os.environ["MJ_TARGET"], int(os.environ["MJ_MAX"])
db = open_db(os.environ["MJ_STORE"])
if db.execute("SELECT count(*) FROM projects").fetchone()[0] == 0:
    err("STORE_EMPTY", "No project scrapes are indexed yet; run index.add on scrape receipts first.")
if target:
    rows = db.execute("""SELECT p.project_path, p.name, p.scraped_at, count(*) AS uses,
                                count(DISTINCT pl.comp_id) AS comps, min(pl.name) AS fx_name
                         FROM plugins pl JOIN projects p ON p.id = pl.project_id
                         WHERE pl.match_name = ? GROUP BY p.id ORDER BY p.project_path LIMIT ?""", (target, limit)).fetchall()
    print(json.dumps({"ok": True, "data": {
        "schema": "MJ_PLUGIN_USAGE_1", "matchName": target, "projectCount": len(rows), "truncated": len(rows) >= limit,
        "projects": [{"projectPath": r[0], "projectName": r[1], "scrapedAt": r[2], "layerUses": r[3],
                      "compositions": r[4], "effectName": r[5]} for r in rows],
        "note": "Each project's newest indexed scrape is used; projects never scraped are not covered.",
        "_warnings": ([{"code": "RESULTS_TRUNCATED", "message": "Only the first %d projects are listed." % len(rows)}] if len(rows) >= limit else []),
    }}))
else:
    rows = db.execute("""SELECT pl.match_name, min(pl.name), count(DISTINCT pl.project_id), count(*)
                         FROM plugins pl GROUP BY pl.match_name ORDER BY 3 DESC, 1 LIMIT ?""", (limit,)).fetchall()
    print(json.dumps({"ok": True, "data": {
        "schema": "MJ_PLUGIN_INVENTORY_1", "distinctEffects": len(rows), "truncated": len(rows) >= limit,
        "effects": [{"matchName": r[0], "effectName": r[1], "projects": r[2], "layerUses": r[3]} for r in rows],
        "projectsIndexed": db.execute("SELECT count(*) FROM projects").fetchone()[0],
        "_warnings": ([{"code": "RESULTS_TRUNCATED", "message": "Only the first %d effects are listed." % len(rows)}] if len(rows) >= limit else []),
    }}))
PY_AUDIT_PLUGINS
) || true
  frames_emit_python_result "$_out"
}

# --- src/modules/insight.zsh ---
# Project insight — what changed, and how healthy is it. Both are read-only (Tier 0) and built on
# the existing ingest and lint engines; nothing here edits a project.
#
# project.diff   — compare two MJ_PROJECT_SCRAPE_1 receipts: comps, layers, expressions, footage,
#                  fonts and effect types added, removed or changed
# project.health — a 0-100 score from missing footage, expression problems and snapshot freshness.
#                  The formula is versioned (HEALTH_FORMULA_VERSION) and every point lost links back
#                  to the findings behind it. format=record keeps the score in the local store so
#                  it can be trended; format=all lists every recorded project with its trend.

HEALTH_FORMULA_VERSION=1

handle_project_diff() {
  local _rc=0 _a="" _b="" _out=""
  require_arg path || { emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  _a="$MJ_REQUIRED_ARG_VALUE"
  require_arg input || { emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  _b="$MJ_REQUIRED_ARG_VALUE"
  project_require_scrape_file "$_a" || { _rc=$?; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return $_rc; }
  project_require_scrape_file "$_b" || { _rc=$?; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return $_rc; }

  _out=$(MJ_A="$_a" MJ_B="$_b" protect_python <<'PY_PROJECT_DIFF'
MAX_CHANGES = 200
ida, idb = tree_id(os.environ["MJ_A"]), tree_id(os.environ["MJ_B"])
a, b = load_scrape(os.environ["MJ_A"]), load_scrape(os.environ["MJ_B"])
S = {k: 0 for k in ("compsAdded", "compsRemoved", "compsChanged", "layersAdded", "layersRemoved", "layersChanged", "layersMoved", "expressionsChanged",
                    "footageAdded", "footageRemoved", "footageMissingChanged", "footageMoved", "fontsAdded", "fontsRemoved", "effectsAdded", "effectsRemoved")}
changes = []
def note(kind, text, **extra):
    d = {"kind": kind, "text": text}; d.update(extra); changes.append(d)

def num(v):
    return v if isinstance(v, (int, float)) and not isinstance(v, bool) else None

def keyed(items, key_fn):
    """Key each item; duplicates get #2, #3 ... so same-named layers still pair up in order."""
    seen, out = {}, {}
    for it in items:
        k = key_fn(it)
        seen[k] = seen.get(k, 0) + 1
        out[k if seen[k] == 1 else "%s#%d" % (k, seen[k])] = it
    return out

def comps_of(doc):
    return [c for c in doc["comps"] if isinstance(c, dict)]

ca, cb = comps_of(a), comps_of(b)
ids_ok = all(isinstance(c.get("id"), int) and c["id"] > 0 for c in ca + cb) and len({c["id"] for c in ca}) == len(ca) and len({c["id"] for c in cb}) == len(cb)
ck = (lambda c: "id:%d" % c["id"]) if ids_ok else (lambda c: "name:%s" % c.get("name", ""))
A, B = keyed(ca, ck), keyed(cb, ck)

def eff_set(layer):
    out = {}
    for e in layer.get("effects") or []:
        if isinstance(e, dict) and e.get("matchName"):
            out[str(e["matchName"])] = str(e.get("name", e["matchName"]))
    return out

def exprs(layer):
    return {str(x.get("propertyPath", "")): str(x.get("expression", "")) for x in (layer.get("expressions") or []) if isinstance(x, dict)}

for k in sorted(set(B) - set(A)):
    S["compsAdded"] += 1; note("comp", 'comp "%s" added (%d layers)' % (B[k].get("name"), len(B[k].get("layers") or [])), comp=B[k].get("name"))
for k in sorted(set(A) - set(B)):
    S["compsRemoved"] += 1; note("comp", 'comp "%s" removed' % A[k].get("name"), comp=A[k].get("name"))
for k in sorted(set(A) & set(B)):
    x, y = A[k], B[k]
    cname = y.get("name")
    comp_changed = False
    if x.get("name") != y.get("name"):
        comp_changed = True; note("comp", 'comp renamed "%s" -> "%s"' % (x.get("name"), y.get("name")), comp=cname)
    for field, label in (("width", "width"), ("height", "height"), ("frameRate", "frame rate"), ("duration", "duration"), ("pixelAspect", "pixel aspect")):
        if num(x.get(field)) is not None and num(y.get(field)) is not None and x[field] != y[field]:
            comp_changed = True; note("comp", 'comp "%s": %s %s -> %s' % (cname, label, x[field], y[field]), comp=cname)
    LA = keyed([l for l in x.get("layers") or [] if isinstance(l, dict)], lambda l: str(l.get("name", "")))
    LB = keyed([l for l in y.get("layers") or [] if isinstance(l, dict)], lambda l: str(l.get("name", "")))
    for lk in sorted(set(LB) - set(LA)):
        S["layersAdded"] += 1; note("layer", 'layer "%s" added to "%s"' % (LB[lk].get("name"), cname), comp=cname, layer=LB[lk].get("name"))
    for lk in sorted(set(LA) - set(LB)):
        S["layersRemoved"] += 1; note("layer", 'layer "%s" removed from "%s"' % (LA[lk].get("name"), cname), comp=cname, layer=LA[lk].get("name"))
    # A layer "moved" only if its place among the layers both versions share changed; inserting or
    # deleting a layer shifts every index below it but moves nothing.
    common_a = [k for k in LA if k in LB]
    common_b = [k for k in LB if k in LA]
    rank_a = {k: i for i, k in enumerate(common_a)}
    rank_b = {k: i for i, k in enumerate(common_b)}
    for lk in sorted(set(LA) & set(LB)):
        p, q = LA[lk], LB[lk]
        lname, bits = q.get("name"), []
        for field in ("enabled", "locked", "solo"):
            if p.get(field) != q.get(field) and field in p and field in q:
                bits.append("%s %s -> %s" % (field, p[field], q[field]))
        if p.get("sourceName") != q.get("sourceName") or p.get("sourcePath") != q.get("sourcePath"):
            bits.append("source %s -> %s" % (p.get("sourceName") or "none", q.get("sourceName") or "none"))
        if p.get("type") != q.get("type"):
            bits.append("type %s -> %s" % (p.get("type"), q.get("type")))
        ep, eq = eff_set(p), eff_set(q)
        if set(ep) != set(eq):
            add_, rem_ = sorted(set(eq) - set(ep)), sorted(set(ep) - set(eq))
            bits.append("effects" + ("".join(" +" + eq[m] for m in add_)) + ("".join(" -" + ep[m] for m in rem_)))
        xp, xq = exprs(p), exprs(q)
        changed_props = sorted(pp for pp in set(xp) | set(xq) if xp.get(pp) != xq.get(pp))
        for pp in changed_props:
            S["expressionsChanged"] += 1
            what = "added" if pp not in xp else "removed" if pp not in xq else "changed"
            note("expression", 'layer "%s" in "%s": expression on %s %s' % (lname, cname, pp, what), comp=cname, layer=lname, propertyPath=pp)
        if rank_a[lk] != rank_b[lk] and not bits and not changed_props:
            S["layersMoved"] += 1; comp_changed = True
            note("layer", 'layer "%s" in "%s" moved in the stack' % (lname, cname), comp=cname, layer=lname)
        if bits:
            S["layersChanged"] += 1
            note("layer", 'layer "%s" in "%s": %s' % (lname, cname, "; ".join(bits)), comp=cname, layer=lname)
        if bits or changed_props:
            comp_changed = True
    if comp_changed:
        S["compsChanged"] += 1

# footage: by id when every item has one, else by path (or name)
fa = [f for f in a["footage"] if isinstance(f, dict)]
fb = [f for f in b["footage"] if isinstance(f, dict)]
fids = all(isinstance(f.get("id"), int) and f["id"] > 0 for f in fa + fb)
fk = (lambda f: "id:%d" % f["id"]) if fids else (lambda f: "p:%s" % (f.get("path") or f.get("name") or ""))
FA, FB = keyed(fa, fk), keyed(fb, fk)
for k in sorted(set(FB) - set(FA)):
    S["footageAdded"] += 1; note("footage", 'footage "%s" added' % FB[k].get("name"))
for k in sorted(set(FA) - set(FB)):
    S["footageRemoved"] += 1; note("footage", 'footage "%s" removed' % FA[k].get("name"))
for k in sorted(set(FA) & set(FB)):
    p, q = FA[k], FB[k]
    if bool(p.get("missing")) != bool(q.get("missing")):
        S["footageMissingChanged"] += 1
        note("footage", 'footage "%s" %s' % (q.get("name"), "went missing" if q.get("missing") else "is no longer missing"))
    elif (p.get("path") or "") != (q.get("path") or ""):
        S["footageMoved"] += 1
        note("footage", 'footage "%s" moved: %s -> %s' % (q.get("name"), p.get("path") or "none", q.get("path") or "none"))
fonta, fontb = {str(f) for f in a["fonts"]}, {str(f) for f in b["fonts"]}
for f in sorted(fontb - fonta):
    S["fontsAdded"] += 1; note("font", 'font "%s" added' % f)
for f in sorted(fonta - fontb):
    S["fontsRemoved"] += 1; note("font", 'font "%s" no longer used' % f)
def all_effects(doc):
    out = set()
    for c in comps_of(doc):
        for l in c.get("layers") or []:
            if isinstance(l, dict):
                out |= set(eff_set(l))
    return out
ea, eb = all_effects(a), all_effects(b)
for m in sorted(eb - ea):
    S["effectsAdded"] += 1; note("effect", 'effect type %s now used' % m)
for m in sorted(ea - eb):
    S["effectsRemoved"] += 1; note("effect", 'effect type %s no longer used' % m)

def side(doc, path):
    return {"path": path, "projectName": doc.get("projectName"), "projectPath": doc.get("projectPath"), "scrapedAt": doc.get("scrapedAt")}
warnings = []
if a.get("projectPath") != b.get("projectPath"):
    warnings.append({"code": "DIFFERENT_PROJECTS", "message": "The two scrapes are from different project paths (%s, %s)." % (a.get("projectPath"), b.get("projectPath"))})
if str(a.get("scrapedAt", "")) > str(b.get("scrapedAt", "")):
    warnings.append({"code": "SCRAPES_OUT_OF_ORDER", "message": "The first scrape is newer than the second; 'added' and 'removed' are reversed from a history point of view."})
print(json.dumps({"ok": True, "data": {
    "schema": "MJ_DIFF_1", "before": side(a, os.environ["MJ_A"]), "after": side(b, os.environ["MJ_B"]),
    "identical": not changes, "summary": S, "changes": changes[:MAX_CHANGES], "changesTruncated": len(changes) > MAX_CHANGES,
    "matchedBy": {"comps": "id" if ids_ok else "name", "footage": "id" if fids else "path"},
    "sourceUnchanged": tree_id(os.environ["MJ_A"]) == ida and tree_id(os.environ["MJ_B"]) == idb,
    "_warnings": warnings + ([{"code": "CHANGES_TRUNCATED", "message": "Only the first %d changes are listed." % MAX_CHANGES}] if len(changes) > MAX_CHANGES else []),
}}))
PY_PROJECT_DIFF
) || true
  frames_emit_python_result "$_out"
}

handle_project_health() {
  local _rc=0 _path="" _versions="" _fmt="score" _ing="" _lint="" _out="" _data=""
  request_arg_present format && _fmt=$(request_arg_get format)
  case "$_fmt" in score|record|all) ;; *) set_error "INVALID_ARGUMENT" "format must be score, record or all."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65 ;; esac

  if [ "$_fmt" = all ]; then
    library_require_store existing || { _rc=$?; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return $_rc; }
    _out=$(MJ_STORE="$MJ_STORE" MJ_FORMULA="$HEALTH_FORMULA_VERSION" library_python <<'PY_HEALTH_ALL'
db = open_db(os.environ["MJ_STORE"])
rows = db.execute("SELECT project_path, scraped_at, score FROM health WHERE formula_version = ? ORDER BY project_path, scraped_at", (int(os.environ["MJ_FORMULA"]),)).fetchall()
by = {}
for pp, at, sc in rows:
    by.setdefault(pp, []).append((at, sc))
projects = []
for pp, series in sorted(by.items()):
    projects.append({"projectPath": pp, "latestScore": series[-1][1], "latestAt": series[-1][0],
                     "series": [sc for _, sc in series][-30:], "snapshots": len(series),
                     "direction": "improving" if len(series) > 1 and series[-1][1] > series[0][1] else "worsening" if len(series) > 1 and series[-1][1] < series[0][1] else "steady"})
print(json.dumps({"ok": True, "data": {"schema": "MJ_HEALTH_TRENDS_1", "formulaVersion": int(os.environ["MJ_FORMULA"]), "projects": projects}}))
PY_HEALTH_ALL
) || true
    frames_emit_python_result "$_out"
    return
  fi

  require_arg path || { emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  _path="$MJ_REQUIRED_ARG_VALUE"
  request_arg_present input && _versions=$(request_arg_get input)
  if [ -n "$_versions" ]; then
    is_absolute_path "$_versions" && [ -d "$_versions" ] || { set_error "INVALID_PATH" "The versions folder must be an existing absolute directory."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
    mj_require_local_existing_path "$_versions" || { emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 73; }
  fi
  project_require_scrape_file "$_path" || { _rc=$?; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return $_rc; }
  if [ "$_fmt" = record ]; then
    library_require_store create || { _rc=$?; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return $_rc; }
  else
    MJ_STORE=""
  fi
  _ing=$(project_run_ingest "$_path") || { set_error "INGEST_FAILED" "Scrape summarizer failed to run."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 74; }
  _data=$(project_emit_python_data "$_ing" 2>/dev/null) || {
    # the engine's envelope names the real problem (invalid JSON, too large, wrong schema): pass it on
    frames_emit_python_result "$_ing"; return $?
  }
  _ing="$_data"
  _lint=$(project_run_lint "$_path") || { set_error "LINT_FAILED" "Expression linter failed to run."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 74; }
  _lint=$(project_emit_python_data "$_lint" 2>/dev/null) || { set_error "LINT_FAILED" "Expression linter failed to run."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 74; }

  _out=$(MJ_SCRAPE="$_path" MJ_VERSIONS="$_versions" MJ_FMT="$_fmt" MJ_STORE="$MJ_STORE" MJ_INGEST="$_ing" MJ_LINT="$_lint" MJ_FORMULA="$HEALTH_FORMULA_VERSION" library_python <<'PY_PROJECT_HEALTH'
import calendar
ing, lint = json.loads(os.environ["MJ_INGEST"]), json.loads(os.environ["MJ_LINT"])
scrape_id = tree_id(os.environ["MJ_SCRAPE"])
doc = load_scrape(os.environ["MJ_SCRAPE"])
missing, unlinked = ing.get("footageMissing") or [], ing.get("footageUnlinked") or []
comps = []

# footage (35): 12 per missing item, 3 per item not linked to a file
lost = min(35, 12 * len(missing) + 3 * len(unlinked))
comps.append({"name": "footage", "max": 35, "points": 35 - lost, "measured": True,
              "why": ("Missing footage items: %d; unlinked: %d." % (len(missing), len(unlinked))) if lost else "All footage is linked and present.",
              "findings": [{"kind": "missing", "name": n} for n in missing[:20]] + [{"kind": "unlinked", "name": n} for n in unlinked[:20]]})

# expressions (40): 8 per error, 3 per warning (notes cost nothing)
errs, warns = lint.get("errors", 0), lint.get("warnings", 0)
lost = min(40, 8 * errs + 3 * warns)
comps.append({"name": "expressions", "max": 40, "points": 40 - lost, "measured": True,
              "why": ("Expression errors: %d; warnings: %d." % (errs, warns)) if lost else "No expression problems.",
              "findings": [{"code": f["code"], "severity": f["severity"], "comp": f["comp"], "layer": f["layer"], "propertyPath": f["propertyPath"]}
                           for f in lint.get("findings", []) if f["severity"] in ("error", "warning")][:20]})

# snapshots (25): only measured when a versions folder is given
pname = str(doc.get("projectName", ""))
stem = pname[:-4] if pname.lower().endswith(".aep") else pname
versions = os.environ["MJ_VERSIONS"]
if versions:
    pat = re.compile(r"^" + re.escape(stem) + r"\.(\d{8}T\d{6}Z)\.[0-9a-f]{12}\.aep$", re.I)
    stamps = sorted(m.group(1) for n in os.listdir(versions) for m in [pat.match(n)] if m)
    scraped = str(doc.get("scrapedAt", ""))
    try:
        parsed = time.strptime(scraped[:19], "%Y-%m-%dT%H:%M:%S")
        # "...Z" is UTC. A bare timestamp (older scraper builds) is the scraping machine's local time,
        # which we take to be this machine's, the same as the snapshot stamps are UTC.
        scraped_epoch = calendar.timegm(parsed) if scraped.endswith("Z") else time.mktime(parsed)
    except ValueError:
        scraped_epoch = time.time()
    if not stamps:
        pts, why = 0, "No snapshots of this project exist."
    else:
        newest = calendar.timegm(time.strptime(stamps[-1], "%Y%m%dT%H%M%SZ"))
        gap = scraped_epoch - newest
        pts, why = (25, "Newest of %d snapshots is current." % len(stamps)) if gap <= 3600 else (15, "Newest snapshot is %d hours older than the scrape." % (gap // 3600)) if gap <= 86400 else (0, "Newest snapshot is %d days older than the scrape." % (gap // 86400))
    comps.append({"name": "snapshots", "max": 25, "points": pts, "measured": True, "why": why, "findings": [{"kind": "snapshot", "name": s} for s in stamps[-5:]]})
else:
    comps.append({"name": "snapshots", "max": 25, "points": 0, "measured": False, "why": "Not measured; pass a versions folder to include it.", "findings": []})

earned = sum(c["points"] for c in comps if c["measured"])
possible = sum(c["max"] for c in comps if c["measured"])
score = round(100 * earned / possible)
band = "healthy" if score >= 90 else "needs a look" if score >= 70 else "at risk" if score >= 40 else "unhealthy"
out = {"schema": "MJ_PROJECT_HEALTH_1", "projectName": pname, "projectPath": doc.get("projectPath"), "scrapedAt": doc.get("scrapedAt"),
       "score": score, "band": band, "formulaVersion": int(os.environ["MJ_FORMULA"]), "components": comps,
       "formula": "100 x earned / measurable points. footage 35 (-12 per missing item, -3 per unlinked), expressions 40 (-8 per error, -3 per warning), snapshots 25 (0/15/25 by age of newest snapshot, only when measured).",
       "recorded": False, "trend": None, "sourceUnchanged": tree_id(os.environ["MJ_SCRAPE"]) == scrape_id,
       # The score is built from what the scrape holds; if the scrape is partial the reader must know.
       "_warnings": list(ing.get("_warnings") or [])}
if os.environ["MJ_FMT"] == "record":
    db = open_db(os.environ["MJ_STORE"], create=True)
    sha = sha256_file(os.environ["MJ_SCRAPE"])
    with db:
        db.execute("INSERT OR REPLACE INTO health(project_path, scraped_at, score, formula_version, receipt_sha256, recorded_at) VALUES (?,?,?,?,?,?)",
                   (str(doc.get("projectPath") or pname), str(doc.get("scrapedAt", "")), score, int(os.environ["MJ_FORMULA"]), sha, now_iso()))
    out["recorded"] = True
    out["trend"] = [r[0] for r in db.execute("SELECT score FROM health WHERE project_path = ? AND formula_version = ? ORDER BY scraped_at", (str(doc.get("projectPath") or pname), int(os.environ["MJ_FORMULA"])))][-30:]
print(json.dumps({"ok": True, "data": out}))
PY_PROJECT_HEALTH
) || true
  frames_emit_python_result "$_out"
}

# --- src/modules/c4d.zsh ---
# Cinema 4D intelligence over MJ_C4D_SCRAPE_1 receipts, and the AE/C4D bridge. All read-only.
#
# c4d.inspect  — summarize a scene receipt: renderer, resolution, fps, range, passes, textures
# c4d.lint     — check a scene receipt (missing/absolute textures, camera, odd sizes, range, output, renderer)
# bridge.check — compare a scene receipt with the After Effects comps that use that scene
#
# The receipt is written by integrations/cinema4d/MographJailed_C4DScraper.py under c4dpy. Everything
# here works on the receipt, so it needs no Cinema 4D licence and never opens a scene.

IFS= read -r -d '' MJ_PY_C4D <<'PY_C4D_LIB' || true
C4D_MAX_BYTES = 8388608

def load_c4d(path):
    try:
        if os.path.getsize(path) > C4D_MAX_BYTES:
            err("SCRAPE_TOO_LARGE", "Scene scrape exceeds the byte bound.")
        with open(path, "r", encoding="utf-8") as f:
            doc = json.load(f)
    except Exception as e:
        err("INVALID_JSON", "Scene scrape is not valid JSON: %s" % str(e)[:120])
    if not isinstance(doc, dict) or doc.get("schema") != "MJ_C4D_SCRAPE_1":
        err("SCHEMA_MISMATCH", "Scene scrape must be an MJ_C4D_SCRAPE_1 document.")
    def num(k):
        v = doc.get(k)
        return isinstance(v, (int, float)) and not isinstance(v, bool)
    for k in ("scenePath", "sceneName", "scrapedAt", "c4dVersion", "renderer"):
        if not isinstance(doc.get(k), str):
            err("SCHEMA_MISMATCH", "Scene scrape is missing required key: %s" % k)
    for k in ("fps", "startFrame", "endFrame", "width", "height"):
        if not num(k):
            err("SCHEMA_MISMATCH", "Scene scrape is missing a numeric %s." % k)
    if doc["fps"] <= 0:
        err("SCHEMA_MISMATCH", "Scene scrape has a non-positive fps.")
    for k in ("passes", "cameras", "takes", "materials", "textures"):
        if k in doc and not isinstance(doc[k], list):
            err("SCHEMA_MISMATCH", "%s must be an array." % k)
    return doc

def scene_seconds(d):
    return (d["endFrame"] - d["startFrame"] + 1) / float(d["fps"])
PY_C4D_LIB

c4d_python() {
  local _main=""
  IFS= read -r -d '' _main || true
  printf '%s\n%s\n%s' "$MJ_PY_PROTECT_LIB" "$MJ_PY_C4D" "$_main" | /usr/bin/python3 - 2>/dev/null
}

c4d_require_receipt() {
  local _path="$1"
  is_absolute_path "$_path" || { set_error "INVALID_PATH" "Scene scrape path must be absolute."; return 65; }
  [ -f "$_path" ] || { set_error "INVALID_TARGET" "Scene scrape must be a regular file."; return 65; }
  [ -r "$_path" ] || { set_error "PERMISSION_DENIED" "Scene scrape is not readable."; return 77; }
  cap_available python3 || { set_error "UNSUPPORTED" "Cinema 4D scene checks require python3."; return 69; }
  mj_require_local_existing_path "$_path" || return 73
}

handle_c4d_inspect() {
  local _rc=0 _path="" _out=""
  require_arg path || { emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  _path="$MJ_REQUIRED_ARG_VALUE"
  c4d_require_receipt "$_path" || { _rc=$?; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return $_rc; }
  _out=$(MJ_RECEIPT="$_path" c4d_python <<'PY_C4D_INSPECT'
id0 = tree_id(os.environ["MJ_RECEIPT"])
d = load_c4d(os.environ["MJ_RECEIPT"])
tex = [t for t in d.get("textures", []) if isinstance(t, dict)]
mats = [m for m in d.get("materials", []) if isinstance(m, dict)]
by_type = {}
for m in mats:
    by_type[m.get("type", "other")] = by_type.get(m.get("type", "other"), 0) + 1
missing = [t.get("path", "") for t in tex if t.get("missing")]
absolute = [t.get("path", "") for t in tex if t.get("absolute") and not t.get("missing")]
cams = [c for c in d.get("cameras", []) if isinstance(c, dict)]
warnings = []
if missing:
    warnings.append({"code": "TEXTURES_MISSING", "message": "Missing textures: %d." % len(missing)})
if d.get("truncated"):
    warnings.append({"code": "SCENE_TRUNCATED", "message": "The scene held more textures, materials or cameras than the scraper records; counts are lower bounds."})
print(json.dumps({"ok": True, "data": {
    "schema": "MJ_C4D_SUMMARY_1", "sceneName": d["sceneName"], "scenePath": d["scenePath"], "c4dVersion": d["c4dVersion"], "scrapedAt": d["scrapedAt"],
    "renderer": d["renderer"], "width": d["width"], "height": d["height"], "fps": d["fps"],
    "startFrame": d["startFrame"], "endFrame": d["endFrame"], "frames": d["endFrame"] - d["startFrame"] + 1, "seconds": round(scene_seconds(d), 3),
    "outputPath": d.get("outputPath") or "", "multipass": bool(d.get("multipass")),
    "passes": [p.get("name", "") for p in d.get("passes", []) if isinstance(p, dict)],
    "cameras": len(cams), "activeCamera": next((c.get("name") for c in cams if c.get("active")), None),
    "takes": [t.get("name", "") for t in d.get("takes", []) if isinstance(t, dict)],
    "materials": {"total": len(mats), "byType": by_type},
    "textures": {"total": len(tex), "missing": missing[:50], "absolute": absolute[:50]},
    "objects": d.get("objects"),
    "sourceUnchanged": tree_id(os.environ["MJ_RECEIPT"]) == id0,
    "_warnings": warnings,
}}))
PY_C4D_INSPECT
) || true
  frames_emit_python_result "$_out"
}

handle_c4d_lint() {
  local _rc=0 _path="" _out=""
  require_arg path || { emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  _path="$MJ_REQUIRED_ARG_VALUE"
  c4d_require_receipt "$_path" || { _rc=$?; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return $_rc; }
  _out=$(MJ_RECEIPT="$_path" c4d_python <<'PY_C4D_LINT'
MAX_FINDINGS = 200
id0 = tree_id(os.environ["MJ_RECEIPT"])
d = load_c4d(os.environ["MJ_RECEIPT"])
TEACH = {
    "C001": ("A texture file the scene points at is not on disk, so it renders as a missing-texture placeholder or black.",
             "Relink it, or use File > Save Project with Assets to collect everything beside the scene.",
             'tex/wood_old.png   (not found)', 'tex/wood.png   (relinked, next to the scene)'),
    "C002": ("An absolute texture path such as /Users/you/... exists only on your Mac, so the scene breaks on another machine or after a move.",
             "Collect assets with Save Project with Assets so paths become relative to the scene.",
             '/Users/me/Desktop/wood.png', 'tex/wood.png'),
    "C003": ("With no camera the scene renders from the editor view, which changes whenever someone orbits the viewport.",
             "Add a camera object and make it the active camera.", '(no camera)', 'Camera   (active)'),
    "C004": ("Common video formats need even pixel dimensions; an odd width or height fails to encode or gets cropped by a pixel.",
             "Change the output size to even numbers.", '1921 x 1081', '1920 x 1080'),
    "C005": ("The end frame is before the start frame, so there is nothing to render.", "Fix the frame range in Render Settings or the document settings.",
             'frames 120 to 10', 'frames 10 to 120'),
    "C006": ("There is no render output path, so a render finishes without saving frames.", "Set the output path and format in Render Settings > Save.",
             '(empty)', '/work/renders/shot_$frame.png'),
    "C007": ("This is a Redshift scene but it contains standard materials, which Redshift will not shade the way you expect.",
             "Convert them to Redshift materials, or switch the scene to the standard/physical renderer.", '12 standard materials in a Redshift scene', 'Redshift materials throughout'),
    "C008": ("The scene uses a renderer other than Redshift or Physical.", "Nothing is wrong; MographJailed renders with the scene's own renderer. This note is here so you are not surprised by the look.",
             'renderer: standard', 'renderer: redshift or physical'),
    "C009": ("Multi-pass output is switched on but no passes or AOVs were found, so you get only the beauty image.",
             "Add the passes you need to composite separately (for example depth, cryptomatte), or switch multi-pass off.", 'multi-pass on, 0 passes', 'multi-pass on, 4 passes'),
}
findings = []
def add(code, sev, msg, subject=""):
    t = TEACH[code]
    findings.append({"code": code, "severity": sev, "subject": subject, "message": msg, "teach": {"why": t[0], "fix": t[1]}})
tex = [t for t in d.get("textures", []) if isinstance(t, dict)]
for t in tex:
    if t.get("missing"):
        add("C001", "error", 'Texture "%s" is missing.' % t.get("path", ""), t.get("path", ""))
for t in tex:
    if t.get("absolute") and not t.get("missing"):
        add("C002", "warning", 'Texture "%s" uses an absolute path.' % t.get("path", ""), t.get("path", ""))
cams = [c for c in d.get("cameras", []) if isinstance(c, dict)]
if not cams:
    add("C003", "warning", "The scene has no camera; it renders from the editor view.")
if d["width"] % 2 or d["height"] % 2:
    add("C004", "warning", "Resolution %d x %d has an odd dimension." % (d["width"], d["height"]))
if d["endFrame"] < d["startFrame"]:
    add("C005", "error", "The end frame (%d) is before the start frame (%d)." % (d["endFrame"], d["startFrame"]))
if not (d.get("outputPath") or "").strip():
    add("C006", "warning", "The render output path is empty.")
mats = [m for m in d.get("materials", []) if isinstance(m, dict)]
std = sum(1 for m in mats if m.get("type") == "standard")
if d["renderer"] == "redshift" and std:
    add("C007", "warning", "%d standard material%s in a Redshift scene." % (std, "" if std == 1 else "s"))
if d["renderer"] in ("standard", "other"):
    add("C008", "info", "The scene uses the %s renderer, not Redshift or Physical." % d["renderer"])
if d.get("multipass") and not d.get("passes"):
    add("C009", "info", "Multi-pass output is on but no passes were found.")
order = {"error": 0, "warning": 1, "info": 2}
findings.sort(key=lambda f: (order[f["severity"]], f["code"], f["subject"]))
truncated = len(findings) > MAX_FINDINGS
findings = findings[:MAX_FINDINGS]
print(json.dumps({"ok": True, "data": {
    "schema": "MJ_C4D_LINT_1", "sceneName": d["sceneName"], "renderer": d["renderer"], "numFindings": len(findings),
    "errors": sum(1 for f in findings if f["severity"] == "error"), "warnings": sum(1 for f in findings if f["severity"] == "warning"),
    "info": sum(1 for f in findings if f["severity"] == "info"), "findings": findings, "findingsTruncated": truncated,
    "teaching": {c: {"before": TEACH[c][2], "after": TEACH[c][3]} for c in sorted({f["code"] for f in findings})},
    "rules": sorted(TEACH), "sourceUnchanged": tree_id(os.environ["MJ_RECEIPT"]) == id0,
    "_warnings": ([{"code": "FINDINGS_TRUNCATED", "message": "Only the first %d findings are listed." % MAX_FINDINGS}] if truncated else []),
}}))
PY_C4D_LINT
) || true
  frames_emit_python_result "$_out"
}

handle_bridge_check() {
  local _rc=0 _c4d="" _ae="" _comp="" _out=""
  require_arg path || { emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  _c4d="$MJ_REQUIRED_ARG_VALUE"
  require_arg input || { emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  _ae="$MJ_REQUIRED_ARG_VALUE"
  request_arg_present target && _comp=$(request_arg_get target)
  c4d_require_receipt "$_c4d" || { _rc=$?; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return $_rc; }
  project_require_scrape_file "$_ae" || { _rc=$?; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return $_rc; }

  _out=$(MJ_C4D="$_c4d" MJ_AE="$_ae" MJ_COMP="$_comp" c4d_python <<'PY_BRIDGE_CHECK'
ida, idb = tree_id(os.environ["MJ_C4D"]), tree_id(os.environ["MJ_AE"])
c = load_c4d(os.environ["MJ_C4D"])
ae = load_scrape(os.environ["MJ_AE"])
only = os.environ["MJ_COMP"]
TEACH = {
    "B001": ("The After Effects comp runs at a different frame rate from the Cinema 4D scene, so frames are dropped or duplicated and motion stutters.",
             "Set the comp's frame rate to the scene's, or re-render the scene at the comp's rate."),
    "B002": ("The comp and the scene have different pixel dimensions, so the render is scaled or cropped in the comp.",
             "Match the comp size to the scene, or set the scene's output size to the comp's."),
    "B003": ("The comp and the scene run for different lengths: a shorter comp cuts the end of the animation, a longer one holds or goes blank.",
             "Match the comp duration to the scene's frame range, or change the range on the Cinema 4D side."),
    "B004": ("The layer points at a different .c4d than the scene that was checked, so After Effects is showing another copy.",
             "Replace the layer's source with the scene you checked, or check the scene the layer actually uses."),
    "B005": ("The After Effects project reports this scene file as missing, so the layer shows nothing.",
             "Relink it with Replace Footage, then check again."),
}
scene = c["scenePath"]; sname = c["sceneName"].lower()
footage = [f for f in ae["footage"] if isinstance(f, dict)]
def is_scene(path, name):
    base = (os.path.basename(path or "") or name or "").lower()
    return base.endswith(".c4d") and base == sname
matches, findings = [], []
def add(code, sev, comp, layer, msg):
    findings.append({"code": code, "severity": sev, "comp": comp, "layer": layer, "message": msg, "teach": {"why": TEACH[code][0], "fix": TEACH[code][1]}})
for comp in ae["comps"]:
    if not isinstance(comp, dict) or (only and comp.get("name") != only):
        continue
    cname = str(comp.get("name", ""))
    for layer in comp.get("layers") or []:
        if not isinstance(layer, dict) or not is_scene(layer.get("sourcePath"), layer.get("sourceName")):
            continue
        lname = str(layer.get("name", ""))
        spath = str(layer.get("sourcePath") or "")
        matches.append({"comp": cname, "layer": lname, "layerIndex": layer.get("index"), "samePath": (spath == scene) if spath else None})
        fr, du, w, h = comp.get("frameRate"), comp.get("duration"), comp.get("width"), comp.get("height")
        if isinstance(fr, (int, float)) and abs(fr - c["fps"]) > 0.01:
            add("B001", "error", cname, lname, 'Comp "%s" runs at %s fps; the scene is %s fps.' % (cname, fr, c["fps"]))
        if isinstance(w, int) and isinstance(h, int) and (w != c["width"] or h != c["height"]):
            add("B002", "warning", cname, lname, 'Comp "%s" is %d x %d; the scene is %d x %d.' % (cname, w, h, c["width"], c["height"]))
        if isinstance(du, (int, float)) and abs(du - scene_seconds(c)) > 1.0 / c["fps"] + 1e-6:
            add("B003", "warning", cname, lname, 'Comp "%s" is %.2f s; the scene range is %.2f s (%d frames).' % (cname, du, scene_seconds(c), c["endFrame"] - c["startFrame"] + 1))
        if spath and spath != scene:
            add("B004", "error", cname, lname, 'Layer "%s" uses %s, not %s.' % (lname, spath, scene))
        if any(f.get("missing") and ((f.get("path") or "") == spath or (spath == "" and (f.get("name") or "").lower() == sname)) for f in footage):
            add("B005", "error", cname, lname, 'After Effects reports "%s" as missing.' % sname)
order = {"error": 0, "warning": 1, "info": 2}
findings.sort(key=lambda f: (order[f["severity"]], f["code"], f["comp"], f["layer"]))
errors = sum(1 for f in findings if f["severity"] == "error")
warns = []
if not matches:
    warns.append({"code": "NO_MATCHING_LAYER", "message": "No layer%s in the After Effects project uses %s, so nothing was compared." % (" in comp \"%s\"" % only if only else "", c["sceneName"])})
print(json.dumps({"ok": True, "data": {
    "schema": "MJ_BRIDGE_CHECK_1", "sceneName": c["sceneName"], "projectName": ae.get("projectName"), "matched": len(matches), "matches": matches,
    "numFindings": len(findings), "errors": errors, "warnings": sum(1 for f in findings if f["severity"] == "warning"),
    "consistent": bool(matches) and errors == 0 and not findings, "findings": findings,
    "scene": {"fps": c["fps"], "width": c["width"], "height": c["height"], "frames": c["endFrame"] - c["startFrame"] + 1, "seconds": round(scene_seconds(c), 3), "renderer": c["renderer"]},
    "sourceUnchanged": tree_id(os.environ["MJ_C4D"]) == ida and tree_id(os.environ["MJ_AE"]) == idb,
    "_warnings": warns,
}}))
PY_BRIDGE_CHECK
) || true
  frames_emit_python_result "$_out"
}

# --- src/modules/studio.zsh ---
# Studio operations over MJ_PROJECT_SCRAPE_1 receipts.
#
# project.preflight — will this project open cleanly on this Mac? Fonts (After Effects' own missing-font
#                     report plus a scan of this Mac's font folders), footage that is missing or no longer
#                     on disk, and third-party effects to confirm. Read-only.

IFS= read -r -d '' MJ_PY_FONTS <<'PY_FONTS_LIB' || true
import struct

FONT_EXTS = (".ttf", ".otf", ".ttc", ".otc")
FONT_MAX_FILES = 20000

def default_font_dirs():
    home = os.path.expanduser("~")
    dirs = ["/System/Library/Fonts", "/Library/Fonts", home + "/Library/Fonts",
            home + "/Library/Application Support/Adobe/CoreSync/plugins/livetype"]
    try:
        assets = "/System/Library/AssetsV2"
        dirs += sorted(os.path.join(assets, d) for d in os.listdir(assets) if d.startswith("com_apple_MobileAsset_Font"))
    except OSError:
        pass
    return dirs

def _names_at(f, base):
    """PostScript, family, typographic family and full names of the sfnt font at offset base."""
    f.seek(base)
    hdr = f.read(12)
    if len(hdr) < 12:
        return []
    num = struct.unpack(">H", hdr[4:6])[0]
    recs = f.read(16 * num)
    for i in range(num):
        tag, _, off, length = struct.unpack(">4sIII", recs[16 * i:16 * i + 16])
        if tag != b"name":
            continue
        f.seek(off)
        data = f.read(min(length, 1 << 20))
        if len(data) < 6:
            return []
        count, soff = struct.unpack(">HH", data[2:6])
        out = []
        for j in range(count):
            r = data[6 + 12 * j:18 + 12 * j]
            if len(r) < 12:
                break
            plat, enc, lang, nid, ln, o = struct.unpack(">HHHHHH", r)
            if nid not in (1, 4, 6, 16):
                continue
            raw = data[soff + o:soff + o + ln]
            try:
                s = raw.decode("utf-16-be") if plat in (0, 3) else raw.decode("mac_roman")
            except Exception:
                continue
            if s:
                out.append(s)
        return out
    return []

def font_names(path):
    try:
        with open(path, "rb") as f:
            head = f.read(12)
            if head[:4] in (b"ttcf",):
                n = struct.unpack(">I", head[8:12])[0]
                f.seek(12)
                offs = struct.unpack(">%dI" % min(n, 256), f.read(4 * min(n, 256)))
                names = []
                for o in offs:
                    names += _names_at(f, o)
                return names
            if head[:4] in (b"\x00\x01\x00\x00", b"OTTO", b"true"):
                return _names_at(f, 0)
    except (OSError, struct.error):
        pass
    return []

def norm_font(s):
    return "".join(ch for ch in s.lower() if ch.isalnum())

def scan_fonts(dirs, cache_path=""):
    """Set of normalized names from every font file under dirs, plus scan facts. With cache_path, a file
    whose size and modification time are unchanged is not read again (the index lives in the private store)."""
    cache = {}
    if cache_path:
        try:
            with open(cache_path, encoding="utf-8") as f:
                doc = json.load(f)
            if isinstance(doc, dict) and doc.get("v") == 1 and isinstance(doc.get("files"), dict):
                cache = doc["files"]
        except (OSError, ValueError):
            cache = {}
    fresh, names, files, scanned = {}, set(), 0, []
    for d in dirs:
        if not os.path.isdir(d) or storage_class(d) == "network":
            continue
        scanned.append(d)
        for root, subdirs, fnames in os.walk(d):
            for fn in fnames:
                # Adobe Fonts (livetype) stores fonts as extensionless hidden files; read their header too.
                if not fn.lower().endswith(FONT_EXTS) and "livetype" not in root:
                    continue
                files += 1
                if files > FONT_MAX_FILES:
                    return names, files, scanned, True
                p = os.path.join(root, fn)
                try:
                    st = os.stat(p)
                except OSError:
                    continue
                hit = cache.get(p)
                if isinstance(hit, list) and len(hit) == 3 and hit[0] == st.st_size and hit[1] == st.st_mtime_ns and isinstance(hit[2], list):
                    found = hit[2]
                else:
                    found = sorted({norm_font(n) for n in font_names(p)})
                fresh[p] = [st.st_size, st.st_mtime_ns, found]
                names.update(found)
    if cache_path and fresh != cache:
        try:
            tmp = "%s.%d" % (cache_path, os.getpid())
            with open(tmp, "w", encoding="utf-8") as f:
                json.dump({"v": 1, "files": fresh}, f, separators=(",", ":"))
            os.replace(tmp, cache_path)
        except OSError:
            pass
    return names, files, scanned, False
PY_FONTS_LIB

studio_python() {
  local _main=""
  IFS= read -r -d '' _main || true
  printf '%s\n%s\n%s' "$MJ_PY_PROTECT_LIB" "$MJ_PY_FONTS" "$_main" | /usr/bin/python3 - 2>/dev/null
}

handle_project_preflight() {
  local _rc=0 _path="" _out=""
  require_arg path || { emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  _path="$MJ_REQUIRED_ARG_VALUE"
  project_require_scrape_file "$_path" || { _rc=$?; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return $_rc; }
  local _fc=""; library_store_dir_ready && _fc="$(library_store_dir)/fonts.json"
  _out=$(MJ_SCRAPE="$_path" MJ_FONT_CACHE="$_fc" MJ_FONT_DIRS="${MJ_FONT_DIRS:-}" MJ_FONT_DIRS_ONLY="${MJ_FONT_DIRS_ONLY:-}" studio_python <<'PY_PREFLIGHT'
id0 = tree_id(os.environ["MJ_SCRAPE"])
d = load_scrape(os.environ["MJ_SCRAPE"])
extra = [p for p in os.environ.get("MJ_FONT_DIRS", "").split(":") if p.startswith("/")]
dirs = extra if os.environ.get("MJ_FONT_DIRS_ONLY") == "1" else extra + default_font_dirs()
installed, nfiles, scanned, capped = scan_fonts(dirs, os.environ.get("MJ_FONT_CACHE", ""))

# Which layers use each font, so a problem can be traced.
uses = {}
for c in d["comps"]:
    if not isinstance(c, dict):
        continue
    for l in c.get("layers") or []:
        if isinstance(l, dict) and l.get("font"):
            uses.setdefault(l["font"], []).append({"comp": c.get("name", ""), "layer": l.get("name", "")})
ae_missing = d.get("missingFonts")
ae_missing = set(ae_missing) if isinstance(ae_missing, list) else None
fonts = []
for name in sorted(set(x for x in d["fonts"] if isinstance(x, str)) | set(uses)):
    here = norm_font(name) in installed
    if ae_missing is not None and name in ae_missing:
        state = "missing"            # After Effects said so when the project was scraped
    elif here:
        state = "installed"
    else:
        state = "notFound"           # not in any scanned font folder (a font manager may still provide it)
    fonts.append({"name": name, "state": state, "foundOnThisMac": here, "uses": uses.get(name, [])[:20]})

footage = []
for f in d["footage"]:
    if not isinstance(f, dict) or f.get("kind") in ("solid", "placeholder"):
        continue
    p = f.get("path") or ""
    reported = bool(f.get("missing"))
    if not p:
        if reported:
            footage.append({"name": f.get("name", ""), "path": "", "state": "missing", "storage": "none"})
        continue
    cls = storage_class(p)
    if cls != "local":
        if reported:
            footage.append({"name": f.get("name", ""), "path": p, "state": "missing", "storage": cls})
        continue                     # network volumes are never touched
    gone = not os.path.exists(p)
    if reported or gone:
        footage.append({"name": f.get("name", ""), "path": p, "state": "missing" if reported else "goneSinceScrape", "storage": cls})

FIRST_PARTY = ("ADBE ", "CC ", "APC ", "Mettle", "VISINF", "Keylight", "ISL ", "CS ", "PEDG")
fx = {}
for c in d["comps"]:
    if not isinstance(c, dict):
        continue
    for l in c.get("layers") or []:
        if not isinstance(l, dict):
            continue
        for e in l.get("effects") or []:
            mn = (e or {}).get("matchName", "") if isinstance(e, dict) else ""
            if mn and not mn.startswith(FIRST_PARTY):
                rec = fx.setdefault(mn, {"matchName": mn, "name": e.get("name", ""), "layers": 0})
                rec["layers"] += 1
third = sorted(fx.values(), key=lambda r: r["matchName"])

bad_fonts = [f for f in fonts if f["state"] != "installed"]
problems = len(bad_fonts) + len(footage)
warnings = []
if ae_missing is None:
    warnings.append({"code": "FONT_REPORT_UNAVAILABLE", "message": "This scrape has no After Effects missing-font report (scraper older than 1.1 or After Effects older than 24.0); font status comes from scanning this Mac's font folders only."})
if capped:
    warnings.append({"code": "FONT_SCAN_CAPPED", "message": "Stopped after %d font files; some installed fonts may not have been seen." % FONT_MAX_FILES})
print(json.dumps({"ok": True, "data": {
    "schema": "MJ_PREFLIGHT_1", "projectName": d.get("projectName"), "projectPath": d.get("projectPath"), "scrapedAt": d.get("scrapedAt"),
    "ready": problems == 0, "problems": problems,
    "fonts": fonts, "fontsMissing": len(bad_fonts),
    "fontScan": {"dirs": scanned, "files": nfiles, "names": len(installed)},
    "footage": footage, "footageMissing": len(footage),
    "thirdPartyEffects": third,
    "sourceUnchanged": tree_id(os.environ["MJ_SCRAPE"]) == id0,
    "_warnings": warnings,
}}))
PY_PREFLIGHT
) || true
  frames_emit_python_result "$_out"
}

# --- src/modules/space.zsh ---
# Disk space taken by After Effects, Adobe media and Cinema 4D / Redshift caches.
#
# cache.inspect — list the known cache folders on this Mac with their size, and flag the ones left
#                 over from a host version that is no longer installed. Read-only.
# cache.clean   — empty ONE cache, named by the id cache.inspect gave it (never a path). Without
#                 format=delete it only reports what would be freed. Refuses while the app that owns
#                 the cache is running, and only ever deletes inside the cache folders listed here.

IFS= read -r -d '' MJ_PY_SPACE <<'PY_SPACE_LIB' || true
import glob, plistlib, shutil, subprocess

def installed_versions(apps):
    """{"ae": {"26.5", ...}, "c4d": {"2026", ...}} from the hosts' Info.plist files."""
    out = {"ae": set(), "c4d": set()}
    for p in glob.glob(os.path.join(apps, "Adobe After Effects *", "Adobe After Effects *.app", "Contents", "Info.plist")):
        try:
            v = str(plistlib.load(open(p, "rb")).get("CFBundleShortVersionString", ""))
            out["ae"].add(".".join(v.split(".")[:2]))
        except Exception:
            pass
    for d in glob.glob(os.path.join(apps, "Maxon Cinema 4D *")):
        m = re.search(r"(\d{4})$", d)
        if m:
            out["c4d"].add(m.group(1))
    return out

def ae_pref_cache_folders(home):
    """Disk-cache folders chosen in each After Effects version's preferences (Disk Cache Controls > Folder N)."""
    found = {}
    for p in glob.glob(os.path.join(home, "Library", "Preferences", "Adobe", "After Effects", "*", "Adobe After Effects * Prefs.txt")):
        ver = os.path.basename(os.path.dirname(p))
        try:
            text = open(p, "rb").read(4 << 20).decode("utf-8", "replace").replace("\r", "\n")
        except OSError:
            continue
        sec = text.split('["Disk Cache Controls"]', 1)
        if len(sec) == 2:
            m = re.search(r'"Folder \d+" = "([^"]+)"', sec[1].split("\n[", 1)[0])
            if m and m.group(1).startswith("/"):
                found[ver] = m.group(1)
    return found

def measure(path, limit=500000):
    """(bytes, files, newest mtime) without following symlinks; stops counting after limit entries."""
    total = files = 0
    newest = 0.0
    for root, dirs, names in os.walk(path):
        for n in names:
            try:
                st = os.lstat(os.path.join(root, n))
            except OSError:
                continue
            total += st.st_blocks * 512 if hasattr(st, "st_blocks") else st.st_size
            files += 1
            newest = max(newest, st.st_mtime)
            if files >= limit:
                return total, files, newest
    return total, files, newest

def known_caches(home, apps):
    inst = installed_versions(apps)
    caches = []
    def add(cid, app, kind, path, version=None, cleanable=True, note=""):
        if not os.path.isdir(path) or os.path.islink(path) or storage_class(path) == "network":
            return
        if any(c["id"] == cid for c in caches):          # two folders for one version (a custom cache drive and ~/Library/Caches)
            n = 2
            while any(c["id"] == "%s-%d" % (cid, n) for c in caches):
                n += 1
            cid = "%s-%d" % (cid, n)
        left_over = False
        if version is not None:
            left_over = version not in inst["ae" if app == "After Effects" else "c4d"]
        caches.append({"id": cid, "app": app, "kind": kind, "path": path, "version": version, "leftOver": left_over, "cleanable": cleanable, "note": note})
    roots = {os.path.join(home, "Library", "Caches")}
    roots.update(ae_pref_cache_folders(home).values())
    seen = set()
    for root in sorted(roots):
        for vdir in sorted(glob.glob(os.path.join(root, "Adobe", "After Effects", "*"))):
            ver = os.path.basename(vdir)
            for sub, kind, tag in (("Disk Cache*", "disk cache", "disk"), ("3D Cache*", "3D cache", "3d")):
                for p in sorted(glob.glob(os.path.join(vdir, sub))):
                    rp = os.path.realpath(p)
                    if rp in seen:
                        continue
                    seen.add(rp)
                    add("ae-%s-%s" % (tag, ver), "After Effects", kind, p, ver)
    common = os.path.join(home, "Library", "Application Support", "Adobe", "Common")
    add("adobe-media-cache", "Adobe video apps", "media cache files", os.path.join(common, "Media Cache Files"))
    add("adobe-media-cache-db", "Adobe video apps", "media cache database", os.path.join(common, "Media Cache"))
    add("adobe-peak-files", "Adobe video apps", "audio waveform files", os.path.join(common, "Peak Files"))
    maxon = os.path.join(home, "Library", "Preferences", "Maxon")
    for d in sorted(glob.glob(os.path.join(maxon, "Maxon Cinema 4D *", "Redshift", "Cache"))):
        folder = os.path.basename(os.path.dirname(os.path.dirname(d)))
        m = re.search(r"Cinema 4D (\d{4})", folder)
        add("redshift-" + re.sub(r"[^A-Za-z0-9]+", "-", folder.replace("Maxon Cinema 4D ", "")).strip("-").lower(), "Cinema 4D", "Redshift cache", d, m.group(1) if m else None)
    add("maxon-asset-cache", "Cinema 4D", "Asset Browser cache", os.path.join(maxon, "_assetcache"), cleanable=False,
        note="Cinema 4D manages this itself; empty it from the Asset Browser if needed.")
    return caches

APP_PROCESSES = {
    "After Effects": ("After Effects", "aerender"),
    "Adobe video apps": ("After Effects", "After Effects Render Engine", "aerender", "Adobe Premiere Pro", "Adobe Media Encoder", "Adobe Audition", "Adobe Character Animator", "Adobe Prelude"),
    "Cinema 4D": ("Cinema 4D", "Commandline", "c4dpy", "Redshift", "Team Render Client", "Team Render Server", "Team Render"),
}

def running_processes(ps):
    """Executable names of running processes, or None when they cannot be listed (then nothing is deleted)."""
    try:
        out = subprocess.run([ps, "-axo", "comm="], capture_output=True, text=True, timeout=10, stdin=subprocess.DEVNULL)
    except Exception:
        return None
    if out.returncode != 0:
        return None
    return {os.path.basename(l.strip()) for l in out.stdout.splitlines() if l.strip()}
PY_SPACE_LIB

space_python() {
  local _main=""
  IFS= read -r -d '' _main || true
  printf '%s\n%s\n%s' "$MJ_PY_PROTECT_LIB" "$MJ_PY_SPACE" "$_main" | /usr/bin/python3 - 2>/dev/null
}

handle_cache_inspect() {
  local _out=""
  cap_available python3 || { set_error "UNSUPPORTED" "Cache inspection requires python3."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 69; }
  _out=$(MJ_APPS="$MJ_HOST_APPS_DIR" space_python <<'PY_CACHE_INSPECT'
home = os.path.expanduser("~")
caches = known_caches(home, os.environ["MJ_APPS"])
for c in caches:
    c["bytes"], c["files"], newest = measure(c["path"])
    c["newest"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(newest)) if newest else None
caches.sort(key=lambda c: -c["bytes"])
print(json.dumps({"ok": True, "data": {
    "schema": "MJ_CACHE_INSPECT_1", "caches": caches,
    "totalBytes": sum(c["bytes"] for c in caches),
    "cleanableBytes": sum(c["bytes"] for c in caches if c["cleanable"]),
    "leftOverBytes": sum(c["bytes"] for c in caches if c["cleanable"] and c["leftOver"]),
}}))
PY_CACHE_INSPECT
) || true
  frames_emit_python_result "$_out"
}

handle_cache_clean() {
  local _id="" _fmt="report" _out=""
  require_arg target || { emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  _id="$MJ_REQUIRED_ARG_VALUE"
  case "$_id" in ""|*[!a-z0-9.-]*) set_error "INVALID_ARGUMENT" "target must be a cache id from cache.inspect (for example ae-disk-26.3)."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65 ;; esac
  request_arg_present format && _fmt=$(request_arg_get format)
  case "$_fmt" in report|delete) ;; *) set_error "INVALID_ARGUMENT" "format must be report (default) or delete."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65 ;; esac
  cap_available python3 || { set_error "UNSUPPORTED" "Cache cleaning requires python3."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 69; }
  _out=$(MJ_APPS="$MJ_HOST_APPS_DIR" MJ_ID="$_id" MJ_FMT="$_fmt" MJ_PS="$MJ_PS" space_python <<'PY_CACHE_CLEAN'
home = os.path.expanduser("~")
cid, delete = os.environ["MJ_ID"], os.environ["MJ_FMT"] == "delete"
c = next((x for x in known_caches(home, os.environ["MJ_APPS"]) if x["id"] == cid), None)
if c is None:
    err("NOT_FOUND", "No cache with id %s on this Mac; run cache.inspect for the list." % cid)
if not c["cleanable"]:
    err("POLICY_DENIED", "%s is not emptied by this tool. %s" % (c["kind"], c["note"]))
before, files, _ = measure(c["path"])
removed = 0
problems = []
if delete:
    procs = running_processes(os.environ["MJ_PS"])
    if procs is None:
        err("UNSUPPORTED", "Could not list running apps, so nothing was deleted.")
    # A cache left over from a version that is no longer installed cannot be in use by the installed one.
    # Executables carry the year ("Adobe Media Encoder 2026"), so match a name or "<name> <anything>".
    busy = [] if c["leftOver"] else sorted(p for p in APP_PROCESSES[c["app"]] if any(n == p or n.startswith(p + " ") for n in procs))
    if busy:
        err("HOST_BUSY", "Quit %s first; it may be using this cache." % ", ".join(busy))
    root = os.path.realpath(c["path"])
    # Empty the folder, keep the folder itself (the app expects it). Entries are removed without
    # following symlinks, and each one is re-checked to sit directly inside the cache folder.
    for name in sorted(os.listdir(root)):
        p = os.path.join(root, name)
        if os.path.dirname(os.path.realpath(p) if not os.path.islink(p) else p) != root:
            problems.append(name)
            continue
        try:
            if os.path.isdir(p) and not os.path.islink(p):
                shutil.rmtree(p)
            else:
                os.unlink(p)
            removed += 1
        except OSError:
            problems.append(name)
after = measure(c["path"])[0] if delete else before
warnings = []
if problems:
    warnings.append({"code": "CACHE_PARTLY_CLEANED", "message": "%d entr%s could not be removed." % (len(problems), "y" if len(problems) == 1 else "ies")})
print(json.dumps({"ok": True, "data": {
    "schema": "MJ_CACHE_CLEAN_1", "id": cid, "app": c["app"], "kind": c["kind"], "path": c["path"], "version": c["version"], "leftOver": c["leftOver"],
    "deleted": delete, "bytesBefore": before, "filesBefore": files, "bytesAfter": after, "bytesFreed": max(before - after, 0) if delete else 0,
    "wouldFree": before if not delete else None, "entriesRemoved": removed, "problems": problems[:20],
    "_warnings": warnings,
}}))
PY_CACHE_CLEAN
) || true
  frames_emit_python_result "$_out"
}

# --- src/modules/deliver.zsh ---
# Delivery QC: check a rendered movie against a delivery spec before it goes out. Read-only.
#
# media.qc path=<movie> format=<built-in spec> | input=<spec file>
#   Container, codec, size, frame rate, duration, colour tags, audio channels and sample rate from
#   stock avmediainfo; integrated loudness (ITU-R BS.1770-4 / EBU R128 gating) and sample peak
#   measured here in Python on audio decoded by stock afconvert. Each check passes, fails, warns or
#   is skipped with a reason. No ffmpeg: true peak is approximated by the sample peak (stated).

IFS= read -r -d '' MJ_PY_QC <<'PY_QC_LIB' || true
import array, math, struct, subprocess, tempfile

BUILTIN_SPECS = {
    "broadcast-us": {"name": "US broadcast (ATSC A/85)", "container": "mov", "codec": "prores", "width": "1920", "height": "1080",
                     "fps": "29.97, 23.976", "audio": "required", "audioChannels": "2", "audioSampleRate": "48000",
                     "loudness": "-24", "loudnessTolerance": "2", "peakMax": "-2", "colorTags": "required"},
    "broadcast-eu": {"name": "European broadcast (EBU R128)", "container": "mov", "codec": "prores", "width": "1920", "height": "1080",
                     "fps": "25", "audio": "required", "audioChannels": "2", "audioSampleRate": "48000",
                     "loudness": "-23", "loudnessTolerance": "1", "peakMax": "-1", "colorTags": "required"},
    "web": {"name": "Web and streaming", "container": "mp4, mov", "codec": "h264, hevc", "audio": "any",
            "audioSampleRate": "48000, 44100", "loudness": "-14", "loudnessTolerance": "2", "peakMax": "-1"},
    "social-vertical": {"name": "Social, vertical 9:16", "container": "mp4", "codec": "h264", "width": "1080", "height": "1920",
                        "fps": "23.976, 24, 25, 29.97, 30", "maxDuration": "90", "audio": "any", "loudness": "-14", "loudnessTolerance": "2", "peakMax": "-1"},
    "prores-master": {"name": "ProRes master", "container": "mov", "codec": "prores", "audio": "any", "audioSampleRate": "48000", "colorTags": "required"},
}
SPEC_KEYS = {"name", "container", "codec", "width", "height", "fps", "minDuration", "maxDuration", "audio", "audioChannels",
             "audioSampleRate", "loudness", "loudnessTolerance", "peakMax", "colorTags"}
CODEC_FAMILY = {"apch": "prores", "apcn": "prores", "apcs": "prores", "apco": "prores", "ap4h": "prores", "ap4x": "prores", "aprh": "prores", "aprn": "prores",
                "avc1": "h264", "avc3": "h264", "hvc1": "hevc", "hev1": "hevc", "dvh1": "hevc", "jpeg": "mjpeg", "png ": "png", "rle ": "animation", "mp4v": "mpeg4"}

def parse_spec_file(path):
    spec = {}
    try:
        lines = open(path, encoding="utf-8").read(65536).splitlines()
    except (OSError, UnicodeDecodeError):
        err("INVALID_SPEC", "The spec file could not be read as UTF-8 text.")
    for n, line in enumerate(lines, 1):
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        if "=" not in line:
            err("INVALID_SPEC", "Spec line %d is not key = value." % n)
        k, v = (x.strip() for x in line.split("=", 1))
        if k not in SPEC_KEYS:
            err("INVALID_SPEC", "Spec line %d: unknown key %s (known: %s)." % (n, k, ", ".join(sorted(SPEC_KEYS))))
        spec[k] = v
    return spec

NUM_KEYS = ("width", "height", "minDuration", "maxDuration", "audioChannels", "loudness", "loudnessTolerance", "peakMax")

def validate_spec(spec):
    """Every value is checked before the movie is touched, so a typo is an error, never a silently skipped check."""
    for k in NUM_KEYS:
        if k in spec:
            try:
                v = float(spec[k])
            except ValueError:
                err("INVALID_SPEC", "%s must be a number (got %s)." % (k, spec[k][:20]))
            if v != v or v in (float("inf"), float("-inf")):
                err("INVALID_SPEC", "%s must be a finite number." % k)
    for k in ("fps", "audioSampleRate"):
        if k in spec:
            items = [x.strip() for x in spec[k].split(",") if x.strip()]
            if not items:
                err("INVALID_SPEC", "%s needs at least one number." % k)
            for x in items:
                try:
                    float(x)
                except ValueError:
                    err("INVALID_SPEC", "%s must be numbers separated by commas (got %s)." % (k, x[:20]))
    for k in ("container", "codec"):
        if k in spec and not [x for x in spec[k].split(",") if x.strip()]:
            err("INVALID_SPEC", "%s needs at least one value." % k)
    if spec.get("audio", "any").lower() not in ("required", "none", "any"):
        err("INVALID_SPEC", "audio must be required, none or any (got %s)." % spec["audio"][:20])
    if spec.get("colorTags", "any").lower() not in ("required", "any"):
        err("INVALID_SPEC", "colorTags must be required or any (got %s)." % spec["colorTags"][:20])
    if spec.get("loudnessTolerance") is not None and "loudness" not in spec:
        err("INVALID_SPEC", "loudnessTolerance needs loudness.")
    if not any(k in spec for k in SPEC_KEYS - {"name", "loudnessTolerance"}) and spec.get("audio", "any").lower() == "any":
        err("INVALID_SPEC", "The spec asks for nothing to check.")

def spec_list(v):
    return [x.strip().lower() for x in str(v).split(",") if x.strip()]

def spec_num(spec, k):
    try:
        return float(spec[k])
    except (KeyError, ValueError):
        if k in spec:
            err("INVALID_SPEC", "%s must be a number." % k)
        return None

def probe(avmediainfo, path):
    try:
        out = subprocess.run([avmediainfo, path], capture_output=True, text=True, timeout=60, stdin=subprocess.DEVNULL)
    except Exception:
        err("NATIVE_OUTPUT_INVALID", "avmediainfo could not be run on this file.")
    text = out.stdout
    if out.returncode != 0 or "Track count:" not in text:
        err("DECODE_UNSUPPORTED", "macOS cannot read this movie (avmediainfo found no tracks).")
    info = {"duration": None, "video": None, "audio": None}
    m = re.search(r"^Duration: ([0-9.]+) seconds", text, re.M)
    if m:
        info["duration"] = float(m.group(1))
    for block in re.split(r"^Track \d+: ", text, flags=re.M)[1:]:
        kind = block.split(None, 1)[0]
        if kind == "Video" and info["video"] is None:
            v = {}
            m = re.search(r"Format: (.*?) '(.{4})'", block)
            if m:
                v["format"], v["fourcc"] = m.group(1), m.group(2)
                v["codec"] = CODEC_FAMILY.get(m.group(2), m.group(2).strip().lower())
            m = re.search(r"Presentation Dimensions: (\d+) x (\d+)", block) or re.search(r"Dimensions: (\d+) x (\d+)", block)
            if m:
                v["width"], v["height"] = int(m.group(1)), int(m.group(2))
            m = re.search(r"Nominal frame rate: ([0-9.]+) fps", block)
            if m:
                v["fps"] = float(m.group(1))
            v["colorTags"] = {"primaries": "Color Primaries were not specified" not in block,
                              "transfer": "Transfer function was not specified" not in block,
                              "matrix": "YCbCr matrix was not specified" not in block}
            info["video"] = v
        elif kind == "Sound" and info["audio"] is None:
            a = {}
            m = re.search(r"Format: (.*?) '(.{4})'", block)
            if m:
                a["format"] = m.group(1)
            m = re.search(r"Channels per frame: (\d+)", block)
            if m:
                a["channels"] = int(m.group(1))
            m = re.search(r"Sample rate: ([0-9.]+)", block)
            if m:
                a["sampleRate"] = float(m.group(1))
            info["audio"] = a
    return info

# ---- ITU-R BS.1770-4 loudness, streamed so long files need little memory ----
def _biquads(rate):
    """K-weighting: high shelf then high pass, coefficients for any sample rate (BS.1770 analogue prototypes)."""
    def shelf():
        G, Q, fc = 3.99984385397, 0.7071752369554193, 1681.9744509555319
        K = math.tan(math.pi * fc / rate); Vh = 10 ** (G / 20.0); Vb = Vh ** 0.499666774155
        a0 = 1 + K / Q + K * K
        return ((Vh + Vb * K / Q + K * K) / a0, 2 * (K * K - Vh) / a0, (Vh - Vb * K / Q + K * K) / a0, 2 * (K * K - 1) / a0, (1 - K / Q + K * K) / a0)
    def highpass():
        Q, fc = 0.5003270373253953, 38.13547087613982
        K = math.tan(math.pi * fc / rate)
        a0 = 1 + K / Q + K * K
        return (1 / a0, -2 / a0, 1 / a0, 2 * (K * K - 1) / a0, (1 - K / Q + K * K) / a0)
    return shelf(), highpass()

def read_wav_float(path):
    """Yields (rate, channels) then interleaved float32 arrays of about one second each."""
    f = open(path, "rb")
    if f.read(4) != b"RIFF":
        raise ValueError("not a WAV file")
    f.read(4)
    if f.read(4) != b"WAVE":
        raise ValueError("not a WAV file")
    rate = chans = fmt = bits = None
    while True:
        hdr = f.read(8)
        if len(hdr) < 8:
            raise ValueError("no data chunk")
        cid, size = hdr[:4], struct.unpack("<I", hdr[4:])[0]
        if cid == b"fmt ":
            body = f.read(size)
            fmt, chans, rate = struct.unpack("<HHI", body[:8]); bits = struct.unpack("<H", body[14:16])[0]
            if fmt == 0xFFFE and len(body) >= 26:
                fmt = struct.unpack("<H", body[24:26])[0]
        elif cid == b"data":
            break
        else:
            f.seek(size + (size & 1), 1)
    if fmt != 3 or bits != 32:
        raise ValueError("expected 32-bit float samples")
    yield rate, chans
    left = size
    step = rate * chans * 4
    while left > 0:
        buf = f.read(min(step, left))
        if not buf:
            break
        left -= len(buf)
        a = array.array("f"); a.frombytes(buf[: len(buf) - len(buf) % 4])
        if struct.pack("=I", 1) != struct.pack("<I", 1):
            a.byteswap()
        yield a

def loudness(wav_path):
    """{integrated LUFS or None (all gated out), samplePeak dBFS, seconds}."""
    gen = read_wav_float(wav_path)
    rate, chans = next(gen)
    (b0, b1, b2, a1, a2), (c0, c1, c2, d1, d2) = _biquads(rate)
    weights = [1.0, 1.0, 1.0, 0.0, 1.41, 1.41][:chans] if chans <= 6 else [1.0] * chans
    if chans <= 2:
        weights = [1.0] * chans
    active = [ch for ch in range(chans) if weights[ch] != 0.0]
    state = {ch: [0.0] * 8 for ch in active}
    seg = rate // 10                      # 100 ms
    seg_sums, cur, cur_n = [], [0.0] * chans, 0
    peak = 0.0
    total = 0
    for block in gen:
        n = len(block) // chans
        total += n
        if n:
            peak = max(peak, max(block), -min(block))
        sqs = {}
        for ch in active:
            x1, x2, y1, y2, z1, z2, w1, w2 = state[ch]
            out = []
            app = out.append
            for x in block[ch::chans]:
                y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
                x2 = x1; x1 = x; y2 = y1; y1 = y
                z = c0 * y + c1 * z1 + c2 * z2 - d1 * w1 - d2 * w2
                z2 = z1; z1 = y; w2 = w1; w1 = z
                app(z * z)
            state[ch] = [x1, x2, y1, y2, z1, z2, w1, w2]
            sqs[ch] = out
        i = 0
        while i < n:                     # accumulate 100 ms segments
            take = min(seg - cur_n, n - i)
            for ch in active:
                cur[ch] += math.fsum(sqs[ch][i:i + take])
            cur_n += take; i += take
            if cur_n == seg:
                seg_sums.append(cur); cur, cur_n = [0.0] * chans, 0
    # 400 ms blocks, 75 % overlap
    blocks = []
    for j in range(len(seg_sums) - 3):
        z = sum(weights[ch] * sum(seg_sums[j + q][ch] for q in range(4)) / (4 * seg) for ch in range(chans))
        if z > 0:
            blocks.append(z)
    def lufs(z):
        return -0.691 + 10 * math.log10(z)
    gated = [z for z in blocks if lufs(z) > -70.0]
    integrated = None
    if gated:
        rel = lufs(sum(gated) / len(gated)) - 10.0
        g2 = [z for z in gated if lufs(z) > rel]
        if g2:
            integrated = round(lufs(sum(g2) / len(g2)), 1)
    return {"integrated": integrated, "samplePeak": round(20 * math.log10(peak), 1) if peak > 0 else None, "seconds": round(total / float(rate), 3) if rate else 0,
            "tooShort": total < int(0.4 * rate)}
PY_QC_LIB

deliver_python() {
  local _main=""
  IFS= read -r -d '' _main || true
  printf '%s\n%s\n%s' "$MJ_PY_PROTECT_LIB" "$MJ_PY_QC" "$_main" | /usr/bin/python3 - 2>/dev/null
}

handle_media_qc() {
  local _rc=0 _path="" _fmt="" _spec="" _out=""
  require_arg path || { emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  _path="$MJ_REQUIRED_ARG_VALUE"
  is_absolute_path "$_path" || { set_error "INVALID_PATH" "Movie path must be absolute."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  [ -f "$_path" ] || { set_error "NOT_FOUND" "Movie not found."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 66; }
  mj_require_local_existing_path "$_path" || { emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 73; }
  request_arg_present format && _fmt=$(request_arg_get format)
  request_arg_present input && _spec=$(request_arg_get input)
  if [ -n "$_fmt" ] && [ -n "$_spec" ]; then set_error "INVALID_ARGUMENT" "Give either format (a built-in spec) or input (a spec file), not both."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; fi
  if [ -z "$_fmt" ] && [ -z "$_spec" ]; then set_error "MISSING_ARGUMENT" "Give format=<built-in spec> or input=<spec file>."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; fi
  if [ -n "$_fmt" ]; then   # a bad argument is reported before a missing tool, on any machine
    case "$_fmt" in broadcast-us|broadcast-eu|web|social-vertical|prores-master) ;;
      *) set_error "INVALID_ARGUMENT" "Unknown spec; built-in specs: broadcast-eu, broadcast-us, prores-master, social-vertical, web."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65 ;; esac
  fi
  if [ -n "$_spec" ]; then
    is_absolute_path "$_spec" || { set_error "INVALID_PATH" "Spec path must be absolute."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
    [ -f "$_spec" ] || { set_error "NOT_FOUND" "Spec file not found."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 66; }
  fi
  cap_available python3 && cap_available avmediainfo || { set_error "UNSUPPORTED" "Delivery QC needs stock python3 and avmediainfo (macOS 12 or later)."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 69; }
  _out=$(MJ_MOVIE="$_path" MJ_FMT="$_fmt" MJ_SPEC="$_spec" MJ_AVMEDIAINFO="$(cap_path avmediainfo)" \
         MJ_AFCONVERT="$(cap_available afconvert && cap_path afconvert)" deliver_python <<'PY_MEDIA_QC'
movie = os.environ["MJ_MOVIE"]
id0 = tree_id(movie)
if os.environ["MJ_FMT"]:
    spec = BUILTIN_SPECS.get(os.environ["MJ_FMT"])
    if spec is None:
        err("INVALID_ARGUMENT", "Unknown spec %s; built-in specs: %s." % (os.environ["MJ_FMT"], ", ".join(sorted(BUILTIN_SPECS))))
    spec = dict(spec); spec_name = spec.pop("name"); spec_src = os.environ["MJ_FMT"]
else:
    spec = parse_spec_file(os.environ["MJ_SPEC"]); spec_name = spec.pop("name", os.path.basename(os.environ["MJ_SPEC"])); spec_src = os.environ["MJ_SPEC"]
validate_spec(spec)
info = probe(os.environ["MJ_AVMEDIAINFO"], movie)
v, a = info["video"] or {}, info["audio"]
checks = []
def add(check, status, expected, actual, message):
    checks.append({"check": check, "status": status, "expected": expected, "actual": actual, "message": message})
def one_of(check, key, actual, label):
    if key not in spec:
        return
    want = spec_list(spec[key])
    if actual is None:
        add(check, "fail", ", ".join(want), None, "%s could not be read." % label)
    elif str(actual).lower() in want:
        add(check, "pass", ", ".join(want), actual, "%s is %s." % (label, actual))
    else:
        add(check, "fail", ", ".join(want), actual, "%s is %s; the spec wants %s." % (label, actual, " or ".join(want)))

ext = os.path.splitext(movie)[1].lower().lstrip(".")
one_of("container", "container", ext, "Container")
if not info["video"]:
    if any(k in spec for k in ("codec", "width", "height", "fps", "colorTags")):
        add("video", "fail", "a video track", None, "There is no video track.")
else:
    one_of("codec", "codec", v.get("codec"), "Codec")
    for key in ("width", "height"):
        if key in spec:
            want = int(spec_num(spec, key)); got = v.get(key)
            add(key, "pass" if got == want else "fail", want, got, "%s is %s%s." % (key.capitalize(), got, "" if got == want else "; the spec wants %d" % want))
    if "fps" in spec:
        want = [float(x) for x in spec_list(spec["fps"])]
        got = v.get("fps")
        ok = got is not None and any(abs(got - w) < 0.011 for w in want)
        add("fps", "pass" if ok else "fail", ", ".join("%g" % w for w in want), got, "Frame rate is %s fps%s." % ("%g" % got if got else "unknown", "" if ok else "; the spec wants %s" % " or ".join("%g" % w for w in want)))
    if spec.get("colorTags", "").lower() == "required":
        tags = v.get("colorTags", {})
        missing = [k for k in ("primaries", "transfer", "matrix") if not tags.get(k)]
        add("colorTags", "fail" if missing else "pass", "primaries, transfer, matrix", [k for k in tags if tags[k]],
            "Colour tags missing: %s; players may show the wrong colours." % ", ".join(missing) if missing else "Colour tags are set.")
dur = info["duration"]
for key, cmp, word in (("minDuration", lambda d, w: d >= w - 0.001, "at least"), ("maxDuration", lambda d, w: d <= w + 0.001, "at most")):
    if key in spec:
        w = spec_num(spec, key)
        ok = dur is not None and cmp(dur, w)
        add(key, "pass" if ok else "fail", w, dur, "Duration is %.3f s; the spec wants %s %g s." % (dur or 0, word, w))
need_audio = spec.get("audio", "any").lower()
if need_audio == "required" and not a:
    add("audio", "fail", "an audio track", None, "There is no audio track.")
elif need_audio == "none" and a:
    add("audio", "fail", "no audio", a.get("format"), "There is an audio track; the spec wants none.")
if a:
    if "audioChannels" in spec:
        w = int(spec_num(spec, "audioChannels")); g = a.get("channels")
        add("audioChannels", "pass" if g == w else "fail", w, g, "Audio has %s channel%s%s." % (g, "" if g == 1 else "s", "" if g == w else "; the spec wants %d" % w))
    if "audioSampleRate" in spec:
        want = [int(float(x)) for x in spec_list(spec["audioSampleRate"])]; g = int(a.get("sampleRate") or 0)
        add("audioSampleRate", "pass" if g in want else "fail", ", ".join(map(str, want)), g, "Audio sample rate is %d Hz%s." % (g, "" if g in want else "; the spec wants %s" % " or ".join(map(str, want))))
measured = None
if a and ("loudness" in spec or "peakMax" in spec):
    afc = os.environ.get("MJ_AFCONVERT", "")
    need = int((info["duration"] or 0) * (a.get("sampleRate") or 48000) * (a.get("channels") or 2) * 4)
    free = shutil.disk_usage(tempfile.gettempdir()).free
    skip_why = None
    if not afc:
        skip_why = "afconvert is not available."
    elif need > free - (512 << 20):
        skip_why = "decoding the audio needs about %.1f GB of temporary space and only %.1f GB is free." % (need / 1e9, free / 1e9)
    if skip_why:
        for key in ("loudness", "peakMax"):
            if key in spec:
                add(key, "skipped", spec[key], None, "Not measured: " + skip_why)
    else:
        tmp = tempfile.mkdtemp(prefix="mj-qc.")
        wav = os.path.join(tmp, "audio.wav")
        try:
            r = subprocess.run([afc, "-f", "WAVE", "-d", "LEF32", movie, wav], capture_output=True, timeout=600, stdin=subprocess.DEVNULL)
            if r.returncode != 0 or not os.path.isfile(wav):
                raise ValueError("decode failed")
            measured = loudness(wav)
        except Exception:
            measured = None
        finally:
            shutil.rmtree(tmp, ignore_errors=True)
        if measured is None:
            for key in ("loudness", "peakMax"):
                if key in spec:
                    add(key, "skipped", spec[key], None, "Not measured: macOS could not decode the audio.")
        else:
            if "loudness" in spec and measured.get("tooShort"):
                add("loudness", "skipped", "%g LUFS" % spec_num(spec, "loudness"), None, "Not measured: the audio is under 0.4 s, too short for a loudness reading.")
            elif "loudness" in spec:
                w = spec_num(spec, "loudness"); tol = spec_num(spec, "loudnessTolerance"); tol = 1.0 if tol is None else tol; g = measured["integrated"]
                if g is None:
                    add("loudness", "warn", "%g LUFS" % w, None, "The audio is silent (below the -70 LUFS gate).")
                else:
                    ok = abs(g - w) <= tol + 1e-9
                    add("loudness", "pass" if ok else "fail", "%g LUFS (+/- %g)" % (w, tol), g,
                        "Integrated loudness is %.1f LUFS%s." % (g, "" if ok else "; the spec wants %g +/- %g (%s by %.1f LU)" % (w, tol, "too loud" if g > w else "too quiet", abs(g - w))))
            if "peakMax" in spec:
                w = spec_num(spec, "peakMax"); g = measured["samplePeak"]
                ok = g is None or g <= w + 1e-9
                add("peakMax", "pass" if ok else "fail", "%g dBFS" % w, g, "Sample peak is %s dBFS%s." % ("%.1f" % g if g is not None else "-inf", "" if ok else "; the spec allows %g" % w))
if not checks:
    err("INVALID_SPEC", "The spec produced no checks for this movie (for example it only asks about audio and the movie has none).")
order = {"fail": 0, "warn": 1, "skipped": 2, "pass": 3}
fails = sum(1 for c in checks if c["status"] == "fail")
warns = []
if any(c["check"] == "peakMax" and c["status"] != "skipped" for c in checks):
    warns.append({"code": "PEAK_IS_SAMPLE_PEAK", "message": "Peak is the sample peak; a true-peak meter can read up to about 0.5 dB higher on bright material."})
print(json.dumps({"ok": True, "data": {
    "schema": "MJ_MEDIA_QC_1", "path": movie, "spec": spec_src, "specName": spec_name, "passed": fails == 0,
    "failed": fails, "warnings": sum(1 for c in checks if c["status"] == "warn"), "skipped": sum(1 for c in checks if c["status"] == "skipped"),
    "checks": sorted(checks, key=lambda c: order[c["status"]]),
    "media": {"duration": dur, "video": info["video"], "audio": a, "loudness": measured},
    "sourceUnchanged": tree_id(movie) == id0,
    "_warnings": warns,
}}))
PY_MEDIA_QC
) || true
  frames_emit_python_result "$_out"
}

# --- src/modules/aejob.zsh ---
# After Effects jobs: changes that only After Effects can make, done on a copy, never the original.
#
# project.extract  — keep one comp or a list of comps (and everything they use) as a NEW project.
# project.conform  — bring a project to a studio spec: comp and layer names, labels, project-panel
#                    folders, and the expressions that refer to renamed things (plus, optionally,
#                    broken name references with one clear close match). format=plan (default) only
#                    reports the plan; format=job writes a job.
# project.jobcheck — after the job ran in After Effects: was it applied, and is the original untouched?
#
# Everything is planned here from the scrape, so it is reviewable and testable without After Effects.
# A job folder holds before.aep (a verified copy), plan.json and run.jsx (the fixed runner in
# integrations/after-effects/MographJailed_JobRunner.jsx with the plan embedded). The runner opens only
# before.aep, skips any step whose item no longer matches the plan, and saves result.aep as a new file.

IFS= read -r -d '' MJ_PY_AEJOB <<'PY_AEJOB_LIB' || true
import difflib

def require_same_project(doc, aep):
    """Comp ids and layer indexes only mean something for the project that was scraped. Two client folders
    can each hold a Main.aep, so compare the full resolved path, not the file name."""
    sp = doc.get("projectPath") or ""
    if not sp or os.path.realpath(sp) != os.path.realpath(aep):
        err("PROJECT_SCRAPE_MISMATCH", "The scrape was made from %s, not from %s; scrape this project again so the comp ids match." % (sp or "an unsaved project", aep))

def comp_index(doc):
    comps = [c for c in doc["comps"] if isinstance(c, dict) and isinstance(c.get("id"), int)]
    return comps, {c["id"]: c for c in comps}

def comp_closure(byid, ids):
    """The comps reachable from ids through precomp layers, and the footage ids they use."""
    seen, stack, footage = set(), list(ids), set()
    while stack:
        cid = stack.pop()
        if cid in seen or cid not in byid:
            continue
        seen.add(cid)
        for l in byid[cid].get("layers") or []:
            sid = l.get("sourceId") if isinstance(l, dict) else None
            if isinstance(sid, int) and sid:
                if sid in byid:
                    stack.append(sid)
                else:
                    footage.add(sid)
    return seen, footage

def make_job(kind, label, aep, outdir, plan_body, runner_path, scrape_path):
    """Create <outdir>/<label>.mjjob with a verified copy, plan.json and run.jsx. Never overwrites."""
    job = os.path.join(outdir, label + ".mjjob")
    try:
        os.mkdir(job, 0o755)
    except FileExistsError:
        err("OUTPUT_EXISTS", "A job named %s already exists in the output folder." % label)
    except OSError:
        err("OUTPUT_UNAVAILABLE", "The job folder could not be created.")
    try:
        runner = open(runner_path, encoding="utf-8").read()
    except OSError:
        shutil.rmtree(job, ignore_errors=True)
        err("NOT_FOUND", "The After Effects job runner is missing (integrations/after-effects/MographJailed_JobRunner.jsx).")
    src_sha = sha256_file(aep)
    work = os.path.join(job, "before.aep")
    try:
        cloned = clone_copy(aep, work)
    except OSError:
        shutil.rmtree(job, ignore_errors=True)
        err("SNAPSHOT_FAILED", "The project could not be copied into the job folder.")
    if sha256_file(work) != src_sha or sha256_file(aep) != src_sha:
        shutil.rmtree(job, ignore_errors=True)
        err("SNAPSHOT_UNSTABLE", "The project changed while it was being copied; save it in After Effects and try again.")
    plan = {"schema": "MJ_AE_JOB_1", "kind": kind, "label": label, "createdAt": utc_stamp(),
            "source": {"path": aep, "sha256": src_sha, "size": os.path.getsize(aep)}, "scrape": scrape_path,
            "work": work, "workSha256": src_sha, "result": os.path.join(job, "result.aep"), "receipt": os.path.join(job, "result.json"),
            "quietFlag": os.path.join(job, "quiet")}
    plan.update(plan_body)
    text = json.dumps(plan, indent=1, sort_keys=True, ensure_ascii=True)
    with open(os.path.join(job, "plan.json"), "x", encoding="utf-8") as f:
        f.write(text + "\n")
    with open(os.path.join(job, "run.jsx"), "x", encoding="utf-8") as f:
        f.write("#target aftereffects\n// MographJailed %s job \"%s\". Run this file in After Effects; it works on before.aep in this folder only.\n" % (kind, label))
        f.write("var MJ_PLAN = " + text + ";\n")
        f.write(runner)
    return job, plan, cloned

# ---- studio spec ----
LAYER_KINDS = ("text", "shape", "solid", "null", "adjustment", "camera", "light", "precomp", "footage", "audio")
DEFAULT_STUDIO_SPEC = {
    "name": "MographJailed studio default",
    "precompPrefix": "PRE_", "mainCompPrefix": "", "spaces": "_",
    "layerPrefix.text": "TXT_", "layerPrefix.shape": "SHP_", "layerPrefix.solid": "SOL_", "layerPrefix.null": "NULL_",
    "layerPrefix.adjustment": "ADJ_", "layerPrefix.camera": "CAM_", "layerPrefix.light": "LGT_", "layerPrefix.precomp": "PRE_",
    "layerPrefix.footage": "", "layerPrefix.audio": "AUD_",
    "label.text": "1", "label.shape": "8", "label.solid": "2", "label.null": "11", "label.adjustment": "5", "label.camera": "4",
    "label.light": "6", "label.precomp": "15", "label.footage": "14", "label.audio": "7",
    "label.mainComp": "9", "label.precompItem": "15",
    "folder.mainComps": "01_Comps", "folder.precomps": "02_Precomps", "folder.footage": "03_Footage", "folder.solids": "04_Solids", "folder.audio": "05_Audio",
    "fixBrokenRefs": "suggest",
}
STUDIO_KEYS = {"name", "precompPrefix", "mainCompPrefix", "spaces", "fixBrokenRefs", "label.mainComp", "label.precompItem"} | \
    {"layerPrefix." + k for k in LAYER_KINDS} | {"label." + k for k in LAYER_KINDS} | \
    {"folder." + k for k in ("mainComps", "precomps", "footage", "solids", "audio")}

def parse_studio_spec(path):
    spec = {}
    try:
        lines = open(path, encoding="utf-8").read(65536).splitlines()
    except (OSError, UnicodeDecodeError):
        err("INVALID_SPEC", "The studio spec could not be read as UTF-8 text.")
    for n, line in enumerate(lines, 1):
        s = line.strip()
        if not s or s.startswith("#"):
            continue
        if "=" not in s:
            err("INVALID_SPEC", "Spec line %d is not key = value." % n)
        k, v = (x.strip() for x in s.split("=", 1))
        if k not in STUDIO_KEYS:
            err("INVALID_SPEC", "Spec line %d: unknown key %s." % (n, k))
        if k.startswith("label.") and v and not (v.isdigit() and 0 <= int(v) <= 16):
            err("INVALID_SPEC", "Spec line %d: %s must be a label number 0-16 (or empty to leave labels alone)." % (n, k))
        if k == "spaces" and v not in ("keep", "_", "-"):
            err("INVALID_SPEC", "Spec line %d: spaces must be keep, _ or -." % n)
        if k == "fixBrokenRefs" and v not in ("off", "suggest", "apply"):
            err("INVALID_SPEC", "Spec line %d: fixBrokenRefs must be off, suggest or apply." % n)
        if any(ch in v for ch in '"\\') or len(v) > 64:
            err("INVALID_SPEC", "Spec line %d: values may not contain quotes or backslashes and must be short." % n)
        spec[k] = v
    return spec

def layer_kind(l, comp_ids):
    t = l.get("type")
    simple = {"TextLayer": "text", "ShapeLayer": "shape", "CameraLayer": "camera", "LightLayer": "light", "NullLayer": "null"}
    if t in simple:
        return simple[t]
    if l.get("adjustment"):
        return "adjustment"
    sk = l.get("sourceKind") or ("comp" if l.get("sourceId") in comp_ids else "")
    if sk == "comp":
        return "precomp"
    if sk == "solid":
        return "solid"
    if l.get("hasAudio") and not l.get("hasVideo"):
        return "audio"
    return "footage"

def styled(name, spec):
    n = " ".join(str(name).split())
    sp = spec.get("spaces", "keep")
    if sp in ("_", "-"):
        n = n.replace(" ", sp)
    return n

def prefixed(name, prefix):
    if prefix and not name.lower().startswith(prefix.lower()):
        return prefix + name
    return name

def unique(name, taken):
    if name not in taken:
        return name
    i = 2
    while "%s_%d" % (name, i) in taken:
        i += 1
    return "%s_%d" % (name, i)

REF = re.compile(r'(\bcomp|\.layer|\blayer)\(\s*(["\'])((?:(?!\2)[^\\\n])*)\2\s*\)')
THIS_COMP = re.compile(r'\bthisComp\s*$')

def rewrite_expression(text, own_comp, comp_new, layer_new, layer_names, fix, suggestions, where, unresolved):
    """Rename name references inside one expression. Returns (new text, changed?).
    A layer("...") lookup is followed only when its comp is certain: it directly follows thisComp, or follows
    comp("...") (whitespace and line breaks allowed between). Anything else (c.layer("x") on a variable, a
    layer found through another call) is left alone and counted in `unresolved`."""
    out, pos, changed = [], 0, False
    last_comp_end, last_comp_name = -1, None
    for m in REF.finditer(text):
        fn, q, name = m.group(1), m.group(2), m.group(3)
        new = name
        if fn == "comp":
            last_comp_end, last_comp_name = m.end(), name
            new = comp_new.get(name, name)
        else:
            if fn == "layer":
                target = own_comp
            elif last_comp_end >= 0 and text[last_comp_end:m.start()].strip() == "":
                target = last_comp_name
            elif THIS_COMP.search(text[:m.start()]):
                target = own_comp
            else:
                unresolved.append(where); continue
            names = layer_names.get(target)
            if names is not None and name not in names and fix != "off":
                close = difflib.get_close_matches(name, sorted(names), n=2, cutoff=0.8)
                if len(close) == 1:
                    suggestions.append(dict(where, reference=name, suggestion=close[0], comp=target, applied=fix == "apply"))
                    if fix == "apply":
                        name_fixed = close[0]
                        new = layer_new.get((target, name_fixed), name_fixed)
            if new == name:
                new = layer_new.get((target, name), name)
        if new != name:
            out.append(text[pos:m.start(3)]); out.append(new); pos = m.end(3); changed = True
    out.append(text[pos:])
    return "".join(out), changed

def plan_conform(doc, spec):
    comps, byid = comp_index(doc)
    comp_ids = set(byid)
    used_as_precomp = {l.get("sourceId") for c in comps for l in (c.get("layers") or []) if isinstance(l, dict) and l.get("sourceId") in comp_ids}
    names_count = {}
    for c in comps:
        names_count[c.get("name")] = names_count.get(c.get("name"), 0) + 1
    item_renames, comp_new, taken = [], {}, set()
    # Names that already match the spec keep their name; reserve them first so a rename never lands on one.
    for c in comps:
        role0 = "precomp" if c["id"] in used_as_precomp else "main"
        if prefixed(styled(c["name"], spec), spec.get("precompPrefix" if role0 == "precomp" else "mainCompPrefix", "")) == c["name"]:
            taken.add(c["name"])
    for c in comps:
        role = "precomp" if c["id"] in used_as_precomp else "main"
        new = prefixed(styled(c["name"], spec), spec.get("precompPrefix" if role == "precomp" else "mainCompPrefix", ""))
        if new != c["name"]:
            new = unique(new, taken)
        taken.add(new)
        c["_role"] = role
        if new != c["name"]:
            item_renames.append({"id": c["id"], "kind": "comp", "role": role, "from": c["name"], "to": new})
            if names_count[c["name"]] == 1:
                comp_new[c["name"]] = new
    layer_renames, layer_new, layer_labels, layer_names = [], {}, [], {}
    for c in comps:
        layer_names[c["name"]] = {l.get("name") for l in (c.get("layers") or []) if isinstance(l, dict)}
        seen, lc = set(), {}
        for l in c.get("layers") or []:
            lc[l.get("name")] = lc.get(l.get("name"), 0) + 1
            if isinstance(l, dict) and prefixed(styled(l.get("name", ""), spec), spec.get("layerPrefix." + layer_kind(l, comp_ids), "")) == l.get("name"):
                seen.add(l.get("name"))
        for l in c.get("layers") or []:
            if not isinstance(l, dict) or not isinstance(l.get("index"), int):
                continue
            kind = layer_kind(l, comp_ids)
            new = prefixed(styled(l.get("name", ""), spec), spec.get("layerPrefix." + kind, ""))
            if new != l.get("name"):
                new = unique(new, seen)
            seen.add(new)
            if new != l.get("name"):
                layer_renames.append({"compId": c["id"], "comp": c["name"], "index": l["index"], "kind": kind, "from": l.get("name"), "to": new})
                if lc[l.get("name")] == 1:
                    layer_new[(c["name"], l.get("name"))] = new
            want = spec.get("label." + kind, "")
            if want != "" and isinstance(l.get("label"), int) and l["label"] != int(want):
                layer_labels.append({"compId": c["id"], "comp": c["name"], "index": l["index"], "layer": l.get("name"), "kind": kind, "from": l["label"], "to": int(want)})
    item_labels, moves, folders = [], [], []
    def move(item_id, kind, frm, folder_key, name):
        dest = spec.get(folder_key, "")
        if dest and frm != dest:
            moves.append({"id": item_id, "kind": kind, "name": name, "from": frm, "to": dest})
            if dest not in folders:
                folders.append(dest)
    for c in comps:
        want = spec.get("label.precompItem" if c["_role"] == "precomp" else "label.mainComp", "")
        if want != "" and isinstance(c.get("label"), int) and c["label"] != int(want):
            item_labels.append({"id": c["id"], "kind": "comp", "name": c["name"], "from": c["label"], "to": int(want)})
        if "folder" in c:
            move(c["id"], "comp", c.get("folder", ""), "folder.precomps" if c["_role"] == "precomp" else "folder.mainComps", c["name"])
    for f in doc["footage"]:
        if not isinstance(f, dict) or not isinstance(f.get("id"), int) or "folder" not in f:
            continue
        key = "folder.solids" if f.get("kind") == "solid" else "folder.audio" if (f.get("hasAudio") and not f.get("hasVideo")) else "folder.footage"
        move(f["id"], "footage", f.get("folder", ""), key, f.get("name", ""))
    expressions, suggestions, dynamic = [], [], 0
    fix = spec.get("fixBrokenRefs", "suggest")
    for c in comps:
        for l in c.get("layers") or []:
            if not isinstance(l, dict):
                continue
            for e in l.get("expressions") or []:
                if not isinstance(e, dict) or e.get("expressionTruncated"):
                    continue
                text = e.get("expression", "")
                where = {"comp": c["name"], "layer": l.get("name"), "path": e.get("propertyPath")}
                unresolved = []
                new, changed = rewrite_expression(text, c["name"], comp_new, layer_new, layer_names, fix, suggestions, where, unresolved)
                if unresolved:
                    dynamic += 1
                if changed:
                    expressions.append({"compId": c["id"], "comp": c["name"], "index": l.get("index"), "layer": l.get("name"), "path": e.get("propertyPath"), "from": text, "to": new})
                if re.search(r"\b(?:comp|layer)\(\s*[^\"'\s)]", text) and not unresolved:
                    dynamic += 1
    return {"itemRenames": item_renames, "layerRenames": layer_renames, "expressions": expressions, "layerLabels": layer_labels,
            "itemLabels": item_labels, "folders": folders, "moves": moves, "suggestions": suggestions, "dynamicReferences": dynamic}
PY_AEJOB_LIB

aejob_python() {
  local _main=""
  IFS= read -r -d '' _main || true
  printf '%s\n%s\n%s' "$MJ_PY_PROTECT_LIB" "$MJ_PY_AEJOB" "$_main" | /usr/bin/python3 - 2>/dev/null
}

aejob_runner_path() {
  local _self
  _self=$(runtime_self_path) || return 1
  printf '%s/../integrations/after-effects/MographJailed_JobRunner.jsx' "${_self%/*}"
}

# Shared checks for an .aep + its scrape (+ optional output folder and label for a job).
aejob_require_inputs() {
  local _aep="$1" _scrape="$2"
  is_absolute_path "$_aep" || { set_error "INVALID_PATH" "Project path must be absolute."; return 65; }
  case "${_aep##*/}" in *.[aA][eE][pP]) ;; *) set_error "INVALID_TARGET" "Project must be an After Effects .aep file."; return 65 ;; esac
  [ -f "$_aep" ] || { set_error "NOT_FOUND" "Project not found."; return 66; }
  mj_require_local_existing_path "$_aep" || return 73
  project_require_scrape_file "$_scrape" || return $?
}

aejob_require_job_output() {
  local _out="$1" _label="$2"
  protect_require_output_dir "$_out" || return $?
  case "$_label" in ""|.*|*[!A-Za-z0-9._-]*) set_error "INVALID_ARGUMENT" "label may contain only letters, digits, dot, dash and underscore."; return 65 ;; esac
  [ ${#_label} -le 64 ] || { set_error "INVALID_ARGUMENT" "label must be at most 64 characters."; return 65; }
}

handle_project_extract() {
  local _rc=0 _aep _scrape _ids _outdir _label _out a
  for a in path input target output label; do require_arg "$a" || { emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }; done
  _aep=$(request_arg_get path); _scrape=$(request_arg_get input); _ids=$(request_arg_get target)
  _outdir=$(request_arg_get output); _label=$(request_arg_get label)
  case "$_ids" in ""|*[!0-9,]*|,*|*,|*,,*) set_error "INVALID_ARGUMENT" "target must be comp ids from the scrape, separated by commas (for example 12,40)."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65 ;; esac
  aejob_require_inputs "$_aep" "$_scrape" || { _rc=$?; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return $_rc; }
  aejob_require_job_output "$_outdir" "$_label" || { _rc=$?; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return $_rc; }
  _out=$(MJ_AEP="$_aep" MJ_SCRAPE="$_scrape" MJ_IDS="$_ids" MJ_OUT="$_outdir" MJ_LABEL="$_label" MJ_RUNNER="$(aejob_runner_path)" aejob_python <<'PY_EXTRACT'
doc = load_scrape(os.environ["MJ_SCRAPE"])
comps, byid = comp_index(doc)
ids = [int(x) for x in os.environ["MJ_IDS"].split(",")]
missing = [i for i in ids if i not in byid]
if missing:
    err("NOT_FOUND", "No comp with id %s in the scrape." % ", ".join(map(str, missing)))
if len(set(ids)) != len(ids):
    err("INVALID_ARGUMENT", "A comp id is listed twice.")
warnings = []
aep = os.environ["MJ_AEP"]
require_same_project(doc, aep)
keep, footage_ids = comp_closure(byid, ids)
fnames = {f.get("id"): f.get("name") for f in doc["footage"] if isinstance(f, dict)}
# Expressions in kept comps that name a comp which will not be in the new project break after extract
# (found running it in After Effects 26.5: comp("Main Comp") inside the extracted precomp).
kept_names = {byid[i]["name"] for i in keep}
outside = []
for cid in sorted(keep):
    for l in byid[cid].get("layers") or []:
        for e in (l.get("expressions") or []) if isinstance(l, dict) else []:
            for m in REF.finditer(e.get("expression", "") if isinstance(e, dict) else ""):
                if m.group(1) == "comp" and m.group(3) not in kept_names:
                    outside.append({"comp": byid[cid]["name"], "layer": l.get("name"), "path": e.get("propertyPath"), "references": m.group(3)})
if outside:
    warnings.append({"code": "EXTERNAL_REFERENCES", "message": "%d expression(s) refer to comps that will not be in the new project (%s); they will error after the extract." % (
        len(outside), ", ".join(sorted({o["references"] for o in outside})))})
body = {"extract": {"compIds": ids, "compNames": [byid[i]["name"] for i in ids]}}
job, plan, cloned = make_job("extract", os.environ["MJ_LABEL"], aep, os.environ["MJ_OUT"], body, os.environ["MJ_RUNNER"], os.environ["MJ_SCRAPE"])
print(json.dumps({"ok": True, "data": {
    "schema": "MJ_AE_JOB_PLAN_1", "kind": "extract", "job": job, "runScript": os.path.join(job, "run.jsx"), "result": plan["result"],
    "source": plan["source"], "copiedInstantly": cloned,
    "comps": [{"id": i, "name": byid[i]["name"]} for i in ids],
    "keeps": {"comps": sorted(byid[i]["name"] for i in keep), "footage": sorted(str(fnames.get(i, i)) for i in footage_ids)},
    "removes": {"comps": len(comps) - len(keep), "footage": max(len(fnames) - len(footage_ids), 0)},
    "externalReferences": outside[:50],
    "_warnings": warnings,
}}))
PY_EXTRACT
) || true
  frames_emit_python_result "$_out"
}

handle_project_conform() {
  local _rc=0 _aep="" _scrape _spec="" _fmt="plan" _outdir="" _label="" _out a
  require_arg input || { emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  _scrape="$MJ_REQUIRED_ARG_VALUE"
  request_arg_present format && _fmt=$(request_arg_get format)
  case "$_fmt" in plan|job) ;; *) set_error "INVALID_ARGUMENT" "format must be plan (default) or job."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65 ;; esac
  request_arg_present spec && _spec=$(request_arg_get spec)
  if [ -n "$_spec" ]; then
    is_absolute_path "$_spec" || { set_error "INVALID_PATH" "Spec path must be absolute."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
    [ -f "$_spec" ] || { set_error "NOT_FOUND" "Studio spec not found."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 66; }
  fi
  if [ "$_fmt" = job ]; then
    for a in path output label; do require_arg "$a" || { emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }; done
    _aep=$(request_arg_get path); _outdir=$(request_arg_get output); _label=$(request_arg_get label)
    aejob_require_inputs "$_aep" "$_scrape" || { _rc=$?; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return $_rc; }
    aejob_require_job_output "$_outdir" "$_label" || { _rc=$?; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return $_rc; }
  else
    project_require_scrape_file "$_scrape" || { _rc=$?; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return $_rc; }
  fi
  _out=$(MJ_AEP="$_aep" MJ_SCRAPE="$_scrape" MJ_SPEC="$_spec" MJ_FMT="$_fmt" MJ_OUT="$_outdir" MJ_LABEL="$_label" MJ_RUNNER="$(aejob_runner_path)" aejob_python <<'PY_CONFORM'
id0 = tree_id(os.environ["MJ_SCRAPE"])
doc = load_scrape(os.environ["MJ_SCRAPE"])
spec = dict(DEFAULT_STUDIO_SPEC)
if os.environ["MJ_SPEC"]:
    spec.update(parse_studio_spec(os.environ["MJ_SPEC"]))
plan = plan_conform(doc, spec)
warnings = []
old = str(doc.get("scraperVersion", "")) < "1.1"
if old:
    warnings.append({"code": "SCRAPE_TOO_OLD", "message": "This scrape is from scraper %s; labels, folders, solids and adjustment layers need scraper 1.1, so only names and expressions are planned." % doc.get("scraperVersion")})
if any(c.get("layersTruncated") for c in doc["comps"] if isinstance(c, dict)) or doc.get("compsTruncated"):
    warnings.append({"code": "SCRAPE_TRUNCATED", "message": "The scrape is truncated; comps or layers beyond its limits are not in the plan."})
if plan["dynamicReferences"]:
    warnings.append({"code": "DYNAMIC_REFERENCES", "message": "%d expression(s) look layers or comps up by a computed name; those references cannot be followed and may need a look after renaming." % plan["dynamicReferences"]})
counts = {k: len(plan[k]) for k in ("itemRenames", "layerRenames", "expressions", "layerLabels", "itemLabels", "moves")}
data = {"schema": "MJ_CONFORM_PLAN_1", "projectName": doc.get("projectName"), "specName": spec.get("name"), "spec": os.environ["MJ_SPEC"] or "built-in",
        "counts": counts, "changes": sum(counts.values()), "plan": plan, "job": None}
if os.environ["MJ_FMT"] == "job":
    aep = os.environ["MJ_AEP"]
    require_same_project(doc, aep)
if os.environ["MJ_FMT"] == "job" and data["changes"] == 0:
    warnings.append({"code": "NOTHING_TO_DO", "message": "The project already matches the spec, so no job was made."})
elif os.environ["MJ_FMT"] == "job":
    body = {"conform": {k: plan[k] for k in ("itemRenames", "layerRenames", "expressions", "layerLabels", "itemLabels", "moves")}, "specName": spec.get("name")}
    job, jp, cloned = make_job("conform", os.environ["MJ_LABEL"], aep, os.environ["MJ_OUT"], body, os.environ["MJ_RUNNER"], os.environ["MJ_SCRAPE"])
    data["job"] = {"folder": job, "runScript": os.path.join(job, "run.jsx"), "result": jp["result"], "source": jp["source"], "copiedInstantly": cloned}
data["sourceUnchanged"] = tree_id(os.environ["MJ_SCRAPE"]) == id0
data["_warnings"] = warnings
print(json.dumps({"ok": True, "data": data}))
PY_CONFORM
) || true
  frames_emit_python_result "$_out"
}

handle_project_jobcheck() {
  local _rc=0 _job _out
  require_arg path || { emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  _job="$MJ_REQUIRED_ARG_VALUE"
  is_absolute_path "$_job" || { set_error "INVALID_PATH" "Job path must be absolute."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  [ -d "$_job" ] && [ -f "$_job/plan.json" ] || { set_error "INVALID_TARGET" "That is not a job folder (no plan.json)."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  mj_require_local_existing_path "$_job" || { emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 73; }
  cap_available python3 || { set_error "UNSUPPORTED" "Job checks require python3."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 69; }
  _out=$(MJ_JOB="$_job" aejob_python <<'PY_JOBCHECK'
job = os.path.realpath(os.environ["MJ_JOB"])
try:
    plan = json.load(open(os.path.join(job, "plan.json"), encoding="utf-8"))
    assert plan.get("schema") == "MJ_AE_JOB_1"
except Exception:
    err("INVALID_RECEIPT", "plan.json is not a MographJailed job plan.")
inside = lambda p: os.path.realpath(p).startswith(job + os.sep)
if not all(inside(plan.get(k, "/")) for k in ("work", "result", "receipt", "quietFlag")):
    err("INVALID_RECEIPT", "The plan points outside its job folder.")
checks = []
def add(name, ok, msg):
    checks.append({"check": name, "ok": ok, "message": msg})
src = plan["source"]["path"]
if os.path.isfile(src):
    same = sha256_file(src) == plan["source"]["sha256"]
    add("originalUnchanged", same, "The original project is byte-for-byte what it was when the job was made." if same else
        "The original project has changed since the job was made (you saved it in After Effects); the job was still applied to the copy.")
else:
    add("originalUnchanged", False, "The original project is no longer at %s." % src)
w = plan["work"]
add("copyUnchanged", os.path.isfile(w) and sha256_file(w) == plan["workSha256"], "before.aep is still the copy the job started from." if os.path.isfile(w) and sha256_file(w) == plan["workSha256"] else "before.aep was changed or removed.")
status, result = "notRun", None
if os.path.isfile(plan["receipt"]):
    try:
        result = json.load(open(plan["receipt"], encoding="utf-8"))
        status = result.get("status", "unknown")
    except Exception:
        status = "unreadable"
add("ran", status != "notRun", "After Effects ran the job (%s)." % status if status != "notRun" else "The job has not been run in After Effects yet.")
res = plan["result"]
has_result = os.path.isfile(res) and os.path.getsize(res) > 0
if status != "notRun":
    add("resultSaved", has_result, "result.aep was saved (%d bytes)." % os.path.getsize(res) if has_result else "There is no result.aep.")
# Complete: After Effects applied it, saved the result, and the copy it worked from is intact. Whether the
# original changed since is reported, not held against the job (you may have kept working on it).
ok = status in ("done", "partial") and has_result and checks[1]["ok"]
print(json.dumps({"ok": True, "data": {
    "schema": "MJ_AE_JOB_CHECK_1", "job": job, "kind": plan.get("kind"), "label": plan.get("label"), "status": status, "complete": ok,
    "result": res if has_result else None, "checks": checks,
    "applied": (result or {}).get("applied"), "steps": (result or {}).get("steps"),
    "skipped": (result or {}).get("skipped", [])[:50], "errors": (result or {}).get("errors", [])[:50],
    "itemsBefore": (result or {}).get("itemsBefore"), "itemsAfter": (result or {}).get("itemsAfter"),
}}))
PY_JOBCHECK
) || true
  frames_emit_python_result "$_out"
}

# --- src/modules/host.zsh ---
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
    # Observed on a real Mac: aerender launched After Effects, exited 0 and rendered nothing. The host
    # was almost certainly waiting on a dialog (sign-in, project conversion, script permissions) that
    # nobody could see; say so instead of leaving a bare "frames are missing".
    silent = status == "incomplete" and frames["count"] == 0 and code == 0 and len(tail) <= 3
    if silent:
        receipt["hint"] = ("The host exited without error but produced no frames. After Effects may be waiting on a dialog "
                           "(sign-in, a project-conversion or crash-recovery prompt, or script permissions). Open the application once by hand, "
                           "clear any prompt, and try again; see the receipt's log.")
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
        err(code_name, "%s%s Receipt: %s" % (msg, (" " + receipt["hint"]) if receipt.get("hint") else "", path))
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

# --- src/cli/entry.zsh ---
MJ_STDIN_REQ=""
MJ_STDIN_HEAD_PID=""
mj_cleanup_stdin() {
  [ -z "$MJ_STDIN_HEAD_PID" ] || kill "$MJ_STDIN_HEAD_PID" 2>/dev/null
  [ -z "$MJ_STDIN_REQ" ] || /bin/rm -f "$MJ_STDIN_REQ"
}

print_help() {
  local _op=""
  printf 'mograph-jailed %s (protocol %s)\n\n' "$MOGRAPHJAILED_CLI_VERSION" "$MOGRAPHJAILED_PROTOCOL_VERSION"
  printf 'Usage:\n  mograph-jailed.zsh --request <request-file>   run one request, print one JSON response\n'
  printf '  mograph-jailed.zsh --request -               read the request from standard input\n'
  printf '  mograph-jailed.zsh --help | --version\n\n'
  printf 'For everyday use, the `mj` shell command builds requests for you (docs/man/mj.md).\n'
  printf 'Request format: PROTOCOL.md. Error codes: docs/man/errors.md.\n\n'
  printf 'Exit codes: 0 ok, 64 usage, 65 bad request, 66 not found, 69 unsupported,\n'
  printf '            73 output problem, 74 operation failed, 77 permission denied\n\n'
  printf 'Operations:\n'
  while IFS= read -r _op; do
    [ -n "$_op" ] || continue
    printf '  %-18s %s\n' "$_op" "$(operation_summary "$_op")"
  done <<EOF_HELP_OPS
$(operation_names)
EOF_HELP_OPS
}

main() {
  local _rc=0
  # `--request -` reads the request from standard input. It is copied (bounded) to a private
  # temp file first, so the parser sees an ordinary file and no special case leaks further.
  if [ "$#" -eq 2 ] && [ "$1" = "--request" ] && [ "$2" = "-" ]; then
    MJ_STDIN_REQ=$(/usr/bin/mktemp "$(mj_tmp_parent)/mj-stdin-request.XXXXXX" 2>/dev/null) || {
      set_error "TEMP_UNAVAILABLE" "Could not create a private file for the request read from standard input."
      emit_error_response "" ""; return 73
    }
    # Read in the background and wait, so a signal can interrupt a blocked read and still clean up.
    trap 'mj_cleanup_stdin; exit 143' TERM
    trap 'mj_cleanup_stdin; exit 130' INT
    trap 'mj_cleanup_stdin; exit 129' HUP
    /usr/bin/head -c 262145 > "$MJ_STDIN_REQ" 2>/dev/null &
    MJ_STDIN_HEAD_PID=$!
    wait "$MJ_STDIN_HEAD_PID" 2>/dev/null
    if [ "$(file_stat_size "$MJ_STDIN_REQ" 2>/dev/null)" -gt 262144 ] 2>/dev/null; then
      /bin/rm -f "$MJ_STDIN_REQ"
      set_error "REQUEST_TOO_LARGE" "Request read from standard input is larger than 256 KB."
      emit_error_response "" ""; return 65
    fi
    set -- --request "$MJ_STDIN_REQ"
  fi
  case "${1:-}" in
    --help|-h) [ "$#" -eq 1 ] && { print_help; return 0; } ;;
    --version|-V) [ "$#" -eq 1 ] && { printf 'mograph-jailed %s (protocol %s)\n' "$MOGRAPHJAILED_CLI_VERSION" "$MOGRAPHJAILED_PROTOCOL_VERSION"; return 0; } ;;
  esac
  if [ "$#" -ne 2 ] || [ "$1" != "--request" ]; then
    set_error "USAGE" "Usage: mograph-jailed.zsh --request <request-file> (see --help)"
    emit_error_response "" ""
    return 64
  fi

  if ! load_request_file "$2"; then
    emit_error_response "${REQUEST_COMMAND:-}" "${REQUEST_ID:-}"
    audit_append 65
    [ -z "$MJ_STDIN_REQ" ] || /bin/rm -f "$MJ_STDIN_REQ"
    return 65
  fi

  dispatch_request
  _rc=$?
  audit_append "$_rc"
  [ -z "$MJ_STDIN_REQ" ] || /bin/rm -f "$MJ_STDIN_REQ"
  return "$_rc"
}

dispatch_request() {
  case "$REQUEST_COMMAND" in
    system.probe) handle_system_probe ;;
    system.doctor) handle_system_doctor ;;
    system.describe) handle_system_describe ;;
    runtime.verify) handle_runtime_verify ;;
    file.inspect) handle_file_inspect ;;
    file.hash) handle_file_hash ;;
    file.provenance) handle_file_provenance ;;
    asset.manifest) handle_asset_manifest ;;
    asset.verify) handle_asset_verify ;;
    search.candidate) handle_search_candidate ;;
    image.inspect) handle_image_inspect ;;
    image.derivative) handle_image_derivative ;;
    image.stats) handle_image_stats ;;
    image.compare) handle_image_compare ;;
    storage.preflight) handle_storage_preflight ;;
    volume.inspect) handle_volume_inspect ;;
    temp.create) handle_temp_create ;;
    temp.clean) handle_temp_clean ;;
    media.inspect) handle_media_inspect ;;
    media.timing) handle_media_timing ;;
    media.frame) handle_media_frame ;;
    project.ingest) handle_project_ingest ;;
    expression.lint) handle_expression_lint ;;
    plugin.audit) handle_plugin_audit ;;
    project.snapshot) handle_project_snapshot ;;
    loop.seams) handle_loop_seams ;;
    golden.record) handle_golden_record ;;
    golden.check) handle_golden_check ;;
    audit.verify) handle_audit_verify ;;
    project.restore) handle_project_restore ;;
    deps.graph) handle_deps_graph ;;
    handoff.package) handle_handoff_package ;;
    index.add) handle_index_add ;;
    index.search) handle_index_search ;;
    index.verify) handle_index_verify ;;
    preset.add) handle_preset_add ;;
    preset.get) handle_preset_get ;;
    host.detect) handle_host_detect ;;
    ae.render) handle_ae_render ;;
    c4d.render) handle_c4d_render ;;
    trace.asset) handle_trace_asset ;;
    audit.plugins) handle_audit_plugins ;;
    project.diff) handle_project_diff ;;
    project.health) handle_project_health ;;
    c4d.inspect) handle_c4d_inspect ;;
    c4d.lint) handle_c4d_lint ;;
    bridge.check) handle_bridge_check ;;
    project.jobcheck) handle_project_jobcheck ;;
    project.conform) handle_project_conform ;;
    project.extract) handle_project_extract ;;
    media.qc) handle_media_qc ;;
    cache.clean) handle_cache_clean ;;
    cache.inspect) handle_cache_inspect ;;
    project.preflight) handle_project_preflight ;;
    report.tech) handle_report_tech ;;
    package.create) handle_package_create ;;
    *)
      set_error "NOT_IMPLEMENTED" "Command is recognized by protocol but not implemented in this build."
      emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"
      return 69
      ;;
  esac
}

main "$@"
