mdls_raw_value() {
  local _key="$1"
  local _path="$2"
  local _value=""
  cap_available mdls || return 1
  _value=$(/usr/bin/mdls -raw -name "$_key" "$_path" 2>/dev/null) || return 1
  case "$_value" in '(null)'|'null'|'') return 1 ;; esac
  printf '%s' "$_value"
}

is_number() {
  printf '%s\n' "$1" | /usr/bin/awk 'BEGIN{ok=0} /^[0-9]+([.][0-9]+)?$/ {ok=1} END{exit ok?0:1}'
}

is_integer() {
  case "$1" in ''|*[!0-9]*) return 1 ;; *) return 0 ;; esac
}

handle_media_inspect() {
  local _path=""
  local _native_probe="unavailable"
  local _size=""
  local _basic=""
  local _duration=""
  local _width=""
  local _height=""
  local _content=""
  local _mdls=false

  require_arg path || { emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  _path="$MJ_REQUIRED_ARG_VALUE"
  is_absolute_path "$_path" || { set_error "INVALID_PATH" "Path must be absolute."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  [ -e "$_path" ] || { set_error "NOT_FOUND" "Media path does not exist."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 66; }
  [ -f "$_path" ] || { set_error "INVALID_TARGET" "Media target must be a regular file."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  [ -r "$_path" ] || { set_error "PERMISSION_DENIED" "Media file is not readable."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 77; }
  cap_available stat && cap_available file && cap_available uname || { set_error "UNSUPPORTED" "Media inspection requires stock macOS stat/file/uname capabilities."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 69; }

  # V0.1 does not execute avmediainfo during the default inspection path.
  # It has no documented stable machine-readable output schema and adds
  # synchronous work, especially on network media. Availability is reported
  # separately so future explicit diagnostic operations can opt in.
  if cap_available avmediainfo; then
    _native_probe="notRun"
  fi

  _size=$(file_stat_size "$_path" || printf '')
  _basic=$(file_basic_type "$_path")
  if cap_available mdls; then
    _duration=$(mdls_raw_value kMDItemDurationSeconds "$_path" 2>/dev/null || printf '')
    _width=$(mdls_raw_value kMDItemPixelWidth "$_path" 2>/dev/null || printf '')
    _height=$(mdls_raw_value kMDItemPixelHeight "$_path" 2>/dev/null || printf '')
    _content=$(mdls_raw_value kMDItemContentType "$_path" 2>/dev/null || printf '')
    if [ -n "$_duration$_width$_height$_content" ]; then _mdls=true; fi
  fi

  is_number "$_duration" 2>/dev/null || _duration=""
  is_integer "$_width" 2>/dev/null || _width=""
  is_integer "$_height" 2>/dev/null || _height=""

  emit_success_start "$REQUEST_COMMAND" "$REQUEST_ID"
  printf '{"path":'; json_quote "$_path"
  printf ',"sizeBytes":'; [ -n "$_size" ] && printf '%s' "$_size" || printf 'null'
  printf ',"basicType":'; json_quote "$_basic"
  printf ',"durationSeconds":'; [ -n "$_duration" ] && printf '%s' "$_duration" || printf 'null'
  printf ',"pixelWidth":'; [ -n "$_width" ] && printf '%s' "$_width" || printf 'null'
  printf ',"pixelHeight":'; [ -n "$_height" ] && printf '%s' "$_height" || printf 'null'
  printf ',"contentType":'; if [ -n "$_content" ]; then json_quote "$_content"; else printf 'null'; fi
  printf ',"nativeProbe":'; json_quote "$_native_probe"
  printf ',"metadata":{"mdlsAdvisory":'; $_mdls && printf 'true' || printf 'false'
  printf ',"avmediainfoAvailable":'; cap_available avmediainfo && printf 'true' || printf 'false'
  printf '},"sources":{"filesystem":["stat","file"],"duration":'; if [ -n "$_duration" ]; then printf '"mdls"'; else printf 'null'; fi
  printf ',"dimensions":'; if [ -n "$_width" ] || [ -n "$_height" ]; then printf '"mdls"'; else printf 'null'; fi
  printf '},"advisory":{"durationSeconds":true,"pixelDimensions":true,"nativeProbe":true}}'
  emit_success_end
}

handle_media_timing() {
  local _path=""
  local _fs=""
  local _class="unknown"
  local _enabled="null"
  local _decode="null"
  local _reorder="null"

  require_arg path || { emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  _path="$MJ_REQUIRED_ARG_VALUE"
  is_absolute_path "$_path" || { set_error "INVALID_PATH" "Path must be absolute."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  [ -f "$_path" ] || { set_error "NOT_FOUND" "Media file does not exist."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 66; }
  [ -r "$_path" ] || { set_error "PERMISSION_DENIED" "Media file is not readable."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 77; }

  if ! standard_library_mediaprobe_available; then
    set_error "UNSUPPORTED" "Structured media timing requires the Standard Library MediaProbe adapter and stock avmediainfo/awk/df/uname capabilities."
    emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"
    return 69
  fi

  # Standard Library 1.0 timing is intentionally local-only. Network volumes
  # are detected but never inspected by this bounded media path.
  if ! mj_require_local_existing_path "$_path"; then
    emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"
    return 73
  fi
  _fs="$MJ_LOCAL_SCOPE_FS"
  _class="$MJ_LOCAL_SCOPE_CLASS"

  if ! media_probe_read_timing "$_path"; then
    set_error "NATIVE_OUTPUT_INVALID" "avmediainfo did not return the bounded labeled timing shape required by MediaProbe."
    emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"
    return 74
  fi

  case "$MJ_MEDIA_VIDEO_ENABLED" in true) _enabled=true ;; false) _enabled=false ;; esac
  case "$MJ_MEDIA_VIDEO_DECODE_SUPPORTED" in true) _decode=true ;; false) _decode=false ;; esac
  case "$MJ_MEDIA_VIDEO_REORDERING" in true) _reorder=true ;; false) _reorder=false ;; esac

  emit_success_start "$REQUEST_COMMAND" "$REQUEST_ID"
  printf '{"schema":"MJ_MEDIA_TIMING_2","path":'; json_quote "$_path"
  printf ',"source":"avmediainfo","adapter":"MJ_MEDIAPROBE_AVMEDIAINFO_TEXT_1","bounded":true'
  printf ',"scope":{"filesystem":'; [ -n "$_fs" ] && json_quote "$_fs" || printf 'null'; printf ',"classification":'; json_quote "$_class"; printf ',"policy":"LOCAL_ONLY"}'
  printf ',"duration":{"seconds":%s,"rational":' "$MJ_MEDIA_DURATION_SECONDS"
  if [ -n "$MJ_MEDIA_DURATION_VALUE" ] && [ -n "$MJ_MEDIA_DURATION_TIMESCALE" ]; then
    printf '{"value":%s,"timescale":%s}' "$MJ_MEDIA_DURATION_VALUE" "$MJ_MEDIA_DURATION_TIMESCALE"
  else
    printf 'null'
  fi
  printf '}'
  printf ',"trackCount":%s' "$MJ_MEDIA_TRACK_COUNT"
  printf ',"video":{"trackCount":%s,"selected":' "$MJ_MEDIA_VIDEO_TRACK_COUNT"
  if [ "$MJ_MEDIA_VIDEO_TRACK_COUNT" -gt 0 ]; then
    printf '{"index":%s,"enabled":%s' "$MJ_MEDIA_VIDEO_TRACK_INDEX" "$_enabled"
    printf ',"codec":'; json_quote "$MJ_MEDIA_VIDEO_CODEC"
    printf ',"fourCC":'; [ -n "$MJ_MEDIA_VIDEO_FOURCC" ] && json_quote "$MJ_MEDIA_VIDEO_FOURCC" || printf 'null'
    printf ',"pixelWidth":%s,"pixelHeight":%s' "$MJ_MEDIA_VIDEO_WIDTH" "$MJ_MEDIA_VIDEO_HEIGHT"
    printf ',"systemDecodeSupported":%s' "$_decode"
    printf ',"dataBytes":'; [ -n "$MJ_MEDIA_VIDEO_DATA_BYTES" ] && printf '%s' "$MJ_MEDIA_VIDEO_DATA_BYTES" || printf 'null'
    printf ',"mediaTimeScale":%s' "$MJ_MEDIA_VIDEO_TIMESCALE"
    printf ',"durationSeconds":%s' "$MJ_MEDIA_VIDEO_DURATION_SECONDS"
    printf ',"nominalFrameRate":%s' "$MJ_MEDIA_VIDEO_NOMINAL_FPS"
    printf ',"minimumSampleDuration":'
    if [ -n "$MJ_MEDIA_VIDEO_MIN_SAMPLE_VALUE" ] && [ -n "$MJ_MEDIA_VIDEO_MIN_SAMPLE_TIMESCALE" ]; then
      printf '{"value":%s,"timescale":%s}' "$MJ_MEDIA_VIDEO_MIN_SAMPLE_VALUE" "$MJ_MEDIA_VIDEO_MIN_SAMPLE_TIMESCALE"
    else
      printf 'null'
    fi
    printf ',"frameReorderingRequired":%s}' "$_reorder"
  else
    printf 'null'
  fi
  printf '}'
  printf ',"sampleTableEnumerated":false'
  printf ',"authority":{"duration":"NATIVE_MEDIA_HEADER","trackTiming":"NATIVE_MEDIA_HEADER","nominalFrameRate":"ADVISORY_NOMINAL"}'
  printf ',"notes":["Default timing is header-bounded; exact per-sample enumeration remains a future explicit operation."]}'
  emit_success_end
}

