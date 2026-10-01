print_help() {
  local _op=""
  printf 'mograph-jailed %s (protocol %s)\n\n' "$MOGRAPHJAILED_CLI_VERSION" "$MOGRAPHJAILED_PROTOCOL_VERSION"
  printf 'Usage:\n  mograph-jailed.zsh --request <request-file>   run one request, print one JSON response\n'
  printf '  mograph-jailed.zsh --help | --version\n\n'
  printf 'For everyday use, the `mj` shell command builds requests for you (docs/man/mj.md).\n'
  printf 'Request format: PROTOCOL.md. Error codes: docs/man/errors.md.\n\n'
  printf 'Exit codes: 0 ok, 64 usage, 65 bad request, 66 not found, 69 unsupported,\n'
  printf '            73 output problem, 74 operation failed, 77 permission denied\n\n'
  printf 'Operations:\n'
  while IFS= read -r _op; do
    [ -n "$_op" ] || continue
    printf '  %-18s %s\n' "$_op" "$(operation_summary "$_op")"
  done <<EOF_HELP_OPS
$(operation_names)
EOF_HELP_OPS
}

main() {
  local _rc=0
  case "${1:-}" in
    --help|-h) [ "$#" -eq 1 ] && { print_help; return 0; } ;;
    --version|-V) [ "$#" -eq 1 ] && { printf 'mograph-jailed %s (protocol %s)\n' "$MOGRAPHJAILED_CLI_VERSION" "$MOGRAPHJAILED_PROTOCOL_VERSION"; return 0; } ;;
  esac
  if [ "$#" -ne 2 ] || [ "$1" != "--request" ]; then
    set_error "USAGE" "Usage: mograph-jailed.zsh --request <request-file> (see --help)"
    emit_error_response "" ""
    return 64
  fi

  if ! load_request_file "$2"; then
    emit_error_response "${REQUEST_COMMAND:-}" "${REQUEST_ID:-}"
    audit_append 65
    return 65
  fi

  dispatch_request
  _rc=$?
  audit_append "$_rc"
  return "$_rc"
}

dispatch_request() {
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
    project.ingest) handle_project_ingest ;;
    expression.lint) handle_expression_lint ;;
    plugin.audit) handle_plugin_audit ;;
    project.snapshot) handle_project_snapshot ;;
    loop.seams) handle_loop_seams ;;
    golden.record) handle_golden_record ;;
    golden.check) handle_golden_check ;;
    audit.verify) handle_audit_verify ;;
    project.restore) handle_project_restore ;;
    deps.graph) handle_deps_graph ;;
    handoff.package) handle_handoff_package ;;
    index.add) handle_index_add ;;
    index.search) handle_index_search ;;
    index.verify) handle_index_verify ;;
    preset.add) handle_preset_add ;;
    preset.get) handle_preset_get ;;
    host.detect) handle_host_detect ;;
    ae.render) handle_ae_render ;;
    c4d.render) handle_c4d_render ;;
    trace.asset) handle_trace_asset ;;
    audit.plugins) handle_audit_plugins ;;
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
