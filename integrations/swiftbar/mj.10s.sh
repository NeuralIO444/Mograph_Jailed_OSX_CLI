#!/bin/zsh -f
# OPTIONAL menu-bar item for people who already run SwiftBar (https://swiftbar.app).
# MographJailed itself starts no menu-bar process; this plugin only runs `status` every
# 10 seconds, and `status` reads local files (no runtime calls, no network).
#
# Install: copy this file into your SwiftBar plugins folder and `chmod +x` it.
# <swiftbar.title>MographJailed</swiftbar.title>
# <swiftbar.hideAbout>true</swiftbar.hideAbout>
# <swiftbar.hideRunInTerminal>true</swiftbar.hideRunInTerminal>
exec /usr/bin/python3 "${MOGRAPHJAILED_ROOT:-$HOME/Documents/MographJailed}/scripts/terminal/mj_ui.py" status --swiftbar
