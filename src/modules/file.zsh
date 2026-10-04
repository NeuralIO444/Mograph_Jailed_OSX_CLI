file_stat_size() {
  local _path="$1"
  if [ "$(/usr/bin/uname -s 2>/dev/null)" = "Darwin" ]; then
    /usr/bin/stat -f '%z' "$_path" 2>/dev/null
  else
    /usr/bin/stat -c '%s' "$_path" 2>/dev/null
  fi
}

# size:mtime identity, used to report honestly whether a source changed while an operation ran.
source_identity() { printf '%s:%s' "$(file_stat_size "$1" 2>/dev/null)" "$(file_stat_mtime "$1" 2>/dev/null)"; }
source_unchanged_json() { [ "$1" = "$(source_identity "$2")" ] && printf 'true' || printf 'false'; }

file_stat_mtime() {
  local _path="$1"
  if [ "$(/usr/bin/uname -s 2>/dev/null)" = "Darwin" ]; then
    /usr/bin/stat -f '%m' "$_path" 2>/dev/null
  else
    /usr/bin/stat -c '%Y' "$_path" 2>/dev/null
  fi
}

# Identity of the bytes that file.hash will read. -L follows a symlink target so
# pre/post stability checks describe the hashed file rather than the link node.
file_hash_identity() {
  local _path="$1"
  if [ "$(/usr/bin/uname -s 2>/dev/null)" = "Darwin" ]; then
    /usr/bin/stat -L -f '%d:%i:%z:%m' "$_path" 2>/dev/null
  else
    /usr/bin/stat -L -c '%d:%i:%s:%Y' "$_path" 2>/dev/null
  fi
}

file_basic_type() {
  /usr/bin/file -b "$1" 2>/dev/null || printf ''
}

