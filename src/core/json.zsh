json_quote() {
  # JSON-quote one shell string in pure zsh (no process): backslash and quote escaped, ASCII controls
  # below 0x20 escaped (\b \f \n \r \t by name, others \u00XX); all other bytes, Unicode included, as is.
  setopt localoptions nomultibyte     # byte-wise: ASCII controls never occur inside a UTF-8 sequence
  local _s="$1" _o="" _c _i
  _s=${_s//\\/\\\\}
  _s=${_s//\"/\\\"}
  _s=${_s//$'\0'/\\u0000}        # zsh strings can hold a NUL; JSON needs it spelled out (after the backslash doubling)
  if [[ "$_s" == *[$'\001'-$'\037']* ]]; then
    _s=${_s//$'\n'/\\n}; _s=${_s//$'\r'/\\r}; _s=${_s//$'\t'/\\t}; _s=${_s//$'\b'/\\b}; _s=${_s//$'\f'/\\f}
    if [[ "$_s" == *[$'\001'-$'\037']* ]]; then
      for (( _i = 1; _i <= ${#_s}; _i++ )); do
        _c=${_s[_i]}
        if [[ "$_c" == [$'\001'-$'\037'] ]]; then _o+=$(printf '\\u%04x' "'$_c"); else _o+=$_c; fi
      done
      _s=$_o
    fi
  fi
  printf '"%s"' "$_s"
}

json_bool() {
  if [ "$1" = "1" ] || [ "$1" = "true" ]; then printf 'true'; else printf 'false'; fi
}
