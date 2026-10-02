#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT="$ROOT/dist/mograph-jailed-linux-test.sh"
: > "$OUT"
printf '%s\n' '#!/usr/bin/env zsh' 'set -u' >> "$OUT"
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
  src/modules/project.zsh \
  src/modules/frames.zsh \
  src/modules/audit.zsh \
  src/modules/protect.zsh \
  src/modules/library.zsh \
  src/modules/insight.zsh \
  src/modules/c4d.zsh \
  src/modules/studio.zsh \
  src/modules/space.zsh \
  src/modules/host.zsh \
  src/cli/entry.zsh; do
  printf '\n# --- %s ---\n' "$f" >> "$OUT"
  cat "$ROOT/$f" >> "$OUT"
  # Test bundle only: host-app tests point discovery at a fake /Applications.
  # The production bundle has no such hook.
  if [ "$f" = "src/core/constants.zsh" ]; then
    printf '%s\n' 'MJ_HOST_APPS_DIR="${MJ_TEST_APPS_DIR:-/Applications}"' >> "$OUT"
    printf '%s\n' 'MJ_PS="${MJ_TEST_PS:-/bin/ps}"' >> "$OUT"
  fi
  if [ "$f" = "src/core/capabilities.zsh" ]; then
    # Test bundle only: MJ_TEST_MISSING_CAPS="python3 sips" makes those tools look absent.
    printf '%s\n' 'cap_available() { case " ${MJ_TEST_MISSING_CAPS:-} " in *" $1 "*) return 1 ;; esac; local _cap_path; _cap_path=$(cap_path "$1") || return 1; [ -x "$_cap_path" ]; }' >> "$OUT"
  fi
  if [ "$f" = "src/modules/project.zsh" ]; then
    printf '%s\n' 'PROJECT_OBSERVE_MAX_PLUGIN_FILE_BYTES="${MJ_TEST_PLUGIN_FILE_LIMIT:-2147483648}"' >> "$OUT"
    printf '%s\n' 'snapshot_test_hook() { [ -n "${MJ_TEST_SNAPSHOT_APPEND:-}" ] && printf x >> "$1"; [ -n "${MJ_TEST_SNAPSHOT_CORRUPT_COPY:-}" ] && printf x >> "$2"; return 0; }' >> "$OUT"
  fi
done
chmod 755 "$OUT"
