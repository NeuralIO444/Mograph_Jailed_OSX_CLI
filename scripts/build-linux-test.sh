#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT="$ROOT/dist/mograph-jailed-linux-test.sh"
: > "$OUT"
printf '%s\n' '#!/usr/bin/env bash' 'set -u' >> "$OUT"
for f in \
  src/core/constants.zsh \
  src/core/json.zsh \
  src/core/errors.zsh \
  src/core/response.zsh \
  src/core/protocol.zsh \
  src/core/path.zsh \
  src/core/capabilities.zsh \
  src/core/operations.zsh \
  src/lib/local_fs.zsh \
  src/lib/native_db.zsh \
  src/lib/media_probe.zsh \
  src/lib/image_kit.zsh \
  src/lib/image_stats.zsh \
  src/lib/frame_kit.zsh \
  src/lib/standard_library.zsh \
  src/modules/system.zsh \
  src/modules/file.zsh \
  src/modules/runtime.zsh \
  src/modules/volume.zsh \
  src/modules/temp.zsh \
  src/modules/media.zsh \
  src/modules/asset.zsh \
  src/modules/provenance.zsh \
  src/modules/image.zsh \
  src/modules/storage.zsh \
  src/modules/search.zsh \
  src/modules/report.zsh \
  src/modules/package.zsh \
  src/cli/entry.zsh; do
  printf '\n# --- %s ---\n' "$f" >> "$OUT"
  cat "$ROOT/$f" >> "$OUT"
done
chmod 755 "$OUT"
