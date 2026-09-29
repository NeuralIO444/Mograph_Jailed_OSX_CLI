# MJ Standard Library 1.0 descriptor shared by system.describe/report.tech.

emit_standard_library_descriptor() {
  local _localfs=false
  local _db=false
  local _db_json=false
  local _db_fts5=false
  local _db_version=""
  local _media=false
  local _image=false
  local _frame=false
  standard_library_localfs_available && _localfs=true
  if standard_library_nativedb_available; then
    _db=true
    [ "$MOGRAPHJAILED_DB_JSON" = "true" ] && _db_json=true
    [ "$MOGRAPHJAILED_DB_FTS5" = "true" ] && _db_fts5=true
    _db_version=$(native_db_version 2>/dev/null || printf '')
  fi
  standard_library_mediaprobe_available && _media=true
  standard_library_imagekit_available && _image=true
  standard_library_framekit_available && _frame=true

  printf '{"version":'; json_quote "$MOGRAPHJAILED_STANDARD_LIBRARY_VERSION"
  printf ',"policy":{"localOnlyByDefault":true,"networkMutation":false,"networkEnumeration":false,"arbitrarySqlAPI":false,"rawShellAPI":false}'
  printf ',"modules":{'
  printf '"LocalFS":{"available":'; $_localfs && printf 'true' || printf 'false'; printf ',"state":'; if $_localfs; then json_quote 'AVAILABLE'; else json_quote 'UNAVAILABLE'; fi; printf ',"authority":"FILESYSTEM_SCOPE"}'
  printf ',"NativeDB":{"available":'; $_db && printf 'true' || printf 'false'; printf ',"state":'; if $_db; then json_quote 'AVAILABLE'; else json_quote 'UNAVAILABLE'; fi; printf ',"authority":"LOCAL_STRUCTURED_STORAGE","publicSql":false,"version":'; [ -n "$_db_version" ] && json_quote "$_db_version" || printf 'null'; printf ',"features":{"json":'; $_db_json && printf 'true' || printf 'false'; printf ',"fts5":'; $_db_fts5 && printf 'true' || printf 'false'; printf '}}'
  printf ',"MediaProbe":{"available":'; $_media && printf 'true' || printf 'false'; printf ',"state":'; if $_media; then json_quote 'AVAILABLE'; else json_quote 'UNAVAILABLE'; fi; printf ',"authority":"NORMALIZED_NATIVE_MEDIA"}'
  printf ',"ImageKit":{"available":'; $_image && printf 'true' || printf 'false'; printf ',"state":'; if $_image; then json_quote 'AVAILABLE'; else json_quote 'UNAVAILABLE'; fi; printf ',"authority":"NATIVE_IMAGE"}'
  printf ',"FrameKit":{"available":'; $_frame && printf 'true' || printf 'false'; printf ',"state":'; if $_frame; then json_quote 'AVAILABLE_CANDIDATE'; else json_quote 'UNAVAILABLE'; fi; printf ',"authority":"NATIVE_FRAME_DERIVATIVE","executionScope":"LOCAL_ONLY","exactRequest":true,"trackTransform":true,"publicGenericJXA":false,"targetMacQualificationRequired":true}'
  printf '}}'
}
