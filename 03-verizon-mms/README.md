# 03 - Picture messages (MMS) on Verizon

**Status: works for receiving and sending, verified 2026-10-09 (postmarketOS v26.06, mmsd-tng 2.6.4,
ModemManager, NetworkManager). Contains a labelled bandaid.** Other carriers: the idea may apply to any carrier
that has a separate MMS-only APN, but the APN names and server addresses here are Verizon-specific.

## Symptom
Texts work, but picture messages fail to send or never download.

## Root cause
Verizon's MMS server (`mms.vtext.com`) answers only when you reach it through the special `vzwapp`
mobile-data access point, which has no general internet. The normal internet connection (`vzwinternet`)
cannot reach it. The MMS daemon (`mmsd-tng` 2.6.4) can only use the one connection ModemManager has
already open, and cannot open a second one itself.

## What it does
`mms-lane.sh` opens a second mobile-data bearer on the `vzwapp` APN (via `mmcli`), makes a
NetworkManager connection "Verizon-MMS" for it with its own routing table (so only MMS traffic uses it
and your normal internet route is unchanged), and tells `mmsd-tng` over D-Bus to use that APN.
`mms-lane.service` keeps it alive.

BANDAID (labelled in the script): when the main data connection gets stuck, the script redials it. Real
cause: NetworkManager does not notice that the data interface vanished. Proper fix: make NetworkManager
redial by itself. See also fix 07, which does a similar redial for the general case.

## Install
```
install -m755 mms-lane.sh ~/.local/bin/
mkdir -p ~/.config/systemd/user && cp mms-lane.service ~/.config/systemd/user/
# edit NM_MAIN at the top of the script to match your connection (nmcli c show)
~/.local/bin/mms-lane.sh on
```
`mms-lane.sh status` shows what it is doing. Needs `mmcli`, `nmcli`, and the `mmsd-tng` user service.

## Undo
`~/.local/bin/mms-lane.sh off` (disables the helper, removes the lane, restores the previous MMS setting).

## Known limits
- Verizon only. Needs adjusting for other carriers (APN names, MMSC address range).
- Tested with the stock mmsd-tng 2.6.4 on one SIM. A carrier or mmsd-tng update may change things.
- Does not cover data roaming.
