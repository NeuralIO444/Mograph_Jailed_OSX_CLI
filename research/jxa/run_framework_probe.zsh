#!/bin/zsh
set -eu
HERE=${0:A:h}
exec /usr/bin/osascript -l JavaScript "$HERE/framework_probe.js"
