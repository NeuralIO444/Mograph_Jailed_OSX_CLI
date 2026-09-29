#!/bin/zsh
set -eu
ROOT=${0:A:h:h}
printf '%s\n' 'MographJailed tests are split into portable harnesses under tests/.'
printf '%s\n' 'On macOS, run the M4/M5/M6 checklists in addition to portable tests.'
