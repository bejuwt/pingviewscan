#!/bin/bash
#
# Double-clickable fallback launcher.
#
# Runs the PingViewScan binary directly, which bypasses LaunchServices /
# Gatekeeper so it works even when Finder refuses to open the .app bundle.
#
DIR="$(cd "$(dirname "$0")" && pwd)"
BIN="$DIR/PingViewScan.app/Contents/MacOS/PingViewScan"

if [ ! -x "$BIN" ]; then
    echo "PingViewScan has not been built yet. Run ./build_app.sh first."
    echo "Press any key to close."
    read -n 1 -s
    exit 1
fi

exec "$BIN"
