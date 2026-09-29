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