handle_media_frame() {
  local _path=""
  local _output=""
  local _time=""
  local _max="2048"
  local _parent=""
  local _parent_real=""
  local _leaf=""
  local _out_real=""
  local _stage=""
  local _stage_file=""
  local _stage_prefix="MographJailed_Frame"
  local _before=""
  local _after=""
  local _delta=""
  local _size=""
  local _out_width=""
  local _out_height=""

  require_arg path || { emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }; _path="$MJ_REQUIRED_ARG_VALUE"
  require_arg output || { emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }; _output="$MJ_REQUIRED_ARG_VALUE"
  require_arg timeSeconds || { emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }; _time="$MJ_REQUIRED_ARG_VALUE"
  if request_arg_present maxPixels; then _max=$(request_arg_get maxPixels); fi

  is_absolute_path "$_path" && is_absolute_path "$_output" || { set_error "INVALID_PATH" "Media source and frame output paths must be absolute."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  [ -f "$_path" ] && [ -r "$_path" ] || { set_error "INVALID_TARGET" "Frame source must be a readable regular media file."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  frame_kit_is_time_seconds "$_time" || { set_error "INVALID_ARGUMENT" "timeSeconds must be a non-negative decimal number."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  frame_kit_is_max_pixels "$_max" || { set_error "INVALID_ARGUMENT" "maxPixels must be an integer from 64 through 4096."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  case "$_output" in *.png|*.PNG) ;; *) set_error "INVALID_OUTPUT" "FrameKit output must be a .png file."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65 ;; esac

  standard_library_framekit_available || { set_error "UNSUPPORTED" "FrameKit requires the qualified local JXA/AVFoundation, MediaProbe, ImageKit, jq, and LocalFS capabilities."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 69; }
  if ! mj_require_local_existing_path "$_path"; then emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 73; fi

  _parent=$(parent_path "$_output")
  [ -d "$_parent" ] && [ -w "$_parent" ] || { set_error "OUTPUT_UNAVAILABLE" "Frame output directory is unavailable or not writable."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 73; }
  _parent_real=$(canonical_existing_dir "$_parent") || { set_error "OUTPUT_UNAVAILABLE" "Could not resolve frame output directory."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 73; }
  if ! mj_require_local_existing_path "$_parent_real"; then emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 73; fi
  _leaf=${_output##*/}; _out_real="$_parent_real/$_leaf"
  [ ! -e "$_out_real" ] && [ ! -L "$_out_real" ] || { set_error "OUTPUT_EXISTS" "Refusing to overwrite an existing frame derivative."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 73; }

  if ! media_probe_read_timing "$_path"; then
    set_error "NATIVE_OUTPUT_INVALID" "MediaProbe could not establish bounded video timing before frame extraction."
    emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"
    return 74
  fi
  [ "$MJ_MEDIA_VIDEO_TRACK_COUNT" -gt 0 ] || { set_error "NO_VIDEO_TRACK" "Frame extraction requires at least one video track."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  [ "$MJ_MEDIA_VIDEO_DECODE_SUPPORTED" != "false" ] || { set_error "DECODE_UNSUPPORTED" "macOS reports that the selected video track is not decodable."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 69; }
  frame_kit_time_before_duration "$_time" "$MJ_MEDIA_DURATION_SECONDS" || { set_error "TIME_OUT_OF_RANGE" "Requested frame time must be within the media duration."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }

  _before=$(file_hash_identity "$_path") || { set_error "SOURCE_STATE_UNAVAILABLE" "Could not establish media source identity before frame extraction."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 74; }
  create_mj_stage_dir "$_parent_real" "$_stage_prefix" || { set_error "TEMP_CREATE_FAILED" "Could not create and bind FrameKit staging directory."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 73; }
  _stage="$MJ_STAGE_DIR"
  _stage_file="$_stage/frame.png"

  if ! frame_kit_extract_png "$_path" "$_stage_file" "$_time" "$MJ_MEDIA_VIDEO_TIMESCALE" "$_max"; then
    cleanup_mj_stage_dir "$_stage" "$_parent_real" "$_stage_prefix" || { set_error "STAGE_CLEANUP_REFUSED" "Frame extraction failed and staging cleanup could not be proven safe."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 74; }
    if [ -n "$MJ_FRAMEKIT_ERROR_MESSAGE" ]; then
      set_error "FRAME_EXTRACTION_FAILED" "$MJ_FRAMEKIT_ERROR_MESSAGE"
    else
      set_error "FRAME_EXTRACTION_FAILED" "Native AVFoundation frame extraction failed."
    fi
    emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"
    return 74
  fi

  _after=$(file_hash_identity "$_path") || {
    cleanup_mj_stage_dir "$_stage" "$_parent_real" "$_stage_prefix" || { set_error "STAGE_CLEANUP_REFUSED" "Frame source state failed and staging cleanup was refused."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 74; }
    set_error "SOURCE_CHANGED" "Media source state could not be re-established after frame extraction."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 74;
  }
  [ "$_before" = "$_after" ] || {
    cleanup_mj_stage_dir "$_stage" "$_parent_real" "$_stage_prefix" || { set_error "STAGE_CLEANUP_REFUSED" "Media source changed and staging cleanup was refused."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 74; }
    set_error "SOURCE_CHANGED" "Media source changed while FrameKit was decoding it."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 74;
  }

  _out_width=$(sips_property pixelWidth "$_stage_file" 2>/dev/null || printf '')
  _out_height=$(sips_property pixelHeight "$_stage_file" 2>/dev/null || printf '')
  [ "$_out_width" = "$MJ_FRAMEKIT_PIXEL_WIDTH" ] && [ "$_out_height" = "$MJ_FRAMEKIT_PIXEL_HEIGHT" ] || {
    cleanup_mj_stage_dir "$_stage" "$_parent_real" "$_stage_prefix" || { set_error "STAGE_CLEANUP_REFUSED" "Frame validation failed and staging cleanup was refused."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 74; }
    set_error "FRAME_VALIDATION_FAILED" "Generated PNG dimensions did not match AVFoundation frame metadata."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 74;
  }

  if ! /bin/mv -n "$_stage_file" "$_out_real" 2>/dev/null; then
    cleanup_mj_stage_dir "$_stage" "$_parent_real" "$_stage_prefix" || { set_error "STAGE_CLEANUP_REFUSED" "Frame publish failed and staging cleanup was refused."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 74; }
    set_error "FRAME_PUBLISH_FAILED" "Could not publish the frame derivative without overwrite."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 74
  fi
  if [ -e "$_stage_file" ] || [ -L "$_stage_file" ]; then
    cleanup_mj_stage_dir "$_stage" "$_parent_real" "$_stage_prefix" || { set_error "STAGE_CLEANUP_REFUSED" "Frame output appeared concurrently and staging cleanup was refused."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 74; }
    set_error "OUTPUT_EXISTS" "Frame output appeared during extraction; refusing overwrite."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 73
  fi
  cleanup_mj_stage_dir "$_stage" "$_parent_real" "$_stage_prefix" || { set_error "STAGE_CLEANUP_REFUSED" "Published frame but could not prove staging ownership for cleanup."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 74; }
  [ -f "$_out_real" ] || { set_error "FRAME_PUBLISH_FAILED" "Frame output was not created."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 74; }

  _size=$(file_stat_size "$_out_real" 2>/dev/null || printf '')
  _delta=$(MJ_FRAMEKIT_REQ="$MJ_FRAMEKIT_REQUESTED_SECONDS" MJ_FRAMEKIT_ACT="$MJ_FRAMEKIT_ACTUAL_SECONDS" /usr/bin/awk 'BEGIN { printf "%.9f", (ENVIRON["MJ_FRAMEKIT_ACT"]+0)-(ENVIRON["MJ_FRAMEKIT_REQ"]+0) }')

  emit_success_start "$REQUEST_COMMAND" "$REQUEST_ID"
  printf '{"schema":"MJ_MEDIA_FRAME_1","source":'; json_quote "$_path"
  printf ',"output":'; json_quote "$_output"; printf ',"resolvedOutput":'; json_quote "$_out_real"
  printf ',"format":"png","maxPixels":%s,"sizeBytes":' "$_max"; [ -n "$_size" ] && printf '%s' "$_size" || printf 'null'
  printf ',"requestedTime":{"seconds":%s,"timescale":%s}' "$MJ_FRAMEKIT_REQUESTED_SECONDS" "$MJ_MEDIA_VIDEO_TIMESCALE"
  printf ',"actualTime":{"seconds":%s,"value":%s,"timescale":%s}' "$MJ_FRAMEKIT_ACTUAL_SECONDS" "$MJ_FRAMEKIT_ACTUAL_VALUE" "$MJ_FRAMEKIT_ACTUAL_TIMESCALE"
  printf ',"deltaSeconds":%s' "$_delta"
  printf ',"pixelWidth":%s,"pixelHeight":%s' "$MJ_FRAMEKIT_PIXEL_WIDTH" "$MJ_FRAMEKIT_PIXEL_HEIGHT"
  printf ',"frameAccurateRequest":true,"toleranceBeforeSeconds":0,"toleranceAfterSeconds":0,"preferredTrackTransformApplied":true'
  printf ',"sourceUnchanged":true,"scope":{"classification":"local","policy":"LOCAL_ONLY"}'
  printf ',"adapter":"JXA_AVAssetImageGenerator_COMPAT_1"'
  printf ',"notes":["FrameKit requests zero AVFoundation time tolerance. actualTime is reported independently and must be used by consumers for verification.","The JXA adapter isolates the deprecated synchronous Objective-C compatibility API behind the stable media.frame contract."]}'
  emit_success_end
}
