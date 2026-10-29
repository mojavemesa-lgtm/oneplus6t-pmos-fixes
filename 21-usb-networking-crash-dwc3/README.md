# 21 - USB networking to a PC crashes the phone (dwc3 "No resource" storm)

Connecting the phone to a PC for USB networking can flood the log and crash the phone.

Keywords: OnePlus 6T postmarketOS USB networking crash, fajita mainline dwc3 gadget No resource for ep, pmOS usb0 NCM tether reboot, sdm845 dwc3 forceRM EndTransfer, Linux phone USB gadget warning storm, ncm set_alt crash

**Status: in our everyday kernel since 2026-10-29 (hours old when this was written), no crash since. Treat as "tested briefly".**

## Symptom
When the phone is plugged into a PC and the USB network gadget (NCM) is set up, the log fills with
`dwc3 ... No resource for ep...` warnings. Each warning runs with interrupts off and takes several ms; a storm of them
delayed another interrupt and, on our deep-sleep kernel (fix 18), crashed the phone after a call wake with the cable in.
Reworded: this fixes the crash after USB networking set-up. It does not make the phone sleep while on a charger.

## Cause
When an endpoint is disabled while the control endpoint is not in the SETUP phase, its End Transfer is delayed. The
network function's `eth_stop()` then disables and re-enables the endpoint at once (NCM Set Interface). The enable issues
a Start Transfer while the old transfer is still active, so the controller answers "No Resource", and every later kick fails
the same way. A second part: `forceRM` was left set when an End Transfer was issued.

## What the fix does (`kernel/`)
- 0001: upstream `c70036e35` (Elson Serrao, Qualcomm): clear forceRM when issuing EndTransfer.
- 0002: ours (`3780edcc0`): skip the no-op Start Transfer when the End Transfer is still delayed; the delayed End
  Transfer runs at the next SETUP stage and its completion restarts queued requests.

A third patch we also run rate-limits the warning (it only limits log noise); it is a hardening extra and not included.

## Install
Apply 0001 and 0002, rebuild, flash. See `../docs/BUILDING-A-KERNEL.md` and `../docs/RECOVERY.md`.

## Undo
Flash the previous boot image.

## Status and limits
- Fixes a crash seen on our kernel with USB networking; not tested on other kernels. Unrelated to charging (fix 05).
- 0002 is our own and not sent upstream.
