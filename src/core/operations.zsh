operation_names() {
  printf '%s\n' \
    system.probe \
    system.doctor \
    system.describe \
    runtime.verify \
    file.inspect \
    file.hash \
    file.provenance \
    asset.manifest \
    asset.verify \
    search.candidate \
    image.inspect \
    image.derivative \
    image.stats \
    image.compare \
    storage.preflight \
    volume.inspect \
    temp.create \
    temp.clean \
    media.inspect \
    media.timing \
    media.frame \
    project.ingest \
    expression.lint \
    plugin.audit \
    project.snapshot \
    loop.seams \
    golden.record \
    golden.check \
    audit.verify \
    project.restore \
    deps.graph \
    handoff.package \
    index.add \
    index.search \
    index.verify \
    preset.add \
    preset.get \
    host.detect \
    ae.render \
    c4d.render \
    report.tech \
    package.create
}

operation_known() {
  case "$1" in
    system.probe|system.doctor|system.describe|runtime.verify|file.inspect|file.hash|file.provenance|asset.manifest|asset.verify|search.candidate|image.inspect|image.derivative|image.stats|image.compare|storage.preflight|volume.inspect|temp.create|temp.clean|media.inspect|media.timing|media.frame|project.ingest|expression.lint|plugin.audit|project.snapshot|loop.seams|golden.record|golden.check|audit.verify|project.restore|deps.graph|handoff.package|index.add|index.search|index.verify|preset.add|preset.get|host.detect|ae.render|c4d.render|report.tech|package.create) return 0 ;;
    *) return 1 ;;
  esac
}

# Emit a JSON string array from newline-delimited stdin. This deliberately
# avoids shell word-splitting semantics, which differ between zsh and bash.
emit_string_array_lines() {
  local _first=1
  local _item=""
  printf '['
  while IFS= read -r _item || [ -n "$_item" ]; do
    [ -n "$_item" ] || continue
    [ "$_first" -eq 1 ] || printf ','
    _first=0
    json_quote "$_item"
  done
  printf ']'
}

operation_available() {
  case "$1" in
    system.probe|system.doctor|system.describe|runtime.verify|report.tech)
      return 0
      ;;
    file.inspect)
      cap_available stat && cap_available file && cap_available uname
      ;;
    file.hash)
      cap_available stat && cap_available uname && { cap_available sha256 || cap_available shasum; }
      ;;
    file.provenance)
      cap_available xattr
      ;;
    asset.manifest)
      cap_available stat && cap_available file && cap_available uname
      ;;
    asset.verify)
      cap_available stat && cap_available uname
      ;;
    search.candidate)
      cap_available mdfind && cap_available mktemp && cap_available rm
      ;;
    image.inspect)
      cap_available sips && cap_available awk
      ;;
    image.derivative)
      cap_available sips && cap_available awk && cap_available mktemp && cap_available mv && cap_available rm && cap_available stat && cap_available uname
      ;;
    loop.seams|golden.record|golden.check|audit.verify|deps.graph|index.add|index.search|index.verify|host.detect|ae.render|c4d.render)
      cap_available python3
      ;;
    project.restore|handoff.package|preset.add|preset.get)
      cap_available python3 && cap_available cp
      ;;
    image.stats|image.compare)
      cap_available python3 && cap_available sips && cap_available awk
      ;;
    storage.preflight)
      cap_available df && cap_available awk && cap_available uname
      ;;
    volume.inspect)
      cap_available df && cap_available awk && cap_available uname
      ;;
    temp.create)
      cap_available mktemp && cap_available rm && cap_available pwd
      ;;
    temp.clean)
      cap_available sed && cap_available rm && cap_available pwd
      ;;
    media.inspect)
      cap_available stat && cap_available file && cap_available uname
      ;;
    media.timing)
      standard_library_mediaprobe_available
      ;;
    media.frame)
      standard_library_framekit_available
      ;;
    project.ingest|expression.lint)
      cap_available python3
      ;;
    plugin.audit)
      cap_available stat && cap_available uname && { cap_available sha256 || cap_available shasum; }
      ;;
    project.snapshot)
      cap_available stat && cap_available uname && cap_available cp && cap_available date && cap_available rm && { cap_available sha256 || cap_available shasum; }
      ;;
    package.create)
      cap_available ditto && cap_available mktemp && cap_available rm && cap_available mv && cap_available stat && cap_available uname
      ;;
    *) return 1 ;;
  esac
}

operation_state() {
  if operation_available "$1"; then printf 'AVAILABLE'; else printf 'UNAVAILABLE'; fi
}

