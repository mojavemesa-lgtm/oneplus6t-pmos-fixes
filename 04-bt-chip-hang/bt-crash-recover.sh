#!/bin/sh
# Watches the kernel log for the WCN3990 Bluetooth chip hanging and brings it
# back without a reboot.
#
# What happens (seen 2026-09-21, 09-23, 09-26): the chip firmware stops
# answering (usually "command 0x0406 tx timeout" while dropping a link), the
# kernel's own recovery then loops on "Reading QCA version information failed
# (-110)" forever. Unbinding/rebinding the hci_uart_qca driver really power-
# cycles the chip and it comes back fine -- but "unconfigured" (this chip has no
# stored address), so if you keep a saved address in /run/bt-addr
# (optional, one line like AA:BB:CC:DD:EE:FF) we re-apply it to keep paired
# devices happy, then power on and reconnect paired devices.
set -u
LOGTAG="bt-crash-recover"
DRV=/sys/bus/serial/drivers/hci_uart_qca
DEV=serial0-0
log() { /usr/bin/logger -t "$LOGTAG" "$1"; }
btmgmt_run() { t="$1"; shift; /usr/bin/script -qec "/usr/bin/timeout $t /usr/bin/btmgmt $*" /dev/null 2>/dev/null; }

recover() {
    log "Bluetooth chip hang detected, power-cycling it"
    # NEVER unbind while hci0 is powered: qca_power_off then oopses in
    # tty_set_termios and wedges the driver until reboot (hit 2026-09-26).
    # In a real hang the kernel has already dropped power, so this is a no-op.
    /usr/bin/timeout 10 /usr/bin/bluetoothctl power off >/dev/null 2>&1
    i=0
    while /usr/bin/timeout 5 /usr/bin/bluetoothctl show 2>/dev/null | grep -q 'Powered: yes'; do
        i=$((i + 1))
        if [ "$i" -ge 10 ]; then
            log "hci0 still powered, NOT resetting (would crash the kernel)"
            return
        fi
        sleep 1
    done
    echo "$DEV" > "$DRV/unbind" 2>/dev/null
    sleep 3
    echo "$DEV" > "$DRV/bind"
    i=0
    while [ ! -d /sys/class/bluetooth/hci0 ] && [ "$i" -lt 30 ]; do sleep 1; i=$((i + 1)); done
    sleep 5
    ADDR=$(cat /run/bt-addr 2>/dev/null)
    if [ -n "$ADDR" ]; then
        btmgmt_run 10 public-addr "$ADDR" >/dev/null
        sleep 3
    fi
    /usr/bin/bluetoothctl power on >/dev/null 2>&1
    sleep 2
    for d in $(/usr/bin/bluetoothctl devices Paired | cut -d' ' -f2); do
        /usr/bin/timeout 10 /usr/bin/bluetoothctl connect "$d" >/dev/null 2>&1
    done
    log "Recovery done: $(/usr/bin/bluetoothctl show | grep -E 'Powered' | tr -d '\t')"
}

last=0
/usr/bin/journalctl -k -f -n 0 -o cat | while read -r line; do
    case "$line" in
        *"hci0: Reading QCA version information failed"*|*"hci0: Opcode 0x0c03 failed"*)
            now=$(date +%s)
            # one recovery per minute at most; our own rebind can log noise too
            if [ $((now - last)) -ge 60 ]; then
                last=$now
                recover
            fi
            ;;
    esac
done
