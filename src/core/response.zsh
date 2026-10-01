# Warnings are real: handlers call add_warning, or (for operations backed by a Python
# engine) return a reserved `_warnings` list in their data that split_warnings lifts out.
MJ_WARNINGS=""
MJ_DATA_JSON=""

# add_warning <CODE> <message>
add_warning() {
  local _item="{\"code\":$(json_quote "$1"),\"message\":$(json_quote "$2")}"
  MJ_WARNINGS="${MJ_WARNINGS:+$MJ_WARNINGS,}$_item"
}

# split_warnings <data-json>: sets MJ_DATA_JSON (data without `_warnings`) and appends the
# warnings. If the JSON cannot be split, the data is passed through unchanged.
split_warnings() {
  local _out="" _w=""
  MJ_DATA_JSON="$1"
  _out=$(printf '%s' "$1" | /usr/bin/python3 -c '
import json, sys
d = json.load(sys.stdin)
ws = d.pop("_warnings", []) if isinstance(d, dict) else []
print(",".join(json.dumps({"code": str(w["code"]), "message": str(w["message"])}) for w in ws if isinstance(w, dict) and "code" in w and "message" in w))
print(json.dumps(d, sort_keys=True, separators=(",", ":")))
' 2>/dev/null) || return 0
  { IFS= read -r _w; IFS= read -r MJ_DATA_JSON; } <<EOF_SPLIT
$_out
EOF_SPLIT
  [ -z "$_w" ] || MJ_WARNINGS="${MJ_WARNINGS:+$MJ_WARNINGS,}$_w"
}

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
  printf ',"warnings":[%s],"error":null}\n' "$MJ_WARNINGS"
}
