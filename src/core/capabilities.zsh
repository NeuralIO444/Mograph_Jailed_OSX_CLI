cap_path() {
  case "$1" in
    zsh) printf '/bin/zsh' ;;
    sw_vers) printf '/usr/bin/sw_vers' ;;
    stat) printf '/usr/bin/stat' ;;
    file) printf '/usr/bin/file' ;;
    df) printf '/bin/df' ;;
    mktemp) printf '/usr/bin/mktemp' ;;
    plutil) printf '/usr/bin/plutil' ;;
    sqlite3) printf '/usr/bin/sqlite3' ;;
    jq) printf '/usr/bin/jq' ;;
    sips) printf '/usr/bin/sips' ;;
    ditto) printf '/usr/bin/ditto' ;;
    sha256)
      if [ -x /sbin/sha256 ]; then printf '/sbin/sha256'
      elif [ -x /usr/bin/sha256 ]; then printf '/usr/bin/sha256'
      else printf '/sbin/sha256'; fi
      ;;
    shasum) printf '/usr/bin/shasum' ;;
    mdls) printf '/usr/bin/mdls' ;;
    avmediainfo) printf '/usr/bin/avmediainfo' ;;
    avconvert) printf '/usr/bin/avconvert' ;;
    afinfo) printf '/usr/bin/afinfo' ;;
    afconvert) printf '/usr/bin/afconvert' ;;
    mdfind) printf '/usr/bin/mdfind' ;;
    xattr) printf '/usr/bin/xattr' ;;
    osascript) printf '/usr/bin/osascript' ;;
    python3) printf '/usr/bin/python3' ;;
    base64) printf '/usr/bin/base64' ;;
    awk) printf '/usr/bin/awk' ;;
    uname) printf '/usr/bin/uname' ;;
    sed) printf '/usr/bin/sed' ;;
    rm) printf '/bin/rm' ;;
    mv) printf '/bin/mv' ;;
    pwd) printf '/bin/pwd' ;;
    *) return 1 ;;
  esac
}

cap_available() {
  local _cap_path
  _cap_path=$(cap_path "$1") || return 1
  [ -x "$_cap_path" ]
}

emit_capability_object() {
  local _name="$1"
  local _path
  _path=$(cap_path "$_name" 2>/dev/null || printf '')
  printf '{"available":'; if [ -n "$_path" ] && [ -x "$_path" ]; then printf 'true'; else printf 'false'; fi
  printf ',"path":'; json_quote "$_path"; printf '}'
}
