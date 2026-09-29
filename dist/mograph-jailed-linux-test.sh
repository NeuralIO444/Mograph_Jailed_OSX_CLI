#!/usr/bin/env bash
set -u

# --- src/core/constants.zsh ---
MOGRAPHJAILED_PROTOCOL="MOGRAPHJAILED"
MOGRAPHJAILED_PROTOCOL_VERSION="1"
MOGRAPHJAILED_CLI_VERSION="0.3.0-dev.2"
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

# --- src/core/json.zsh ---
json_quote() {
  # JSON-quote one shell string. Shell variables cannot contain NUL; all other
  # ASCII controls are escaped. Unicode bytes are preserved.
  JSON_INPUT="$1" /usr/bin/awk 'BEGIN {
    ORS="";
    s=ENVIRON["JSON_INPUT"];
    printf "\"";
    for (i=1; i<=length(s); i++) {
      c=substr(s,i,1);
      if (c=="\\") printf "\\\\";
      else if (c=="\"") printf "\\\"";
      else if (c=="\b") printf "\\b";
      else if (c=="\f") printf "\\f";
      else if (c=="\n") printf "\\n";
      else if (c=="\r") printf "\\r";
      else if (c=="\t") printf "\\t";
      else {
        code=-1;
        for (j=1; j<32; j++) {
          if (c==sprintf("%c",j)) { code=j; break; }
        }
        if (code>=0) printf "\\u%04x", code;
        else printf "%s", c;
      }
    }
    printf "\"";
  }'
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
  printf ',"warnings":[],"error":null}\n'
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
    system.probe|system.doctor|system.describe|runtime.verify|file.inspect|file.hash|file.provenance|asset.manifest|asset.verify|search.candidate|image.inspect|image.derivative|storage.preflight|volume.inspect|temp.create|temp.clean|media.inspect|media.timing|media.frame|package.create|report.tech) return 0 ;;
    *) return 1 ;;
  esac
}

is_safe_arg_name() {
  case "$1" in
    path|target|label|runId|output|input|format|expectedCliVersion|expectedProtocolVersion|expectedFilename|expectedSha256|expectedSizeBytes|expectedModifiedEpoch|requiredBytes|maxResults|timeSeconds|maxPixels) return 0 ;;
    *) return 1 ;;
  esac
}

REQUEST_ARG_path=""
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
    *) return 1 ;;
  esac
}

request_arg_get() {
  local _name="$1"
  request_arg_present "$_name" || return 1
  case "$_name" in
    path) printf '%s' "$REQUEST_ARG_path" ;;
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

validate_request_schema() {
  local _allowed=""
  local _required=""
  local _arg
  case "$REQUEST_COMMAND" in
    system.probe|system.doctor|system.describe|temp.create|report.tech)
      _allowed=""
      _required=""
      ;;
    runtime.verify)
      _allowed=" expectedCliVersion expectedProtocolVersion expectedFilename expectedSha256 "
      _required=" expectedCliVersion expectedProtocolVersion "
      ;;
    file.inspect|file.hash|file.provenance|image.inspect|volume.inspect|temp.clean|media.inspect|media.timing)
      _allowed=" path "
      _required=" path "
      ;;
    media.frame)
      _allowed=" path output timeSeconds maxPixels "
      _required=" path output timeSeconds "
      ;;
    asset.manifest)
      _allowed=" path format "
      _required=" path "
      ;;
    asset.verify)
      _allowed=" path expectedFilename expectedSizeBytes expectedModifiedEpoch expectedSha256 "
      _required=" path "
      ;;
    search.candidate)
      _allowed=" path target maxResults "
      _required=" path target "
      ;;
    image.derivative)
      _allowed=" input output target "
      _required=" input output target "
      ;;
    storage.preflight)
      _allowed=" path requiredBytes "
      _required=" path "
      ;;
    package.create)
      _allowed=" path output "
      _required=" path output "
      ;;
    *)
      set_error "UNSUPPORTED_COMMAND" "Command is not allowlisted."
      return 1
      ;;
  esac

  for _arg in path target label runId output input format expectedCliVersion expectedProtocolVersion expectedFilename expectedSha256 expectedSizeBytes expectedModifiedEpoch requiredBytes maxResults timeSeconds maxPixels; do
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
    base64) printf '/usr/bin/base64' ;;
    awk) printf '/usr/bin/awk' ;;
    uname) printf '/usr/bin/uname' ;;
    sed) printf '/usr/bin/sed' ;;
    rm) printf '/bin/rm' ;;
    mv) printf '/bin/mv' ;;
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
    storage.preflight \
    volume.inspect \
    temp.create \
    temp.clean \
    media.inspect \
    media.timing \
    media.frame \
    report.tech \
    package.create
}

