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
