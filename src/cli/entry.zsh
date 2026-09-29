main() {
  if [ "$#" -ne 2 ] || [ "$1" != "--request" ]; then
    set_error "USAGE" "Usage: mograph-jailed.zsh --request <request-file>"
    emit_error_response "" ""
    return 64
  fi

  if ! load_request_file "$2"; then
    emit_error_response "${REQUEST_COMMAND:-}" "${REQUEST_ID:-}"
    return 65
  fi

  case "$REQUEST_COMMAND" in
    system.probe) handle_system_probe ;;
    system.doctor) handle_system_doctor ;;
    system.describe) handle_system_describe ;;
    runtime.verify) handle_runtime_verify ;;
    file.inspect) handle_file_inspect ;;
    file.hash) handle_file_hash ;;
    file.provenance) handle_file_provenance ;;
    asset.manifest) handle_asset_manifest ;;
    asset.verify) handle_asset_verify ;;
    search.candidate) handle_search_candidate ;;
    image.inspect) handle_image_inspect ;;
    image.derivative) handle_image_derivative ;;
    image.stats) handle_image_stats ;;
    image.compare) handle_image_compare ;;
    storage.preflight) handle_storage_preflight ;;
    volume.inspect) handle_volume_inspect ;;
    temp.create) handle_temp_create ;;
    temp.clean) handle_temp_clean ;;
    media.inspect) handle_media_inspect ;;
    media.timing) handle_media_timing ;;
    media.frame) handle_media_frame ;;
    report.tech) handle_report_tech ;;
    package.create) handle_package_create ;;
    *)
      set_error "NOT_IMPLEMENTED" "Command is recognized by protocol but not implemented in this build."
      emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"
      return 69
      ;;
  esac
}

main "$@"
