#!/bin/sh
# Turn on HD voice (mSBC) negotiation in PulseAudio for the current user.
# Copies the system default.pa to ~/.config/pulse/default.pa (if you have none yet)
# and adds enable_msbc=true to module-bluetooth-discover.
# Undo: delete ~/.config/pulse/default.pa (or remove "enable_msbc=true") and restart PulseAudio / reboot.
set -e
dst="$HOME/.config/pulse/default.pa"
mkdir -p "$HOME/.config/pulse"
[ -f "$dst" ] || cp /etc/pulse/default.pa "$dst"
if grep -q 'module-bluetooth-discover.*enable_msbc=true' "$dst"; then
    echo "already enabled in $dst"
else
    cp "$dst" "$dst.bak-msbc"
    sed -i 's/^load-module module-bluetooth-discover.*/load-module module-bluetooth-discover enable_msbc=true/' "$dst"
    echo "enabled in $dst (backup: $dst.bak-msbc); reboot or restart PulseAudio"
fi
