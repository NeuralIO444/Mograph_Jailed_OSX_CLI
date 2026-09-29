# MJ Standard Library 1.0 — ImageKit foundation
# Reusable stock-sips inspection primitives. Mutation policy remains in public
# handlers so source images cannot be altered through a generic library API.

image_is_uint() {
  case "$1" in ''|*[!0-9]*) return 1 ;; *) return 0 ;; esac
}

sips_property() {
  local _key="$1"
  local _path="$2"
  local _out=""
  cap_available sips && cap_available awk || return 1
  _out=$(/usr/bin/sips -g "$_key" "$_path" 2>/dev/null) || return 1
  printf '%s\n' "$_out" | /usr/bin/awk -v k="$_key:" '$1==k { $1=""; sub(/^[[:space:]]+/,""); print; exit }'
}

image_positive_identification() {
  local _path="$1"
  local _format=""
  local _width=""
  local _height=""
  _format=$(sips_property format "$_path" 2>/dev/null || printf '')
  _width=$(sips_property pixelWidth "$_path" 2>/dev/null || printf '')
  _height=$(sips_property pixelHeight "$_path" 2>/dev/null || printf '')
  [ -n "$_format" ] || return 1
  image_is_uint "$_width" || return 1
  image_is_uint "$_height" || return 1
  [ "$_width" -gt 0 ] && [ "$_height" -gt 0 ]
}

image_emit_inspection_data() {
  local _path="$1"
  local _width=""
  local _height=""
  local _format=""
  local _space=""
  local _alpha=""
  local _alpha_json="null"
  _width=$(sips_property pixelWidth "$_path" 2>/dev/null || printf '')
  _height=$(sips_property pixelHeight "$_path" 2>/dev/null || printf '')
  _format=$(sips_property format "$_path" 2>/dev/null || printf '')
  _space=$(sips_property space "$_path" 2>/dev/null || printf '')
  _alpha=$(sips_property hasAlpha "$_path" 2>/dev/null || printf '')
  image_is_uint "$_width" || _width=""
  image_is_uint "$_height" || _height=""
  case "$(printf '%s' "$_alpha" | /usr/bin/awk '{print tolower($0)}')" in true|yes|1) _alpha_json=true ;; false|no|0) _alpha_json=false ;; esac
  printf '{"path":'; json_quote "$_path"
  printf ',"pixelWidth":'; [ -n "$_width" ] && printf '%s' "$_width" || printf 'null'
  printf ',"pixelHeight":'; [ -n "$_height" ] && printf '%s' "$_height" || printf 'null'
  printf ',"format":'; [ -n "$_format" ] && json_quote "$_format" || printf 'null'
  printf ',"colorSpace":'; [ -n "$_space" ] && json_quote "$_space" || printf 'null'
  printf ',"hasAlpha":%s,"source":"sips"}' "$_alpha_json"
}

standard_library_imagekit_available() {
  cap_available sips && cap_available awk
}
