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
