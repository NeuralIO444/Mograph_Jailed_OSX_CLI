emit_success_start() {
  local _cmd="$1"
  local _req="$2"
  printf '{'
  printf '"protocol":'; json_quote "$MOGRAPHJAILED_PROTOCOL"; printf ','
  printf '"protocolVersion":%s,' "$MOGRAPHJAILED_PROTOCOL_VERSION"
  printf '"cliVersion":'; json_quote "$MOGRAPHJAILED_CLI_VERSION"; printf ','
  printf '"requestId":'; json_quote "$_req"; printf ','
  printf '"command":'; json_quote "$_cmd"; printf ','
  printf '"ok":true,"data":'
}

emit_success_end() {
  printf ',"warnings":[],"error":null}\n'
}
