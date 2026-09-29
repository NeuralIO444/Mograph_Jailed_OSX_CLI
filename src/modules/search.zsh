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
