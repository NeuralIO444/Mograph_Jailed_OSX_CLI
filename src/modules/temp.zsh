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