operation_known() {
  case "$1" in
    system.probe|system.doctor|system.describe|runtime.verify|file.inspect|file.hash|file.provenance|asset.manifest|asset.verify|search.candidate|image.inspect|image.derivative|storage.preflight|volume.inspect|temp.create|temp.clean|media.inspect|media.timing|media.frame|report.tech|package.create) return 0 ;;
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
    package.create)
      cap_available ditto && cap_available mktemp && cap_available rm && cap_available mv && cap_available stat && cap_available uname
      ;;
    *) return 1 ;;
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
    media.inspect) printf 'PATH_DEPENDENT' ;;
    media.timing) printf 'BOUNDED_MEDIA_PROBE' ;;
    media.frame) printf 'FRAME_DECODE' ;;
    package.create) printf 'IO_BOUND' ;;
    *) printf 'UNKNOWN' ;;
  esac
}

operation_mutation() {
  case "$1" in
    temp.create) printf 'TEMP_CREATE' ;;
    temp.clean) printf 'TEMP_DELETE' ;;
    search.candidate) printf 'INTERNAL_TEMP' ;;
    image.derivative|media.frame|package.create) printf 'DERIVATIVE_CREATE' ;;
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
    image.derivative|temp.create|temp.clean|package.create) printf 'AUTHORITATIVE_OPERATION' ;;
    media.inspect) printf 'ADVISORY_METADATA' ;;
    media.timing) printf 'NORMALIZED_NATIVE_MEDIA' ;;
    media.frame) printf 'NATIVE_FRAME_DERIVATIVE' ;;
    report.tech) printf 'DIAGNOSTIC' ;;
    *) printf 'UNKNOWN' ;;
  esac
}

operation_interactive_safe() {
  case "$1" in
    file.hash|asset.manifest|asset.verify|search.candidate|image.derivative|media.timing|media.frame|package.create) return 1 ;;
    *) return 0 ;;
  esac
}

operation_network_sensitive() {
  case "$1" in
    file.inspect|file.hash|file.provenance|asset.manifest|asset.verify|search.candidate|image.inspect|image.derivative|storage.preflight|volume.inspect|media.inspect|media.timing|media.frame|package.create) return 0 ;;
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
    storage.preflight|volume.inspect) printf '%s\n' df awk uname ;;
    temp.create) printf '%s\n' mktemp rm pwd ;;
    temp.clean) printf '%s\n' sed rm pwd ;;
    media.inspect) printf '%s\n' stat file uname ;;
    media.timing) printf '%s\n' avmediainfo awk df uname ;;
    media.frame) printf '%s\n' avmediainfo osascript jq sips awk df mktemp mv rm stat uname ;;
    package.create) printf '%s\n' ditto mktemp rm mv stat uname ;;
  esac
}

operation_optional_capabilities() {
  case "$1" in
    system.probe|system.doctor|report.tech) printf '%s\n' sw_vers ;;
    runtime.verify) printf '%s\n' sha256 shasum ;;
    asset.manifest|asset.verify) printf '%s\n' sha256 shasum ;;
    media.inspect) printf '%s\n' mdls avmediainfo ;;
  esac
}

