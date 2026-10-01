# Reusable image primitives live in src/lib/image_kit.zsh.

handle_image_inspect() {
  local _path=""
  require_arg path || { emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  _path="$MJ_REQUIRED_ARG_VALUE"
  is_absolute_path "$_path" || { set_error "INVALID_PATH" "Path must be absolute."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  [ -f "$_path" ] || { set_error "INVALID_TARGET" "Image target must be a regular file."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  [ -r "$_path" ] || { set_error "PERMISSION_DENIED" "Image is not readable."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 77; }
  cap_available sips && cap_available awk || { set_error "UNSUPPORTED" "Image inspection requires stock macOS sips/awk capabilities."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 69; }
  image_positive_identification "$_path" || { set_error "INVALID_TARGET" "sips did not positively identify the target as a raster image."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }

  emit_success_start "$REQUEST_COMMAND" "$REQUEST_ID"
  image_emit_inspection_data "$_path"
  emit_success_end
}

handle_image_derivative() {
  local _input=""
  local _output=""
  local _max=""
  local _parent=""
  local _parent_real=""
  local _leaf=""
  local _out_real=""
  local _stage=""
  local _stage_file=""
  local _stage_prefix="MographJailed_Image"
  local _before=""
  local _after=""
  local _size=""

  require_arg input || { emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }; _input="$MJ_REQUIRED_ARG_VALUE"
  require_arg output || { emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }; _output="$MJ_REQUIRED_ARG_VALUE"
  require_arg target || { emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }; _max="$MJ_REQUIRED_ARG_VALUE"
  is_absolute_path "$_input" && is_absolute_path "$_output" || { set_error "INVALID_PATH" "Input and output paths must be absolute."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  [ -f "$_input" ] && [ -r "$_input" ] || { set_error "INVALID_TARGET" "Image derivative input must be a readable regular file."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  image_is_uint "$_max" || { set_error "INVALID_ARGUMENT" "Image derivative target must be an integer pixel bound."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  [ ${#_max} -le 4 ] || { set_error "INVALID_ARGUMENT" "Image derivative target exceeds the supported integer range."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  [ "$_max" -ge 16 ] && [ "$_max" -le 4096 ] || { set_error "INVALID_ARGUMENT" "Image derivative target must be between 16 and 4096 pixels."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  case "$_output" in *.png|*.PNG) ;; *) set_error "INVALID_OUTPUT" "Image derivative output must be a .png file."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65 ;; esac
  cap_available sips && cap_available awk && cap_available mktemp && cap_available mv && cap_available rm && cap_available stat && cap_available uname || { set_error "UNSUPPORTED" "Image derivative requires stock macOS sips/awk/mktemp/mv/rm/stat/uname capabilities."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 69; }
  image_positive_identification "$_input" || { set_error "INVALID_TARGET" "sips did not positively identify the derivative input as a raster image."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }

  _parent=$(parent_path "$_output")
  [ -d "$_parent" ] && [ -w "$_parent" ] || { set_error "OUTPUT_UNAVAILABLE" "Image derivative output directory is unavailable or not writable."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 73; }
  _parent_real=$(canonical_existing_dir "$_parent") || { set_error "OUTPUT_UNAVAILABLE" "Could not resolve image derivative output directory."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 73; }
  _leaf=${_output##*/}; _out_real="$_parent_real/$_leaf"
  [ ! -e "$_out_real" ] && [ ! -L "$_out_real" ] || { set_error "OUTPUT_EXISTS" "Refusing to overwrite an existing image derivative."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 73; }
  _before=$(file_hash_identity "$_input") || { set_error "SOURCE_STATE_UNAVAILABLE" "Could not establish image source identity."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 74; }

  create_mj_stage_dir "$_parent_real" "$_stage_prefix" || { set_error "TEMP_CREATE_FAILED" "Could not create and bind image derivative staging directory."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 73; }
  _stage="$MJ_STAGE_DIR"
  _stage_file="$_stage/derivative.png"
  if ! /usr/bin/sips -s format png -Z "$_max" "$_input" --out "$_stage_file" >/dev/null 2>&1; then
    cleanup_mj_stage_dir "$_stage" "$_parent_real" "$_stage_prefix" || { set_error "STAGE_CLEANUP_REFUSED" "Image derivative failed and its staging directory could not be proven safe for cleanup."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 74; }
    set_error "IMAGE_DERIVATIVE_FAILED" "Native image derivative creation failed."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 74
  fi
  _after=$(file_hash_identity "$_input") || {
    cleanup_mj_stage_dir "$_stage" "$_parent_real" "$_stage_prefix" || { set_error "STAGE_CLEANUP_REFUSED" "Image source state failed and staging cleanup was refused."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 74; }
    set_error "SOURCE_CHANGED" "Image source state could not be re-established after derivative creation."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 74;
  }
  [ "$_before" = "$_after" ] || {
    cleanup_mj_stage_dir "$_stage" "$_parent_real" "$_stage_prefix" || { set_error "STAGE_CLEANUP_REFUSED" "Image source changed and staging cleanup was refused."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 74; }
    set_error "SOURCE_CHANGED" "Image source changed while derivative was being created."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 74;
  }
  if ! /bin/mv -n "$_stage_file" "$_out_real" 2>/dev/null; then
    cleanup_mj_stage_dir "$_stage" "$_parent_real" "$_stage_prefix" || { set_error "STAGE_CLEANUP_REFUSED" "Image publish failed and staging cleanup was refused."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 74; }
    set_error "IMAGE_DERIVATIVE_FAILED" "Could not publish image derivative."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 74
  fi
  if [ -e "$_stage_file" ] || [ -L "$_stage_file" ]; then
    cleanup_mj_stage_dir "$_stage" "$_parent_real" "$_stage_prefix" || { set_error "STAGE_CLEANUP_REFUSED" "Image output appeared concurrently and staging cleanup was refused."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 74; }
    set_error "OUTPUT_EXISTS" "Image derivative output appeared during creation; refusing overwrite."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 73
  fi
  cleanup_mj_stage_dir "$_stage" "$_parent_real" "$_stage_prefix" || { set_error "STAGE_CLEANUP_REFUSED" "Published image derivative but could not prove staging ownership for cleanup."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 74; }
  [ -f "$_out_real" ] || { set_error "IMAGE_DERIVATIVE_FAILED" "Image derivative output was not created."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 74; }
  _size=$(file_stat_size "$_out_real" 2>/dev/null || printf '')

  emit_success_start "$REQUEST_COMMAND" "$REQUEST_ID"
  printf '{"source":'; json_quote "$_input"; printf ',"output":'; json_quote "$_output"; printf ',"resolvedOutput":'; json_quote "$_out_real"
  printf ',"maxPixels":%s,"format":"png","sizeBytes":' "$_max"; [ -n "$_size" ] && printf '%s' "$_size" || printf 'null'
  printf ',"sourceUnchanged":true,"inspection":'; image_emit_inspection_data "$_out_real"; printf '}'
  emit_success_end
}

handle_image_stats() {
  local _path=""
  local _id0=""
  local _stats_json=""
  local _width=""
  local _height=""
  local _histogram=""
  local _grid=""

  require_arg path || { emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  _path="$MJ_REQUIRED_ARG_VALUE"
  _id0=$(source_identity "$_path")
  is_absolute_path "$_path" || { set_error "INVALID_PATH" "Path must be absolute."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  [ -f "$_path" ] || { set_error "INVALID_TARGET" "Image stats target must be a regular file."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  [ -r "$_path" ] || { set_error "PERMISSION_DENIED" "Image is not readable."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 77; }
  image_stats_available || { set_error "UNSUPPORTED" "Image stats requires stock macOS python3/sips/awk capabilities."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 69; }
  image_positive_identification "$_path" || { set_error "INVALID_TARGET" "sips did not positively identify the target as a raster image."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }

  _stats_json=$(image_stats_compute "$_path") || { set_error "STATS_FAILED" "Image stats computation failed (PNG decode or histogram)."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 74; }
  # Validate the Python output is ok
  case "$_stats_json" in
    *'"ok": true'*|*'"ok":true'*) ;;
    *) set_error "STATS_FAILED" "Image stats engine returned an error."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 74 ;;
  esac

  _width=$(printf '%s' "$_stats_json" | /usr/bin/python3 -c "import json,sys; print(json.load(sys.stdin)['width'])")
  _height=$(printf '%s' "$_stats_json" | /usr/bin/python3 -c "import json,sys; print(json.load(sys.stdin)['height'])")
  _histogram=$(printf '%s' "$_stats_json" | /usr/bin/python3 -c "import json,sys; print(json.dumps(json.load(sys.stdin)['histogram']))")
  _grid=$(printf '%s' "$_stats_json" | /usr/bin/python3 -c "import json,sys; print(json.dumps(json.load(sys.stdin)['gridAverages']))")

  emit_success_start "$REQUEST_COMMAND" "$REQUEST_ID"
  printf '{"schema":"MJ_IMAGE_STATS_1","path":'; json_quote "$_path"
  printf ',"pixelWidth":%s,"pixelHeight":%s' "$_width" "$_height"
  printf ',"histogramBins":64,"histogram":%s' "$_histogram"
  printf ',"gridSize":8,"gridAverages":%s' "$_grid"
  printf ',"sourceUnchanged":%s}' "$(source_unchanged_json "$_id0" "$_path")"
  emit_success_end
}

handle_image_compare() {
  local _path_a=""
  local _id0a=""
  local _id0b=""
  local _path_b=""
  local _stats_a=""
  local _stats_b=""
  local _hist_a=""
  local _grid_a=""
  local _hist_b=""
  local _grid_b=""
  local _compare_json=""
  local _score=""
  local _hist_sim=""
  local _grid_sim=""

  require_arg pathA || { emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  _path_a="$MJ_REQUIRED_ARG_VALUE"
  require_arg pathB || { emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  _path_b="$MJ_REQUIRED_ARG_VALUE"
  _id0a=$(source_identity "$_path_a"); _id0b=$(source_identity "$_path_b")

  for _p in "$_path_a" "$_path_b"; do
    is_absolute_path "$_p" || { set_error "INVALID_PATH" "Paths must be absolute."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
    [ -f "$_p" ] || { set_error "INVALID_TARGET" "Image compare targets must be regular files."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
    [ -r "$_p" ] || { set_error "PERMISSION_DENIED" "Image is not readable."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 77; }
    image_positive_identification "$_p" || { set_error "INVALID_TARGET" "sips did not positively identify the target as a raster image."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  done

  image_stats_available || { set_error "UNSUPPORTED" "Image compare requires stock macOS python3/sips/awk capabilities."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 69; }

  _stats_a=$(image_stats_compute "$_path_a") || { set_error "STATS_FAILED" "Image stats computation failed for first image."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 74; }
  _stats_b=$(image_stats_compute "$_path_b") || { set_error "STATS_FAILED" "Image stats computation failed for second image."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 74; }

  _hist_a=$(printf '%s' "$_stats_a" | /usr/bin/python3 -c "import json,sys; print(json.dumps(json.load(sys.stdin)['histogram']))")
  _grid_a=$(printf '%s' "$_stats_a" | /usr/bin/python3 -c "import json,sys; print(json.dumps(json.load(sys.stdin)['gridAverages']))")
  _hist_b=$(printf '%s' "$_stats_b" | /usr/bin/python3 -c "import json,sys; print(json.dumps(json.load(sys.stdin)['histogram']))")
  _grid_b=$(printf '%s' "$_stats_b" | /usr/bin/python3 -c "import json,sys; print(json.dumps(json.load(sys.stdin)['gridAverages']))")

  _compare_json=$(image_stats_compare "$_hist_a" "$_grid_a" "$_hist_b" "$_grid_b") || { set_error "COMPARE_FAILED" "Image similarity computation failed."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 74; }
  case "$_compare_json" in
    *'"ok": true'*|*'"ok":true'*) ;;
    *) set_error "COMPARE_FAILED" "Image compare engine returned an error."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 74 ;;
  esac

  _score=$(printf '%s' "$_compare_json" | /usr/bin/python3 -c "import json,sys; print(json.load(sys.stdin)['score'])")
  _hist_sim=$(printf '%s' "$_compare_json" | /usr/bin/python3 -c "import json,sys; print(json.load(sys.stdin)['histogramSimilarity'])")
  _grid_sim=$(printf '%s' "$_compare_json" | /usr/bin/python3 -c "import json,sys; print(json.load(sys.stdin)['gridSimilarity'])")

  emit_success_start "$REQUEST_COMMAND" "$REQUEST_ID"
  printf '{"schema":"MJ_IMAGE_COMPARE_1","pathA":'; json_quote "$_path_a"
  printf ',"pathB":'; json_quote "$_path_b"
  printf ',"score":%s,"histogramSimilarity":%s,"gridSimilarity":%s' "$_score" "$_hist_sim" "$_grid_sim"
  if [ "$(source_unchanged_json "$_id0a" "$_path_a")" = true ] && [ "$(source_unchanged_json "$_id0b" "$_path_b")" = true ]; then printf ',"sourceUnchanged":true}'; else printf ',"sourceUnchanged":false}'; fi
  emit_success_end
}
