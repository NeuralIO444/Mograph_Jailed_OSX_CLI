asset_is_uint() {
  case "$1" in ''|*[!0-9]*) return 1 ;; *) return 0 ;; esac
}

asset_normalize_sha256() {
  local _value="$1"
  local _norm
  _norm=$(printf '%s' "$_value" | /usr/bin/awk '{print tolower($0)}')
  case "$_norm" in *[!0-9a-f]*|'') return 1 ;; esac
  [ ${#_norm} -eq 64 ] || return 1
  printf '%s' "$_norm"
}

asset_stable_sha256() {
  local _path="$1"
  local _before=""
  local _after=""
  MJ_ASSET_HASH=""
  MJ_ASSET_HASH_SOURCE=""
  _before=$(file_hash_identity "$_path") || return 74
  hash_sha256_file "$_path"
  local _rc=$?
  [ "$_rc" -eq 0 ] || return "$_rc"
  _after=$(file_hash_identity "$_path") || return 74
  [ "$_before" = "$_after" ] || return 75
  MJ_ASSET_HASH="$MJ_HASH_VALUE"
  MJ_ASSET_HASH_SOURCE="$MJ_HASH_SOURCE"
  return 0
}

handle_asset_manifest() {
  local _path=""
  local _mode="fast"
  local _size=""
  local _mtime=""
  local _type=""
  local _filename=""
  local _sha=""
  local _hash_source=""
  local _hash_rc=0

  require_arg path || { emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  _path="$MJ_REQUIRED_ARG_VALUE"
  if request_arg_present format; then _mode=$(request_arg_get format); fi
  case "$_mode" in fast|sha256) ;; *) set_error "INVALID_ARGUMENT" "asset.manifest format must be fast or sha256."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65 ;; esac
  is_absolute_path "$_path" || { set_error "INVALID_PATH" "Path must be absolute."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  [ -f "$_path" ] || { set_error "INVALID_TARGET" "Asset manifest target must be a regular file."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  [ -r "$_path" ] || { set_error "PERMISSION_DENIED" "Asset is not readable."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 77; }
  cap_available stat && cap_available file && cap_available uname || { set_error "UNSUPPORTED" "Asset manifest requires stock macOS stat/file/uname capabilities."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 69; }

  _size=$(file_stat_size "$_path" 2>/dev/null || printf '')
  _mtime=$(file_stat_mtime "$_path" 2>/dev/null || printf '')
  _type=$(file_basic_type "$_path")
  _filename=${_path##*/}
  [ -n "$_size" ] && [ -n "$_mtime" ] || { set_error "SOURCE_STATE_UNAVAILABLE" "Could not establish asset stat identity."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 74; }

  if [ "$_mode" = "sha256" ]; then
    asset_stable_sha256 "$_path"
    _hash_rc=$?
    if [ "$_hash_rc" -eq 69 ]; then
      set_error "UNSUPPORTED" "SHA-256 manifest mode requires an approved native SHA-256 utility."
      emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 69
    elif [ "$_hash_rc" -eq 75 ]; then
      set_error "SOURCE_CHANGED" "Asset changed while its manifest hash was being calculated."
      emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 74
    elif [ "$_hash_rc" -ne 0 ]; then
      set_error "HASH_FAILED" "Could not calculate asset SHA-256."
      emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 74
    fi
    _sha="$MJ_ASSET_HASH"
    _hash_source="$MJ_ASSET_HASH_SOURCE"
  fi

  emit_success_start "$REQUEST_COMMAND" "$REQUEST_ID"
  printf '{"schema":"MJ_ASSET_MANIFEST_1","path":'; json_quote "$_path"
  printf ',"filename":'; json_quote "$_filename"
  printf ',"sizeBytes":%s,"modifiedEpoch":%s' "$_size" "$_mtime"
  printf ',"basicType":'; json_quote "$_type"
  printf ',"identity":{"mode":'; if [ "$_mode" = "sha256" ]; then json_quote "SHA256"; else json_quote "STAT_FINGERPRINT"; fi
  printf ',"sha256":'; if [ -n "$_sha" ]; then json_quote "$_sha"; else printf 'null'; fi
  printf ',"hashSource":'; if [ -n "$_hash_source" ]; then json_quote "$_hash_source"; else printf 'null'; fi
  printf ',"stabilityCheck":'; if [ "$_mode" = "sha256" ]; then json_quote "device+inode+size+mtime"; else printf 'null'; fi
  printf '}}'
  emit_success_end
}

handle_asset_verify() {
  local _path=""
  local _filename=""
  local _size=""
  local _mtime=""
  local _expected_filename=""
  local _expected_size=""
  local _expected_mtime=""
  local _expected_sha=""
  local _actual_sha=""
  local _match=true
  local _filename_check="null"
  local _size_check="null"
  local _mtime_check="null"
  local _sha_check="null"
  local _checks=0
  local _hash_rc=0

  require_arg path || { emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  _path="$MJ_REQUIRED_ARG_VALUE"
  is_absolute_path "$_path" || { set_error "INVALID_PATH" "Path must be absolute."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  [ -f "$_path" ] || { set_error "INVALID_TARGET" "Asset verify target must be a regular file."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  [ -r "$_path" ] || { set_error "PERMISSION_DENIED" "Asset is not readable."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 77; }
  cap_available stat && cap_available uname || { set_error "UNSUPPORTED" "Asset verification requires stock macOS stat/uname capabilities."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 69; }

  _filename=${_path##*/}
  _size=$(file_stat_size "$_path" 2>/dev/null || printf '')
  _mtime=$(file_stat_mtime "$_path" 2>/dev/null || printf '')
  [ -n "$_size" ] && [ -n "$_mtime" ] || { set_error "SOURCE_STATE_UNAVAILABLE" "Could not establish asset stat identity."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 74; }

  if request_arg_present expectedFilename; then
    _checks=$((_checks+1)); _expected_filename=$(request_arg_get expectedFilename)
    case "$_expected_filename" in ''|*/*) set_error "INVALID_ARGUMENT" "expectedFilename must be a filename, not a path."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65 ;; esac
    [ "$_filename" = "$_expected_filename" ] && _filename_check=true || { _filename_check=false; _match=false; }
  fi
  if request_arg_present expectedSizeBytes; then
    _checks=$((_checks+1)); _expected_size=$(request_arg_get expectedSizeBytes)
    asset_is_uint "$_expected_size" || { set_error "INVALID_ARGUMENT" "expectedSizeBytes must be an unsigned integer."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
    [ "$_size" = "$_expected_size" ] && _size_check=true || { _size_check=false; _match=false; }
  fi
  if request_arg_present expectedModifiedEpoch; then
    _checks=$((_checks+1)); _expected_mtime=$(request_arg_get expectedModifiedEpoch)
    asset_is_uint "$_expected_mtime" || { set_error "INVALID_ARGUMENT" "expectedModifiedEpoch must be an unsigned integer."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
    [ "$_mtime" = "$_expected_mtime" ] && _mtime_check=true || { _mtime_check=false; _match=false; }
  fi
  if request_arg_present expectedSha256; then
    _checks=$((_checks+1)); _expected_sha=$(asset_normalize_sha256 "$(request_arg_get expectedSha256)" 2>/dev/null || printf '')
    [ -n "$_expected_sha" ] || { set_error "INVALID_ARGUMENT" "expectedSha256 must be a 64-character hexadecimal SHA-256 digest."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
    asset_stable_sha256 "$_path"; _hash_rc=$?
    if [ "$_hash_rc" -eq 69 ]; then set_error "UNSUPPORTED" "SHA-256 verification requires an approved native SHA-256 utility."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 69
    elif [ "$_hash_rc" -eq 75 ]; then set_error "SOURCE_CHANGED" "Asset changed while verification hash was being calculated."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 74
    elif [ "$_hash_rc" -ne 0 ]; then set_error "HASH_FAILED" "Could not calculate asset SHA-256."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 74; fi
    _actual_sha="$MJ_ASSET_HASH"
    [ "$_actual_sha" = "$_expected_sha" ] && _sha_check=true || { _sha_check=false; _match=false; }
  fi

  [ "$_checks" -gt 0 ] || { set_error "MISSING_ARGUMENT" "asset.verify requires at least one expected identity field."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }

  emit_success_start "$REQUEST_COMMAND" "$REQUEST_ID"
  printf '{"match":'; $_match && printf 'true' || printf 'false'
  printf ',"path":'; json_quote "$_path"
  printf ',"actual":{"filename":'; json_quote "$_filename"; printf ',"sizeBytes":%s,"modifiedEpoch":%s,"sha256":' "$_size" "$_mtime"; if [ -n "$_actual_sha" ]; then json_quote "$_actual_sha"; else printf 'null'; fi; printf '}'
  printf ',"checks":{"filename":%s,"sizeBytes":%s,"modifiedEpoch":%s,"sha256":%s}' "$_filename_check" "$_size_check" "$_mtime_check" "$_sha_check"
  printf '}'
  emit_success_end
}
