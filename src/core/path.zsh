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