handle_file_inspect() {
  local _path=""
  local _kind="other"
  local _size=""
  local _mtime=""
  local _type=""

  require_arg path || { emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  _path="$MJ_REQUIRED_ARG_VALUE"
  is_absolute_path "$_path" || { set_error "INVALID_PATH" "Path must be absolute."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  cap_available stat && cap_available file && cap_available uname || { set_error "UNSUPPORTED" "File inspection requires stock macOS stat/file/uname capabilities."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 69; }

  if [ ! -e "$_path" ] && [ ! -L "$_path" ]; then
    set_error "NOT_FOUND" "Path does not exist."
    emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"
    return 66
  fi

  [ -f "$_path" ] && _kind="file"
  [ -d "$_path" ] && _kind="directory"
  [ -L "$_path" ] && _kind="symlink"
  _size=$(file_stat_size "$_path" || printf '')
  _mtime=$(file_stat_mtime "$_path" || printf '')
  _type=$(file_basic_type "$_path")

  emit_success_start "$REQUEST_COMMAND" "$REQUEST_ID"
  printf '{"path":'; json_quote "$_path"
  printf ',"kind":'; json_quote "$_kind"
  printf ',"sizeBytes":'; if [ -n "$_size" ]; then printf '%s' "$_size"; else printf 'null'; fi
  printf ',"modifiedEpoch":'; if [ -n "$_mtime" ]; then printf '%s' "$_mtime"; else printf 'null'; fi
  printf ',"readable":'; [ -r "$_path" ] && printf 'true' || printf 'false'
  printf ',"writableHint":'; [ -w "$_path" ] && printf 'true' || printf 'false'
  printf ',"executable":'; [ -x "$_path" ] && printf 'true' || printf 'false'
  printf ',"basicType":'; json_quote "$_type"
  printf ',"sources":["stat","file"],"advisory":{"writableHint":true}}'
  emit_success_end
}

hash_sha256_file() {
  local _path="$1"
  local _sha=""
  local _out=""
  MJ_HASH_SOURCE=""
  MJ_HASH_VALUE=""
  if cap_available sha256; then
    _sha=$(cap_path sha256)
    _out=$("$_sha" -q "$_path" 2>/dev/null) || return 1
    MJ_HASH_SOURCE="sha256"
    MJ_HASH_VALUE="$_out"
    return 0
  fi
  if cap_available shasum; then
    _out=$(/usr/bin/shasum -a 256 "$_path" 2>/dev/null) || return 1
    MJ_HASH_SOURCE="shasum"
    MJ_HASH_VALUE=${_out%% *}
    return 0
  fi
  return 69
}

handle_file_hash() {
  local _path=""
  local _hash_rc=0
  local _hash=""
  local _identity_before=""
  local _identity_after=""

  require_arg path || { emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  _path="$MJ_REQUIRED_ARG_VALUE"
  is_absolute_path "$_path" || { set_error "INVALID_PATH" "Path must be absolute."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  [ -e "$_path" ] || { set_error "NOT_FOUND" "Path does not exist."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 66; }
  [ -f "$_path" ] || { set_error "INVALID_TARGET" "Hash target must be a regular file."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  [ -r "$_path" ] || { set_error "PERMISSION_DENIED" "File is not readable."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 77; }
  cap_available stat && cap_available uname || { set_error "UNSUPPORTED" "File hashing requires stock macOS stat/uname capabilities."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 69; }

  _identity_before=$(file_hash_identity "$_path") || { set_error "SOURCE_STATE_UNAVAILABLE" "Could not establish source identity before hashing."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 74; }
  hash_sha256_file "$_path"
  _hash_rc=$?
  if [ "$_hash_rc" -eq 69 ]; then
    set_error "UNSUPPORTED" "No approved native SHA-256 utility is available."
    emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"
    return 69
  elif [ "$_hash_rc" -ne 0 ]; then
    set_error "HASH_FAILED" "SHA-256 calculation failed."
    emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"
    return 74
  fi
  _identity_after=$(file_hash_identity "$_path") || { set_error "SOURCE_CHANGED" "Source state could not be re-established after hashing."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 74; }
  if [ "$_identity_before" != "$_identity_after" ]; then
    set_error "SOURCE_CHANGED" "Source identity changed while SHA-256 was being calculated."
    emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"
    return 74
  fi

  _hash="$MJ_HASH_VALUE"
  case "$_hash" in *[!0-9a-fA-F]*|'') set_error "NATIVE_OUTPUT_INVALID" "Hash utility returned unexpected output."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 74 ;; esac
  [ ${#_hash} -eq 64 ] || { set_error "NATIVE_OUTPUT_INVALID" "Hash utility returned unexpected length."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 74; }

  emit_success_start "$REQUEST_COMMAND" "$REQUEST_ID"
  printf '{"path":'; json_quote "$_path"; printf ',"algorithm":"SHA-256","hash":'; json_quote "$_hash"; printf ',"source":'; json_quote "$MJ_HASH_SOURCE"; printf ',"stabilityCheck":"device+inode+size+mtime"}'
  emit_success_end
}

# macOS file flags (st_flags). SF_DATALESS (0x40000000) marks a file whose bytes live in the cloud (Dropbox, iCloud,
# OneDrive "online only"): reading it would download it, or hand back nothing. Prints 0 off macOS.
file_stat_flags() {
  if [ "$(/usr/bin/uname -s 2>/dev/null)" = "Darwin" ]; then /usr/bin/stat -f '%f' "$1" 2>/dev/null || printf '0'; else printf '0'; fi
}

# A project or scene must have its bytes on this Mac before anything hashes, copies or opens it. Looks at the file's
# metadata only (never reads it, so it cannot start a download). Sets the error and returns 65 (empty) or 74 (cloud only).
file_require_materialized() {
  local _p="$1" _flags _size
  _flags=$(file_stat_flags "$_p"); _flags=${_flags:-0}
  if [ $(( _flags & 1073741824 )) -ne 0 ]; then
    set_error "FILE_NOT_DOWNLOADED" "$(basename -- "$_p") is stored online only (Dropbox, iCloud or similar) and is not on this Mac yet. Make it available offline, wait for it to finish downloading, then try again."
    return 74
  fi
  _size=$(file_stat_size "$_p"); _size=${_size:-0}
  if [ "$_size" -le 0 ]; then
    set_error "FILE_EMPTY" "$(basename -- "$_p") is empty (0 bytes). If it lives in Dropbox or iCloud it may not have downloaded yet: open it once, or make it available offline, then try again."
    return 65
  fi
  return 0
}
