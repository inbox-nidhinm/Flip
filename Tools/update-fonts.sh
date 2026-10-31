#!/bin/bash
# Copies the title face and its licence from the AA Bridge submodule into
# Sources/Flip/Fonts, where the app bundles them from.
#
# The copies in Sources/Flip/Fonts are committed, so Flip builds without the
# submodule. When the submodule is not checked out this does nothing, quietly,
# and the committed copies are used as they are.
#
# To pick up a new release of the face: move the submodule to it, run this
# (or make-app.sh, which runs it), and commit what changed.
set -euo pipefail

cd "$(dirname "$0")/.."

SRC="Vendor/AA-Bridge/slab"
DEST="Sources/Flip/Fonts"
FONT="AABridgeSlab16pt-Light.ttf"

if [ ! -f "$SRC/fonts/ttf/$FONT" ] || [ ! -f "$SRC/OFL.txt" ]; then
    exit 0
fi

for pair in "fonts/ttf/$FONT:$FONT" "OFL.txt:OFL.txt"; do
    from="$SRC/${pair%%:*}"
    to="$DEST/${pair##*:}"
    if ! cmp -s "$from" "$to"; then
        cp "$from" "$to"
        echo "updated $to"
    fi
done
