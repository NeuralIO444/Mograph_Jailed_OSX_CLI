canonical_dir() {
  canonical_existing_dir "$1"
}

handle_package_create() {
  local _src=""
  local _out=""
  local _parent=""
  local _src_real=""
  local _parent_real=""
  local _out_leaf=""
  local _out_real=""
  local _stage=""
  local _stage_zip=""
  local _stage_prefix="MographJailed_Package"
  local _size=""

  require_arg path || { emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  _src="$MJ_REQUIRED_ARG_VALUE"
  require_arg output || { emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  _out="$MJ_REQUIRED_ARG_VALUE"
  is_absolute_path "$_src" && is_absolute_path "$_out" || { set_error "INVALID_PATH" "Source and output paths must be absolute."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  [ -d "$_src" ] || { set_error "INVALID_TARGET" "Package source must be a directory."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  [ ! -L "$_src" ] || { set_error "INVALID_TARGET" "Package source directory may not be a symlink."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  [ -r "$_src" ] || { set_error "PERMISSION_DENIED" "Package source is not readable."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 77; }
  case "$_out" in *.zip) ;; *) set_error "INVALID_OUTPUT" "Package output must end in .zip."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65 ;; esac

  _parent=$(parent_path "$_out")
  [ -d "$_parent" ] && [ -w "$_parent" ] || { set_error "OUTPUT_UNAVAILABLE" "Package output directory is unavailable or not writable."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 73; }
  _src_real=$(canonical_dir "$_src") || { set_error "INVALID_TARGET" "Could not resolve package source."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  _parent_real=$(canonical_dir "$_parent") || { set_error "OUTPUT_UNAVAILABLE" "Could not resolve package output directory."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 73; }
  _out_leaf=${_out##*/}
  _out_real="$_parent_real/$_out_leaf"
  case "$_out_real" in "$_src_real"/*) set_error "INVALID_OUTPUT" "Package output may not be inside the package source tree."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65 ;; esac
  if [ -e "$_out_real" ] || [ -L "$_out_real" ]; then set_error "OUTPUT_EXISTS" "Refusing to overwrite an existing package."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 73; fi

  cap_available ditto && cap_available mktemp && cap_available mv && cap_available rm && cap_available stat && cap_available uname || { set_error "UNSUPPORTED" "Native packaging requires stock macOS ditto/mktemp/mv/rm/stat/uname capabilities."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 69; }

  # Re-check the canonical source immediately before invoking ditto. A shell
  # adapter cannot make directory replacement fully race-free, but it can fail
  # closed for ordinary symlink substitution before the native copy begins.
  [ -d "$_src_real" ] && [ ! -L "$_src_real" ] || { set_error "INVALID_TARGET" "Package source changed during validation."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 73; }

  # Stage and publish through the canonical parent so retargeting a symlinked
  # lexical parent cannot redirect the final write after validation. The stage
  # itself is ownership-bound before any recursive cleanup is permitted.
  create_mj_stage_dir "$_parent_real" "$_stage_prefix" || { set_error "TEMP_CREATE_FAILED" "Could not create and bind package staging directory."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 73; }
  _stage="$MJ_STAGE_DIR"
  _stage_zip="$_stage/package.zip"
  if ! /usr/bin/ditto -c -k --sequesterRsrc --keepParent "$_src_real" "$_stage_zip" 2>/dev/null; then
    cleanup_mj_stage_dir "$_stage" "$_parent_real" "$_stage_prefix" || { set_error "STAGE_CLEANUP_REFUSED" "Packaging failed and its staging directory could not be proven safe for cleanup."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 74; }
    set_error "PACKAGE_FAILED" "Native report packaging failed."
    emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"
    return 74
  fi

  if ! /bin/mv -n "$_stage_zip" "$_out_real" 2>/dev/null; then
    cleanup_mj_stage_dir "$_stage" "$_parent_real" "$_stage_prefix" || { set_error "STAGE_CLEANUP_REFUSED" "Package publish failed and staging cleanup was refused."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 74; }
    set_error "PACKAGE_FAILED" "Package publish failed."
    emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"
    return 74
  fi
  if [ -e "$_stage_zip" ] || [ -L "$_stage_zip" ]; then
    cleanup_mj_stage_dir "$_stage" "$_parent_real" "$_stage_prefix" || { set_error "STAGE_CLEANUP_REFUSED" "Package output appeared concurrently and staging cleanup was refused."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 74; }
    if [ -e "$_out_real" ] || [ -L "$_out_real" ]; then
      set_error "OUTPUT_EXISTS" "Package output appeared during creation; refusing to overwrite it."
      emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"
      return 73
    fi
    set_error "PACKAGE_FAILED" "Package publish did not move the staged archive."
    emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"
    return 74
  fi
  cleanup_mj_stage_dir "$_stage" "$_parent_real" "$_stage_prefix" || { set_error "STAGE_CLEANUP_REFUSED" "Published package but could not prove staging ownership for cleanup."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 74; }
  [ -f "$_out_real" ] || { set_error "PACKAGE_FAILED" "Package output was not created."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 74; }

  _size=$(file_stat_size "$_out_real" 2>/dev/null || printf '')
  emit_success_start "$REQUEST_COMMAND" "$REQUEST_ID"
  printf '{"source":'; json_quote "$_src"; printf ',"output":'; json_quote "$_out"
  printf ',"resolvedOutput":'; json_quote "$_out_real"
  printf ',"format":"zip","sourceTool":"ditto","sizeBytes":'; [ -n "$_size" ] && printf '%s' "$_size" || printf 'null'
  printf '}'
  emit_success_end
}
