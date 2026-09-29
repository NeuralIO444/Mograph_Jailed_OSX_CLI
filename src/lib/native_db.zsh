# MJ Standard Library 1.0 — NativeDB
# Safe capability layer for the stock sqlite3 runtime. There is deliberately no
# public arbitrary-SQL request operation. Product modules may build fixed-schema
# stores on top of these internal helpers after their own contract review.

native_db_available() {
  cap_available sqlite3
}

native_db_version() {
  local _out=""
  native_db_available || return 1
  _out=$(/usr/bin/sqlite3 -version 2>/dev/null) || return 1
  printf '%s\n' "$_out" | /usr/bin/awk 'NR==1 {print $1; exit}'
}

# Static, in-memory capability probes only. No request data becomes SQL and no
# filesystem database is created by these checks.
native_db_probe_features() {
  local _out=""
  MOGRAPHJAILED_DB_RUNTIME=false
  MOGRAPHJAILED_DB_JSON=false
  MOGRAPHJAILED_DB_FTS5=false
  native_db_available || return 1

  _out=$(/usr/bin/sqlite3 -batch -init /dev/null ':memory:' 'PRAGMA temp_store=MEMORY; SELECT 1;' 2>/dev/null) || return 1
  [ "$_out" = "1" ] || return 1
  MOGRAPHJAILED_DB_RUNTIME=true

  _out=$(/usr/bin/sqlite3 -batch -init /dev/null ':memory:' "PRAGMA temp_store=MEMORY; SELECT json_valid('{\"mj\":\"native\"}');" 2>/dev/null || printf '')
  [ "$_out" = "1" ] && MOGRAPHJAILED_DB_JSON=true

  _out=$(/usr/bin/sqlite3 -batch -init /dev/null ':memory:' "PRAGMA temp_store=MEMORY; CREATE VIRTUAL TABLE mj_fts USING fts5(value); INSERT INTO mj_fts(value) VALUES('native search'); SELECT count(*) FROM mj_fts WHERE mj_fts MATCH 'native';" 2>/dev/null || printf '')
  [ "$_out" = "1" ] && MOGRAPHJAILED_DB_FTS5=true
  return 0
}

native_db_parent_for_path() {
  local _path="$1"
  case "$_path" in
    /*) ;;
    *) return 1 ;;
  esac
  case "$_path" in
    */*) printf '%s' "${_path%/*}" ;;
    *) return 1 ;;
  esac
}

# Validate where a future SQLite store may be created. This function does not
# create a database. Network and unknown filesystems fail closed.
native_db_validate_store_path() {
  local _path="$1"
  local _parent=""
  [ -n "$_path" ] || return 1
  _parent=$(native_db_parent_for_path "$_path") || return 1
  [ -n "$_parent" ] || _parent="/"
  [ -d "$_parent" ] || return 1
  [ -w "$_parent" ] || return 1
  if [ -e "$_path" ] || [ -L "$_path" ]; then
    [ -f "$_path" ] || return 1
    [ ! -L "$_path" ] || return 1
  fi
  mj_require_local_existing_path "$_parent"
}

standard_library_nativedb_available() {
  native_db_probe_features
}
