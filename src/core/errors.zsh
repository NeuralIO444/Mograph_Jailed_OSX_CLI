MJ_ERR_CODE=""
MJ_ERR_MESSAGE=""

set_error() {
  MJ_ERR_CODE="$1"
  MJ_ERR_MESSAGE="$2"
}

emit_error_response() {
  local _cmd="$1"
  local _req="$2"
  printf '{'
  printf '"protocol":'; json_quote "$MOGRAPHJAILED_PROTOCOL"; printf ','
  printf '"protocolVersion":%s,' "$MOGRAPHJAILED_PROTOCOL_VERSION"
  printf '"cliVersion":'; json_quote "$MOGRAPHJAILED_CLI_VERSION"; printf ','
  printf '"requestId":'; json_quote "$_req"; printf ','
  printf '"command":'; json_quote "$_cmd"; printf ','
  printf '"ok":false,"data":null,"warnings":[],'
  printf '"error":{"code":'; json_quote "$MJ_ERR_CODE"; printf ',"message":'; json_quote "$MJ_ERR_MESSAGE"; printf '}'
  printf '}\n'
}