emit_operation_requires() {
  local _name="$1"
  printf '{"all":'
  operation_required_all "$_name" | emit_string_array_lines
  printf ',"anyOf":['
  case "$_name" in
    file.hash)
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
  printf ',"cost":'; json_quote "$(operation_cost "$_name")"
  printf ',"mutation":'; json_quote "$(operation_mutation "$_name")"
  printf ',"authority":'; json_quote "$(operation_authority "$_name")"
  printf ',"interactiveSafe":'; $_interactive && printf 'true' || printf 'false'
  printf ',"networkSensitive":'; $_network && printf 'true' || printf 'false'
  printf ',"executionScope":'; if [ "$_name" = "media.timing" ] || [ "$_name" = "media.frame" ]; then json_quote "LOCAL_ONLY"; else json_quote "EXPLICIT_PATH_OR_NONE"; fi
  printf ',"requires":'; emit_operation_requires "$_name"
  printf ',"optionalCapabilities":'; operation_optional_capabilities "$_name" | emit_string_array_lines
  printf '}'
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
# - no generic AppleScript/JXA Objective-C bridge is exposed to callers.
#
# Bridge note (target-Mac Gate A, 2026-09-29): macOS Tahoe (26.x) broke JXA's
# ObjC bridge for AVFoundation ($.AVURLAsset is undefined even though
# ObjC.import('AVFoundation') succeeds), while Foundation still bridges.
# AppleScriptObjC (use framework "AVFoundation") still sees AVFoundation
# classes on Tahoe, so the adapter is AppleScriptObjC. The embedded script is
# fixed; request data enters only through environment variables.
#
# Frame-grid note: with zero tolerance, AVAssetImageGenerator returns nil
# unless the requested time is exactly a sample presentation time. A raw
# request like 1.0s in 29.97fps media names no real frame, so the adapter
# snaps the request down to the containing frame's exact presentation time
# using integer math on the video track's natural timescale, then extracts
# with zero tolerance. requestedSeconds echoes the caller's time;
# actualSeconds/value/timescale name the extracted frame. Consumers must use
# actualTime for verification (the media.frame contract already provides it
# alongside deltaSeconds).

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

