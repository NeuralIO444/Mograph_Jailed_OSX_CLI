json_quote() {
  # JSON-quote one shell string. Shell variables cannot contain NUL; all other
  # ASCII controls are escaped. Unicode bytes are preserved.
  JSON_INPUT="$1" /usr/bin/awk 'BEGIN {
    ORS="";
    s=ENVIRON["JSON_INPUT"];
    printf "\"";
    for (i=1; i<=length(s); i++) {
      c=substr(s,i,1);
      if (c=="\\") printf "\\\\";
      else if (c=="\"") printf "\\\"";
      else if (c=="\b") printf "\\b";
      else if (c=="\f") printf "\\f";
      else if (c=="\n") printf "\\n";
      else if (c=="\r") printf "\\r";
      else if (c=="\t") printf "\\t";
      else {
        code=-1;
        for (j=1; j<32; j++) {
          if (c==sprintf("%c",j)) { code=j; break; }
        }
        if (code>=0) printf "\\u%04x", code;
        else printf "%s", c;
      }
    }
    printf "\"";
  }'
}

json_bool() {
  if [ "$1" = "1" ] || [ "$1" = "true" ]; then printf 'true'; else printf 'false'; fi
}
