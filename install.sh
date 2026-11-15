#!/bin/bash
# Builds Lingo and moves it into /Applications, replacing any running copy.
set -euo pipefail

cd "$(dirname "$0")"

./build.sh

DEST="/Applications/Lingo.app"

if pgrep -x Lingo >/dev/null; then
    echo "Quitting the running copy..."
    osascript -e 'tell application "Lingo" to quit' 2>/dev/null || pkill -x Lingo || true
    sleep 1
fi

rm -rf "$DEST"
cp -R build.noindex/Lingo.app "$DEST"
echo "Installed $DEST"

open "$DEST"
echo "Lingo is running. Look for the speech-bubble icon in your menu bar."