# Executes a fixed embedded AppleScriptObjC adapter. Request data is supplied
# only through environment variables; no request value is interpreted as
# AppleScript source. The adapter extracts the full-resolution frame; the
# caller (media.frame) bounds dimensions afterwards with sips so the adapter
# stays narrow and every bridge call is an object call or a proven C function.
frame_kit_extract_png() {
  local _source="$1"
  local _output="$2"
  local _seconds="$3"
  local _json=""

  frame_kit_reset
  cap_available osascript && cap_available jq || return 1

  _json=$(MJ_FRAMEKIT_SOURCE="$_source" \
    MJ_FRAMEKIT_OUTPUT="$_output" \
    MJ_FRAMEKIT_SECONDS="$_seconds" \
    /usr/bin/osascript - <<'ASOBJC_FRAMEKIT' 2>/dev/null
use framework "AVFoundation"
use framework "Foundation"
use framework "AppKit"
use scripting additions

on errorJSON(code, message)
  return "{\"ok\":false,\"code\":\"" & code & "\",\"message\":\"" & message & "\"}"
end errorJSON

try
  set srcPath to system attribute "MJ_FRAMEKIT_SOURCE"
  set outPath to system attribute "MJ_FRAMEKIT_OUTPUT"
  set secsText to system attribute "MJ_FRAMEKIT_SECONDS"
  if srcPath is missing value or srcPath is "" then return my errorJSON("INVALID_SOURCE", "Missing source path.")
  if outPath is missing value or outPath is "" then return my errorJSON("INVALID_OUTPUT", "Missing output path.")
  if secsText is missing value or secsText is "" then return my errorJSON("INVALID_TIME", "Missing requested time.")
  set tSecs to secsText as real
  if tSecs < 0 then return my errorJSON("INVALID_TIME", "Requested time is negative.")

  set theURL to current application's NSURL's fileURLWithPath:srcPath
  if theURL is missing value then return my errorJSON("ASSET_OPEN_FAILED", "Could not form a file URL for the source.")
  set theAsset to current application's AVURLAsset's alloc()'s initWithURL:theURL options:(missing value)
  if theAsset is missing value then return my errorJSON("ASSET_OPEN_FAILED", "AVURLAsset could not open the source.")

  set vTracks to theAsset's tracksWithMediaType:(current application's AVMediaTypeVideo)
  if (count of vTracks) < 1 then return my errorJSON("NO_VIDEO_TRACK_ADAPTER", "The asset has no video track.")
  set vTrack to item 1 of vTracks
  set fps to vTrack's nominalFrameRate
  set nts to vTrack's naturalTimeScale
  if fps <= 0 or nts <= 0 then return my errorJSON("FRAME_GRID_UNAVAILABLE", "The video track has no usable frame grid; variable frame rate media is not supported.")
  set ticksPerFrame to round (nts / fps)
  if ticksPerFrame < 1 then return my errorJSON("FRAME_GRID_UNAVAILABLE", "The video track frame grid is not usable.")

  set frameIndex to (tSecs * fps) div 1
  set frameValue to frameIndex * ticksPerFrame
  set requestedTime to current application's CMTimeMake(frameValue, nts)
  set actualSeconds to frameValue / nts

  set gen to current application's AVAssetImageGenerator's assetImageGeneratorWithAsset:theAsset
  if gen is missing value then return my errorJSON("GENERATOR_FAILED", "AVAssetImageGenerator could not be created.")
  gen's setAppliesPreferredTrackTransform:true
  gen's setRequestedTimeToleranceBefore:(current application's CMTimeMake(0, nts))
  gen's setRequestedTimeToleranceAfter:(current application's CMTimeMake(0, nts))

  set cgImage to gen's copyCGImageAtTime:requestedTime actualTime:(missing value) |error|:(missing value)
  if cgImage is missing value then return my errorJSON("FRAME_GENERATION_FAILED", "AVFoundation did not return an image for the snapped frame time.")

  set rep to current application's NSBitmapImageRep's alloc()'s initWithCGImage:cgImage
  if rep is missing value then return my errorJSON("PNG_ENCODE_FAILED", "NSBitmapImageRep could not wrap the generated image.")
  set pngData to rep's representationUsingType:(current application's NSPNGFileType) |properties|:(missing value)
  if pngData is missing value then return my errorJSON("PNG_ENCODE_FAILED", "AppKit could not encode the generated image as PNG.")
  set wroteOK to pngData's writeToFile:outPath atomically:true
  if wroteOK is not true then return my errorJSON("PNG_WRITE_FAILED", "PNG data could not be written to the staged output.")

  set w to rep's pixelsWide()
  set h to rep's pixelsHigh()
  if w < 1 or h < 1 then return my errorJSON("FRAME_RESULT_INVALID", "AVFoundation returned invalid frame dimensions.")

  return "{\"ok\":true,\"requestedSeconds\":" & (tSecs as text) & ",\"actualSeconds\":" & (actualSeconds as text) & ",\"actualValue\":" & (frameValue as text) & ",\"actualTimescale\":" & (nts as text) & ",\"pixelWidth\":" & (w as text) & ",\"pixelHeight\":" & (h as text) & ",\"transformApplied\":true,\"toleranceBeforeSeconds\":0,\"toleranceAfterSeconds\":0,\"adapter\":\"ASOBJC_AVAssetImageGenerator\"}"
on error e
  return my errorJSON("ASOBJC_EXCEPTION", "AppleScriptObjC adapter failed: " & (e as text))
