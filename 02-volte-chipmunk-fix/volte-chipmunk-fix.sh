#!/bin/sh
# Fix "chipmunk" (sped-up, high-pitched) call audio on VoLTE wideband (AMR-WB) calls.
# Sets the q6voice vocproc topology to NONE (0x10F70 = 69488) for TX and RX.
# Source: postmarketOS pmaports issue #3713 (OnePlus 6T chipmunk audio).
# Kernel defaults are TX 69489 (SM_ECNS) / RX 69495 (RX_DEFAULT); to undo, set those back.
for i in $(seq 1 30); do
    if amixer -c 0 cset name='VoiceMMode1 TX Topology' 69488 >/dev/null 2>&1 \
    && amixer -c 0 cset name='VoiceMMode1 RX Topology' 69488 >/dev/null 2>&1; then
        echo "voice topology set to NONE (69488)"
        exit 0
    fi
    sleep 2
done
echo "failed to set voice topology" >&2
exit 1
