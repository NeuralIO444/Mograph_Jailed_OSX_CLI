runtime_self_path() {
  local _self="$0"
  # In zsh, FUNCTION_ARGZERO changes $0 while inside shell functions.
  # ZSH_ARGZERO remains the original script used to invoke this shell and is
  # therefore the authoritative runtime path for production /bin/zsh -f use.
  if [ -n "${ZSH_VERSION:-}" ] && [ -n "${ZSH_ARGZERO:-}" ]; then
    _self="$ZSH_ARGZERO"
  fi
  case "$_self" in
    /*) printf '%s' "$_self" ;;
    ./*) printf '%s/%s' "$(/bin/pwd -P)" "${_self#./}" ;;
    */*)
      local _dir=${_self%/*}
      local _leaf=${_self##*/}
      local _real_dir
      _real_dir=$(cd "$_dir" 2>/dev/null && /bin/pwd -P) || return 1
      printf '%s/%s' "$_real_dir" "$_leaf"
      ;;
    *) printf '%s' "$_self" ;;
  esac
}

runtime_bool_json() {
  if [ "$1" = "true" ]; then printf 'true'; else printf 'false'; fi
}

runtime_verify_hash() {
  local _path="$1"
  hash_sha256_file "$_path"
}

handle_runtime_verify() {
  local _expected_cli=""
  local _expected_protocol=""
  local _expected_filename=""
  local _expected_sha=""
  local _expected_sha_norm=""
  local _self=""
  local _filename=""
  local _actual_sha=""
  local _hash_source=""
  local _cli_ok=false
  local _protocol_ok=false
  local _filename_ok=true
  local _sha_ok=true
  local _filename_checked=false
  local _sha_checked=false
  local _compatible=true
  local _hash_rc=0

  require_arg expectedCliVersion || { emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  _expected_cli="$MJ_REQUIRED_ARG_VALUE"
  require_arg expectedProtocolVersion || { emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  _expected_protocol="$MJ_REQUIRED_ARG_VALUE"

  if request_arg_present expectedFilename; then
    _expected_filename=$(request_arg_get expectedFilename)
    [ -n "$_expected_filename" ] || { set_error "INVALID_ARGUMENT" "expectedFilename may not be empty when supplied."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
    case "$_expected_filename" in */*) set_error "INVALID_ARGUMENT" "expectedFilename must be a filename, not a path."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65 ;; esac
    _filename_checked=true
  fi

  if request_arg_present expectedSha256; then
    _expected_sha=$(request_arg_get expectedSha256)
    _expected_sha_norm=$(printf '%s' "$_expected_sha" | /usr/bin/awk '{print tolower($0)}')
    case "$_expected_sha_norm" in *[!0-9a-f]*|'') set_error "INVALID_ARGUMENT" "expectedSha256 must be a 64-character hexadecimal SHA-256 digest."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65 ;; esac
    [ ${#_expected_sha_norm} -eq 64 ] || { set_error "INVALID_ARGUMENT" "expectedSha256 must be a 64-character hexadecimal SHA-256 digest."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
    _sha_checked=true
  fi

  _self=$(runtime_self_path) || { set_error "RUNTIME_PATH_UNAVAILABLE" "Could not resolve the running MographJailed runtime path."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 74; }
  _filename=${_self##*/}

  [ "$MOGRAPHJAILED_CLI_VERSION" = "$_expected_cli" ] && _cli_ok=true || _compatible=false
  [ "$MOGRAPHJAILED_PROTOCOL_VERSION" = "$_expected_protocol" ] && _protocol_ok=true || _compatible=false
  if $_filename_checked; then [ "$_filename" = "$_expected_filename" ] && _filename_ok=true || { _filename_ok=false; _compatible=false; }; fi

  if $_sha_checked; then
    [ -f "$_self" ] && [ -r "$_self" ] || { set_error "RUNTIME_PATH_UNAVAILABLE" "Running MographJailed runtime is not a readable regular file."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 74; }
    runtime_verify_hash "$_self"
    _hash_rc=$?
    if [ "$_hash_rc" -eq 69 ]; then
      set_error "UNSUPPORTED" "Runtime SHA-256 verification requires an approved native SHA-256 utility."
      emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"
      return 69
    elif [ "$_hash_rc" -ne 0 ]; then
      set_error "HASH_FAILED" "Could not calculate the MographJailed runtime SHA-256."
      emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"
      return 74
    fi
    _actual_sha="$MJ_HASH_VALUE"
    _hash_source="$MJ_HASH_SOURCE"
    [ "$_actual_sha" = "$_expected_sha_norm" ] && _sha_ok=true || { _sha_ok=false; _compatible=false; }
  fi

  emit_success_start "$REQUEST_COMMAND" "$REQUEST_ID"
  printf '{"compatible":'; runtime_bool_json "$_compatible"
  printf ',"actual":{"cliVersion":'; json_quote "$MOGRAPHJAILED_CLI_VERSION"
  printf ',"protocolVersion":%s' "$MOGRAPHJAILED_PROTOCOL_VERSION"
  printf ',"filename":'; json_quote "$_filename"
  printf ',"sha256":'; if $_sha_checked; then json_quote "$_actual_sha"; else printf 'null'; fi
  printf '}'
  printf ',"expected":{"cliVersion":'; json_quote "$_expected_cli"
  printf ',"protocolVersion":'; json_quote "$_expected_protocol"
  printf ',"filename":'; if $_filename_checked; then json_quote "$_expected_filename"; else printf 'null'; fi
  printf ',"sha256":'; if $_sha_checked; then json_quote "$_expected_sha_norm"; else printf 'null'; fi
  printf '}'
  printf ',"checks":{"cliVersion":'; runtime_bool_json "$_cli_ok"
  printf ',"protocolVersion":'; runtime_bool_json "$_protocol_ok"
  printf ',"filename":'; if $_filename_checked; then runtime_bool_json "$_filename_ok"; else printf 'null'; fi
  printf ',"sha256":'; if $_sha_checked; then runtime_bool_json "$_sha_ok"; else printf 'null'; fi
  printf '}'
  printf ',"hashSource":'; if $_sha_checked; then json_quote "$_hash_source"; else printf 'null'; fi
  printf ',"runtimePathDisclosure":"filename-only"}'
  emit_success_end
}
