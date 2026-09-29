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