operation_cost() {
  case "$1" in
    system.probe|system.doctor|system.describe|runtime.verify|file.inspect|file.provenance|image.inspect|volume.inspect|storage.preflight|temp.create|temp.clean|report.tech) printf 'FAST' ;;
    file.hash) printf 'SIZE_DEPENDENT' ;;
    asset.manifest|asset.verify) printf 'MODE_DEPENDENT' ;;
    search.candidate) printf 'INDEX_DEPENDENT' ;;
    image.derivative) printf 'IO_BOUND' ;;
    image.stats|image.compare) printf 'SIZE_DEPENDENT' ;;
    loop.seams|golden.record|golden.check) printf 'FRAME_COUNT_DEPENDENT' ;;
    media.inspect) printf 'PATH_DEPENDENT' ;;
    media.timing) printf 'BOUNDED_MEDIA_PROBE' ;;
    media.frame) printf 'FRAME_DECODE' ;;
    project.ingest|expression.lint|audit.verify|deps.graph) printf 'SIZE_DEPENDENT' ;;
    project.restore|handoff.package|preset.add|preset.get) printf 'IO_BOUND' ;;
    index.add) printf 'PATH_DEPENDENT' ;;
    index.search) printf 'INDEX_DEPENDENT' ;;
    index.verify) printf 'SIZE_DEPENDENT' ;;
    host.detect) printf 'BOUNDED_PROBE' ;;
    ae.render|c4d.render) printf 'RENDER_BOUND' ;;
    plugin.audit) printf 'PATH_DEPENDENT' ;;
    project.snapshot) printf 'IO_BOUND' ;;
    package.create) printf 'IO_BOUND' ;;
    *) printf 'UNKNOWN' ;;
  esac
}

operation_mutation() {
  case "$1" in
    temp.create) printf 'TEMP_CREATE' ;;
    temp.clean) printf 'TEMP_DELETE' ;;
    search.candidate|loop.seams|golden.check) printf 'INTERNAL_TEMP' ;;
    image.derivative|media.frame|package.create|project.snapshot|golden.record|project.restore|handoff.package|preset.get|ae.render|c4d.render) printf 'DERIVATIVE_CREATE' ;;
    index.add|preset.add) printf 'STORE_WRITE' ;;
    *) printf 'NONE' ;;
  esac
}

operation_authority() {
  case "$1" in
    system.probe|system.doctor) printf 'AUTHORITATIVE_ENVIRONMENT' ;;
    system.describe) printf 'CONTRACT' ;;
    runtime.verify) printf 'AUTHORITATIVE_RUNTIME' ;;
    file.inspect|volume.inspect|storage.preflight) printf 'MIXED' ;;
    file.hash) printf 'AUTHORITATIVE_BYTES' ;;
    file.provenance) printf 'AUTHORITATIVE_FILESYSTEM_METADATA' ;;
    asset.manifest|asset.verify) printf 'ASSET_IDENTITY' ;;
    search.candidate) printf 'ADVISORY_INDEX' ;;
    image.inspect) printf 'AUTHORITATIVE_IMAGE_STRUCTURE' ;;
    image.stats|image.compare|loop.seams|golden.record|golden.check) printf 'DERIVED_IMAGE_SIGNATURE' ;;
    image.derivative|temp.create|temp.clean|package.create) printf 'AUTHORITATIVE_OPERATION' ;;
    media.inspect) printf 'ADVISORY_METADATA' ;;
    media.timing) printf 'NORMALIZED_NATIVE_MEDIA' ;;
    media.frame) printf 'NATIVE_FRAME_DERIVATIVE' ;;
    report.tech) printf 'DIAGNOSTIC' ;;
    project.ingest) printf 'DERIVED_PROJECT_SUMMARY' ;;
    expression.lint) printf 'DERIVED_LINT_FINDINGS' ;;
    plugin.audit) printf 'AUTHORITATIVE_FILESYSTEM_METADATA' ;;
    project.snapshot) printf 'AUTHORITATIVE_OPERATION' ;;
    audit.verify) printf 'DERIVED_AUDIT_CHAIN' ;;
    project.restore|handoff.package) printf 'AUTHORITATIVE_OPERATION' ;;
    deps.graph) printf 'DERIVED_PROJECT_SUMMARY' ;;
    index.add|preset.add) printf 'MJ_OWNED_STORE' ;;
    index.search) printf 'ADVISORY_INDEX' ;;
    index.verify) printf 'AUTHORITATIVE_STORE_INTEGRITY' ;;
    preset.get|ae.render|c4d.render) printf 'AUTHORITATIVE_OPERATION' ;;
    host.detect) printf 'AUTHORITATIVE_ENVIRONMENT' ;;
    *) printf 'UNKNOWN' ;;
  esac
}

operation_interactive_safe() {
  case "$1" in
    file.hash|asset.manifest|asset.verify|search.candidate|image.derivative|media.timing|media.frame|package.create|project.snapshot|loop.seams|golden.record|golden.check|project.restore|handoff.package|index.add|preset.add|preset.get|ae.render|c4d.render) return 1 ;;
    *) return 0 ;;
  esac
}

operation_network_sensitive() {
  case "$1" in
    file.inspect|file.hash|file.provenance|asset.manifest|asset.verify|search.candidate|image.inspect|image.derivative|image.stats|image.compare|storage.preflight|volume.inspect|media.inspect|media.timing|media.frame|package.create|project.ingest|expression.lint|plugin.audit|project.snapshot|loop.seams|golden.record|golden.check|audit.verify|project.restore|deps.graph|handoff.package|index.add|index.search|index.verify|preset.add|preset.get|ae.render|c4d.render) return 0 ;;
    *) return 1 ;;
  esac
}

