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
