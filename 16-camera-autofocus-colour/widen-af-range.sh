#!/bin/sh
# Copy lolren's tuning files for the two rear cameras to /etc and widen the
# autofocus range from 400..800 to 150..900. On our phone the far-focus
# (landscape) position is about 200, so 400..800 could never focus far away.
# Files in /etc override the ones in /usr/share. Undo: run with --undo.
set -e
SRC=/usr/share/libcamera/ipa/simple
DEST=${DEST:-/etc/libcamera/ipa/simple}

if [ "$1" = "--undo" ]; then
	rm -f "$DEST/imx519.yaml" "$DEST/imx376.yaml"
	echo "Removed $DEST/imx519.yaml and imx376.yaml; libcamera uses $SRC again."
	exit 0
fi

mkdir -p "$DEST"
for s in imx519 imx376; do
	if ! grep -q 'minPosition' "$SRC/$s.yaml" 2>/dev/null; then
		echo "$SRC/$s.yaml has no Af section: install lolren's libcamera first." >&2
		exit 1
	fi
	{
		echo "# Local copy: AF range widened to 150..900 (widen-af-range.sh). Undo: widen-af-range.sh --undo"
		sed -e 's/^\( *minPosition:\).*/\1 150/' \
		    -e 's/^\( *maxPosition:\).*/\1 900/' \
		    -e 's/^\( *initialPosition:\).*/\1 300/' "$SRC/$s.yaml"
	} > "$DEST/$s.yaml"
	echo "Wrote $DEST/$s.yaml"
done
