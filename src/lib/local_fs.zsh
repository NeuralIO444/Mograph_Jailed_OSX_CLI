# MJ Standard Library 1.0 — LocalFS
# Shared filesystem classification and local-only policy helpers.
# This module never enumerates network mounts and never mutates a path.

mj_fs_type() {
  local _path="$1"
  if [ "$(/usr/bin/uname -s 2>/dev/null)" = "Darwin" ]; then
    # macOS BSD stat(1) %T reports the file-object type, not the mounted
    # filesystem. df -Y exposes the mounted filesystem type as column 2.
    /bin/df -kY "$_path" 2>/dev/null | /usr/bin/awk 'NR>1 {v=$2} END{if(v!="") print v}' || true
  else
    /usr/bin/stat -f -c '%T' "$_path" 2>/dev/null || true
  fi
}

mj_fs_class() {
  case "$1" in
    smbfs|nfs|webdav|afpfs|cifs|nfs4) printf 'network' ;;
    apfs|hfs|hfs+|exfat|msdos|vfat|ext2/ext3|ext2|ext3|ext4|xfs|overlay|overlayfs|tmpfs) printf 'local' ;;
    *) printf 'unknown' ;;
  esac
}

# Compatibility names retained for existing modules/consumers of modular source.
volume_fs_type() { mj_fs_type "$1"; }
volume_class() { mj_fs_class "$1"; }

volume_free_kb() {
  /bin/df -kP "$1" 2>/dev/null | /usr/bin/awk 'NR>1 {v=$4} END{if(v ~ /^[0-9]+$/) print v}'
}

# Probe one existing path without walking it. Globals are intentionally namespaced.
mj_local_scope_probe() {
  local _path="$1"
  MJ_LOCAL_SCOPE_FS=""
  MJ_LOCAL_SCOPE_CLASS="unknown"
  MJ_LOCAL_SCOPE_FS=$(mj_fs_type "$_path" 2>/dev/null || printf '')
  if [ -n "$MJ_LOCAL_SCOPE_FS" ]; then
    MJ_LOCAL_SCOPE_CLASS=$(mj_fs_class "$MJ_LOCAL_SCOPE_FS")
  fi
  [ "$MJ_LOCAL_SCOPE_CLASS" = "local" ]
}

# Fail closed for operations that are explicitly local-only. The caller must
# validate path existence/type first so error semantics remain deterministic.
mj_require_local_existing_path() {
  local _path="$1"
  mj_local_scope_probe "$_path" && return 0
  case "$MJ_LOCAL_SCOPE_CLASS" in
    network)
      set_error "NETWORK_SCOPE_BLOCKED" "Operation is local-only; network volumes are outside the MographJailed automatic execution boundary."
      ;;
    *)
      set_error "STORAGE_SCOPE_UNKNOWN" "Operation requires a positively identified local filesystem; storage classification is unknown."
      ;;
  esac
  return 1
}

standard_library_localfs_available() {
  cap_available df && cap_available awk && cap_available uname
}
