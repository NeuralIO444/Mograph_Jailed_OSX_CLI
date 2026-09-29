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
