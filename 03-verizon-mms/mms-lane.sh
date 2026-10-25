#!/bin/bash
# mms-lane.sh — keep a second Verizon data connection ("vzwapp") alive for MMS only.
#
# Why: Verizon only lets the picture-message server (mms.vtext.com, 63.59.x.x) be
# reached from the vzwapp APN, but vzwapp has no general internet. So the phone
# keeps its normal vzwinternet connection for everything, and this script adds a
# second, MMS-only lane next to it. Nothing here touches the main connection or
# the default route (except the BANDAID redial in watch), and nothing needs root.
#
#   mms-lane.sh on      enable the background helper + bring the lane up now
#   mms-lane.sh off     PLAN B: disable the helper, tear the lane down, restore old MMS setting
#   mms-lane.sh status  show what is going on
#   mms-lane.sh up|down|watch   lower-level pieces used by the above / the systemd service

NM_MAIN="Verizon"          # the normal mobile-data connection (APN vzwinternet)
NM_LANE="Verizon-MMS"      # the MMS-only connection this script manages
APN="vzwapp"
MAIN_APN="vzwinternet"
TABLE=100                  # private routing table for traffic bound to the lane
RULE_PRIO=30000
MMSC_NET="63.59.0.0/16"    # Verizon MMS servers
MMSC_URL="http://mms.vtext.com/servlets/mms"
MMSD_UNIT="app-mmsd@autostart.service"
MMSD_STORE="$HOME/.mms/modemmanager/mms"
SERVICE="mms-lane.service"
LOG="$HOME/.local/state/mms-lane.log"
LOCK="$HOME/.local/state/mms-lane.lock"

: "${XDG_RUNTIME_DIR:=/run/user/$(id -u)}"
: "${DBUS_SESSION_BUS_ADDRESS:=unix:path=$XDG_RUNTIME_DIR/bus}"
export XDG_RUNTIME_DIR DBUS_SESSION_BUS_ADDRESS

log()    { echo "$(date '+%F %T') $*" >> "$LOG"; echo "==> $*" >&2; }
notify() { notify-send -a "MMS lane" "$1" "$2" 2>/dev/null || true; }

