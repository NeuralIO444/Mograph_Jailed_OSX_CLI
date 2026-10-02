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
    system.probe|system.doctor|system.describe|runtime.verify|file.inspect|file.hash|file.provenance|asset.manifest|asset.verify|search.candidate|image.inspect|image.derivative|image.stats|image.compare|storage.preflight|volume.inspect|temp.create|temp.clean|media.inspect|media.timing|media.frame|project.ingest|expression.lint|plugin.audit|project.snapshot|loop.seams|golden.record|golden.check|audit.verify|project.restore|deps.graph|handoff.package|index.add|index.search|index.verify|preset.add|preset.get|host.detect|ae.render|c4d.render|trace.asset|audit.plugins|project.diff|project.health|c4d.inspect|c4d.lint|bridge.check|project.preflight|package.create|report.tech) return 0 ;;
    *) return 1 ;;
  esac
}

is_safe_arg_name() {
  case "$1" in
    path|pathA|pathB|target|label|runId|output|input|format|expectedCliVersion|expectedProtocolVersion|expectedFilename|expectedSha256|expectedSizeBytes|expectedModifiedEpoch|requiredBytes|maxResults|timeSeconds|maxPixels|minFrames|threshold|version|range|timeoutSeconds) return 0 ;;
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