end try
ASOBJC_FRAMEKIT
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
  cap_available osascript && cap_available jq && cap_available sips && cap_available awk && cap_available mktemp && cap_available mv && cap_available rm && cap_available stat && cap_available uname && standard_library_localfs_available && standard_library_mediaprobe_available
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
  standard_library_framekit_available && _frame=true

  printf '{"version":'; json_quote "$MOGRAPHJAILED_STANDARD_LIBRARY_VERSION"
  printf ',"policy":{"localOnlyByDefault":true,"networkMutation":false,"networkEnumeration":false,"arbitrarySqlAPI":false,"rawShellAPI":false}'
  printf ',"modules":{'
  printf '"LocalFS":{"available":'; $_localfs && printf 'true' || printf 'false'; printf ',"state":'; if $_localfs; then json_quote 'AVAILABLE'; else json_quote 'UNAVAILABLE'; fi; printf ',"authority":"FILESYSTEM_SCOPE"}'
  printf ',"NativeDB":{"available":'; $_db && printf 'true' || printf 'false'; printf ',"state":'; if $_db; then json_quote 'AVAILABLE'; else json_quote 'UNAVAILABLE'; fi; printf ',"authority":"LOCAL_STRUCTURED_STORAGE","publicSql":false,"version":'; [ -n "$_db_version" ] && json_quote "$_db_version" || printf 'null'; printf ',"features":{"json":'; $_db_json && printf 'true' || printf 'false'; printf ',"fts5":'; $_db_fts5 && printf 'true' || printf 'false'; printf '}}'
  printf ',"MediaProbe":{"available":'; $_media && printf 'true' || printf 'false'; printf ',"state":'; if $_media; then json_quote 'AVAILABLE'; else json_quote 'UNAVAILABLE'; fi; printf ',"authority":"NORMALIZED_NATIVE_MEDIA"}'
  printf ',"ImageKit":{"available":'; $_image && printf 'true' || printf 'false'; printf ',"state":'; if $_image; then json_quote 'AVAILABLE'; else json_quote 'UNAVAILABLE'; fi; printf ',"authority":"NATIVE_IMAGE"}'
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
  for _cap in zsh sw_vers stat file df mktemp plutil sqlite3 jq sips ditto sha256 shasum mdls avmediainfo avconvert afinfo afconvert mdfind xattr osascript base64 awk uname sed rm mv pwd; do
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

  _before=$(file_hash_identity "$_path") || { set_error "SOURCE_STATE_UNAVAILABLE" "Could not establish media source identity before frame extraction."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 74; }
  create_mj_stage_dir "$_parent_real" "$_stage_prefix" || { set_error "TEMP_CREATE_FAILED" "Could not create and bind FrameKit staging directory."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 73; }
  _stage="$MJ_STAGE_DIR"
  _stage_file="$_stage/frame.png"

  if ! frame_kit_extract_png "$_path" "$_stage_file" "$_time"; then
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
  for _cap in zsh sw_vers stat file df mktemp plutil sqlite3 jq sips ditto sha256 shasum mdls avmediainfo avconvert afinfo afconvert mdfind xattr osascript base64 awk uname sed rm mv pwd; do
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

# --- src/cli/entry.zsh ---
main() {
  if [ "$#" -ne 2 ] || [ "$1" != "--request" ]; then
    set_error "USAGE" "Usage: mograph-jailed.zsh --request <request-file>"
    emit_error_response "" ""
    return 64
  fi

  if ! load_request_file "$2"; then
    emit_error_response "${REQUEST_COMMAND:-}" "${REQUEST_ID:-}"
    return 65
  fi

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
    storage.preflight) handle_storage_preflight ;;
    volume.inspect) handle_volume_inspect ;;
    temp.create) handle_temp_create ;;
    temp.clean) handle_temp_clean ;;
    media.inspect) handle_media_inspect ;;
    media.timing) handle_media_timing ;;
    media.frame) handle_media_frame ;;
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