main_up()     { [ "$(nmcli -g GENERAL.STATE con show "$NM_MAIN" 2>/dev/null)" = "activated" ]; }
internet_ok() { curl -4 -s --max-time 8 -o /dev/null http://connectivity-check.ubuntu.com/ \
             || curl -4 -s --max-time 8 -o /dev/null http://example.com/; }
modem_index() { mmcli -L 2>/dev/null | grep -oE 'Modem/[0-9]+' | head -1 | cut -d/ -f2; }
bfield()      { mmcli -b "$1" -K 2>/dev/null | grep "^bearer\.$2 " | cut -d: -f2- | sed 's/^ *//'; }

lane_bearers() {   # bearer numbers whose APN is vzwapp
    local m="$1" b
    for b in $(mmcli -m "$m" -K 2>/dev/null | grep -oE 'Bearer/[0-9]+' | grep -oE '[0-9]+' | sort -un); do
        [ "$(bfield "$b" properties.apn)" = "$APN" ] && echo "$b"
    done
}

ensure_bearer() {  # prints the number of a connected vzwapp bearer, creating one if needed
    local m="$1" b
    for b in $(lane_bearers "$m"); do
        [ "$(bfield "$b" status.connected)" = "yes" ] && { echo "$b"; return 0; }
    done
    for b in $(lane_bearers "$m"); do mmcli -m "$m" --delete-bearer="$b" >/dev/null 2>&1; done
    b=$(mmcli -m "$m" --create-bearer="apn=$APN,ip-type=ipv4" 2>/dev/null | grep -oE 'Bearer/[0-9]+' | grep -oE '[0-9]+')
    [ -n "$b" ] || { log "ModemManager refused to create a $APN bearer"; return 1; }
    if ! timeout 60 mmcli -b "$b" --connect >/dev/null 2>&1; then
        log "Verizon did not accept the $APN bearer"; mmcli -m "$m" --delete-bearer="$b" >/dev/null 2>&1; return 1
    fi
    log "Connected new $APN bearer $b"
    echo "$b"
}

set_mmsd_apn() {   # tell mmsd-tng which APN to use (persisted by mmsd itself)
    local apn="$1"
    if busctl --user call org.ofono.mms /org/ofono/mms org.ofono.mms.ModemManager ChangeSettings sv MMS_APN s "$apn" >/dev/null 2>&1; then
        return 0
    fi
    # mmsd not running: edit its store file directly (it must be stopped, it rewrites the file on exit)
    systemctl --user stop "$MMSD_UNIT" 2>/dev/null
    [ -f "$MMSD_STORE" ] && sed -i "s/^MMS_APN=.*/MMS_APN=$apn/" "$MMSD_STORE"
    systemctl --user start "$MMSD_UNIT" 2>/dev/null
}
mmsd_apn() { busctl --user call org.ofono.mms /org/ofono/mms org.ofono.mms.ModemManager ViewSettings 2>/dev/null | grep -oE '"MMS_APN" s "[^"]*"' | cut -d'"' -f4; }

lane_healthy() {
    local m b iface addr
    m=$(modem_index) || return 1
    for b in $(lane_bearers "$m"); do
        [ "$(bfield "$b" status.connected)" = "yes" ] || continue
        iface=$(bfield "$b" status.interface); addr=$(bfield "$b" ipv4-config.address)
        [ "$(nmcli -g GENERAL.STATE con show "$NM_LANE" 2>/dev/null)" = "activated" ] || return 1
        ip -4 addr show dev "$iface" 2>/dev/null | grep -q "inet $addr/" || return 1
        ip route show table "$TABLE" 2>/dev/null | grep -q "^default .* dev $iface" || return 1
        [ "$(mmsd_apn)" = "$APN" ] || return 1
        return 0
    done
    return 1
}

up() {
    exec 9>"$LOCK"; flock 9
    main_up || { log "Main data ($NM_MAIN) is not connected, nothing to do"; return 2; }
    local had_internet=1; internet_ok || had_internet=0
    local m b iface addr pfx gw
    m=$(modem_index) || { log "No modem found"; return 1; }
    b=$(ensure_bearer "$m") || return 1
    iface=$(bfield "$b" status.interface); addr=$(bfield "$b" ipv4-config.address)
    pfx=$(bfield "$b" ipv4-config.prefix);  gw=$(bfield "$b" ipv4-config.gateway)
    [ -n "$iface" ] && [ -n "$addr" ] && [ -n "$gw" ] || { log "Bearer $b has no IPv4 config"; return 1; }
    nmcli dev set "$iface" managed yes >/dev/null 2>&1
    local routes="$MMSC_NET $gw, 0.0.0.0/0 $gw table=$TABLE" rules="priority $RULE_PRIO oif $iface table $TABLE"
    if nmcli -g connection.id con show "$NM_LANE" >/dev/null 2>&1; then
        nmcli con modify "$NM_LANE" connection.interface-name "$iface" ipv4.addresses "$addr/$pfx" \
            ipv4.routes "$routes" ipv4.routing-rules "$rules" || return 1
    else
        nmcli con add type generic ifname "$iface" con-name "$NM_LANE" connection.autoconnect no \
            ipv4.method manual ipv4.addresses "$addr/$pfx" ipv4.never-default yes ipv4.ignore-auto-dns yes \
            ipv4.routes "$routes" ipv4.routing-rules "$rules" ipv6.method disabled >/dev/null || return 1
    fi
    nmcli con up "$NM_LANE" >/dev/null || { log "Could not activate $NM_LANE"; return 1; }
    set_mmsd_apn "$APN"
    busctl --user call org.ofono.mms /org/ofono/mms org.ofono.mms.ModemManager ProcessMessageQueue >/dev/null 2>&1
    sleep 2
    if [ "$had_internet" = 1 ] && ! internet_ok; then
        log "PLAN B: internet stopped working after enabling the lane, tearing it down"
        down; notify "MMS lane disabled itself" "Internet broke, so the MMS lane was removed."
        return 1
    fi
    log "MMS lane up: $iface $addr/$pfx via bearer $b"
    return 0
}

down() {
    exec 8>"$LOCK.down"; flock 8
    local m b
    set_mmsd_apn "$MAIN_APN"
    nmcli con down "$NM_LANE" >/dev/null 2>&1
    nmcli con delete "$NM_LANE" >/dev/null 2>&1
    m=$(modem_index)
    for b in $(lane_bearers "$m"); do
        mmcli -b "$b" --disconnect >/dev/null 2>&1; mmcli -m "$m" --delete-bearer="$b" >/dev/null 2>&1
    done
    log "MMS lane down, MMS APN back to $MAIN_APN"
}

status() {
    echo "Main data ($NM_MAIN):   $(nmcli -g GENERAL.STATE con show "$NM_MAIN" 2>/dev/null || echo down), APN $(nmcli -g gsm.apn con show "$NM_MAIN" 2>/dev/null)"
    printf 'Internet:               '; internet_ok && echo OK || echo "NOT WORKING"
    echo "Background helper:      $(systemctl --user is-enabled "$SERVICE" 2>/dev/null) / $(systemctl --user is-active "$SERVICE" 2>/dev/null)"
    echo "MMS lane ($NM_LANE): $(nmcli -g GENERAL.STATE con show "$NM_LANE" 2>/dev/null || echo 'not present')"
    local m b; m=$(modem_index)
    for b in $(lane_bearers "$m"); do
        echo "  bearer $b: connected=$(bfield "$b" status.connected) iface=$(bfield "$b" status.interface) ip=$(bfield "$b" ipv4-config.address)"
    done
    echo "MMS daemon APN:         $(mmsd_apn)"
    printf 'Lane healthy:           '; lane_healthy && echo yes || echo no
    printf 'Verizon MMS server:     '
    local iface; iface=$(nmcli -g GENERAL.DEVICES con show "$NM_LANE" 2>/dev/null)
    if [ -n "$iface" ]; then
        # Ask the lane's own Verizon DNS over the lane, like mmsd (ForceCAres) does: the MMS server
        # name only exists inside Verizon, and the system DNS is Quad9 since 2026-10-09.
        local dns code; dns=$(mmcli -b "$b" -K 2>/dev/null | sed -n 's/^bearer\.ipv4-config\.dns\.value\[[0-9]*\] *: *//p' | paste -sd, -)
        code=$(curl -4 -s --max-time 12 --interface "$iface" ${dns:+--dns-interface "$iface" --dns-servers "$dns"} -o /dev/null -w '%{http_code}' "$MMSC_URL")
        [ "$code" != "000" ] && echo "reachable via $iface (http $code)" || echo "NOT reachable via $iface"
    else
        echo "(no lane)"
    fi
}

# BANDAID (2026-10-14): when Verizon hangs up the data call, ModemManager removes
# the data interface but NetworkManager keeps "Verizon" shown as activated on the
# vanished device and never redials (data dead until mobile data is toggled).
# Real bug is in NM/MM; until fixed, spot that state and redial. Note:
# Proper fix: make NetworkManager notice the vanished data interface and redial by itself.
main_stuck() {
    main_up || return 1
    local ifc; ifc=$(nmcli -g GENERAL.IP-IFACE dev show qrtr0 2>/dev/null)
    [ -z "$ifc" ] && return 0
    ip -4 addr show dev "$ifc" 2>/dev/null | grep -q 'inet ' && return 1
    return 0
}

watch() {
    log "watch loop started"
    local fails=0 stuck=0
    while true; do
        if main_stuck; then stuck=$((stuck+1)); else stuck=0; fi
        if [ "$stuck" -ge 2 ]; then
            log "main data link stuck (interface gone) - redialing $NM_MAIN"
            nmcli con down "$NM_MAIN" >/dev/null 2>&1; sleep 2
            nmcli con up "$NM_MAIN" >/dev/null 2>&1 && log "$NM_MAIN redialed" || log "$NM_MAIN redial FAILED"
            stuck=0
        fi
        if main_up && ! lane_healthy; then
            if up; then fails=0; else fails=$((fails+1)); fi
        fi
        if [ "$fails" -ge 3 ]; then sleep 300; fails=0; else sleep 30; fi
    done
}

case "$1" in
  on)
    systemctl --user daemon-reload
    systemctl --user enable --now "$SERVICE" >/dev/null 2>&1
    if up; then
        echo; echo "SUCCESS. The MMS lane is up and will be kept up automatically (also after reboots)."
        echo "Pictures should now arrive. To test, send yourself a photo by text message."
        notify "MMS lane ON" "Picture messages should work now."
    else
        echo; echo "The lane could not be brought up. See $LOG"
    fi
    echo; status ;;
  off)
    systemctl --user disable --now "$SERVICE" >/dev/null 2>&1
    down
    echo; echo "The MMS lane is OFF and the helper is disabled. Phone is back to how it was."
    notify "MMS lane OFF" "Back to the original setup."
    echo; status ;;
  up)     up ;;
  down)   down ;;
  status) status ;;
  watch)  watch ;;
  *) echo "usage: $0 on | off | status | up | down | watch"; exit 1 ;;
esac