# Required and optional capability functions emit one capability per line so
# Registry serialization is identical under zsh and bash.
operation_required_all() {
  case "$1" in
    system.probe|system.doctor|system.describe|runtime.verify|report.tech) ;;
    file.inspect) printf '%s\n' stat file uname ;;
    file.hash) printf '%s\n' stat uname ;;
    file.provenance) printf '%s\n' xattr ;;
    asset.manifest) printf '%s\n' stat file uname ;;
    asset.verify) printf '%s\n' stat uname ;;
    search.candidate) printf '%s\n' mdfind mktemp rm ;;
    image.inspect) printf '%s\n' sips awk ;;
    image.derivative) printf '%s\n' sips awk mktemp mv rm stat uname ;;
    image.stats|image.compare) printf '%s\n' python3 sips awk ;;
    loop.seams|golden.record|golden.check|audit.verify|deps.graph|index.add|index.search|index.verify|host.detect|ae.render|c4d.render) printf '%s\n' python3 ;;
    project.restore|handoff.package|preset.add|preset.get) printf '%s\n' python3 cp ;;
    storage.preflight|volume.inspect) printf '%s\n' df awk uname ;;
    temp.create) printf '%s\n' mktemp rm pwd ;;
    temp.clean) printf '%s\n' sed rm pwd ;;
    media.inspect) printf '%s\n' stat file uname ;;
    media.timing) printf '%s\n' avmediainfo awk df uname ;;
    media.frame) printf '%s\n' avmediainfo python3 jq sips awk df mktemp mv rm stat uname ;;
    package.create) printf '%s\n' ditto mktemp rm mv stat uname ;;
    project.ingest|expression.lint) printf '%s\n' python3 ;;
    plugin.audit) printf '%s\n' stat uname ;;
    project.snapshot) printf '%s\n' stat uname cp date rm ;;
  esac
}

operation_optional_capabilities() {
  case "$1" in
    system.probe|system.doctor|report.tech) printf '%s\n' sw_vers ;;
    runtime.verify) printf '%s\n' sha256 shasum ;;
    asset.manifest|asset.verify) printf '%s\n' sha256 shasum ;;
    media.inspect) printf '%s\n' mdls avmediainfo ;;
    loop.seams|golden.record|golden.check) printf '%s\n' sips ;;
  esac
}

emit_operation_requires() {
  local _name="$1"
  printf '{"all":'
  operation_required_all "$_name" | emit_string_array_lines
  printf ',"anyOf":['
  case "$_name" in
    file.hash|plugin.audit|project.snapshot)
      printf '["sha256","shasum"]'
      ;;
  esac
  printf ']}'
}

emit_operation_descriptor() {
  local _name="$1"
  local _available=false
  local _interactive=false
  local _network=false
  operation_available "$_name" && _available=true
  operation_interactive_safe "$_name" && _interactive=true
  operation_network_sensitive "$_name" && _network=true

  printf '{"available":'; $_available && printf 'true' || printf 'false'
  printf ',"state":'; json_quote "$(operation_state "$_name")"
  printf ',"cost":'; json_quote "$(operation_cost "$_name")"
  printf ',"mutation":'; json_quote "$(operation_mutation "$_name")"
  printf ',"authority":'; json_quote "$(operation_authority "$_name")"
  printf ',"interactiveSafe":'; $_interactive && printf 'true' || printf 'false'
  printf ',"networkSensitive":'; $_network && printf 'true' || printf 'false'
  printf ',"executionScope":'; case "$_name" in media.timing|media.frame|project.ingest|expression.lint|plugin.audit|project.snapshot|loop.seams|golden.record|golden.check|audit.verify|project.restore|deps.graph|handoff.package|index.add|index.search|index.verify|preset.add|preset.get|host.detect|ae.render|c4d.render) json_quote "LOCAL_ONLY" ;; *) json_quote "EXPLICIT_PATH_OR_NONE" ;; esac
  printf ',"requires":'; emit_operation_requires "$_name"
  printf ',"optionalCapabilities":'; operation_optional_capabilities "$_name" | emit_string_array_lines
  request_schema_for "$_name"
  printf ',"args":{"allowed":'; printf '%s\n' ${=MJ_SCHEMA_ALLOWED} | emit_string_array_lines
  printf ',"required":'; printf '%s\n' ${=MJ_SCHEMA_REQUIRED} | emit_string_array_lines
  printf '}}'
}

emit_operation_registry() {
  local _name
  local _first=1
  printf '{'
  while IFS= read -r _name; do
    [ -n "$_name" ] || continue
    [ "$_first" -eq 1 ] || printf ','
    _first=0
    json_quote "$_name"; printf ':'; emit_operation_descriptor "$_name"
  done <<EOF_OPERATIONS
$(operation_names)
EOF_OPERATIONS
  printf '}'
}
