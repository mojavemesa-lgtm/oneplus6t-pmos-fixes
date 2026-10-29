# 22 - Bluetooth earbuds or keyboard disconnect every time the phone sleeps

Bluetooth devices drop as soon as the phone suspends and have to reconnect when it wakes.

Keywords: OnePlus 6T postmarketOS Bluetooth disconnects suspend, fajita mainline Bluetooth sleep drops connection, pmOS bluetooth keyboard wakes phone, sdm845 WCN3990 btqca suspend, Linux phone Bluetooth keep connection during suspend, Plasma Mobile Bluetooth earbuds sleep

**Status: works on our phone since 2026-10-28/29. With a Bluetooth keyboard connected the phone was asleep 92 percent of the
time in a doze test (same as without the keyboard) and a key press woke it. Delivered as two replaced kernel modules.**

## Symptom
Every suspend disconnects Bluetooth devices (the kernel closes all links before sleeping). The reconnect on wake takes seconds
and keeps waking the phone again.

## Cause
`hci_suspend_sync()` disconnects every link and unconfigures the controller. The WCN3990 chip can keep a link alive while the
host sleeps, as Android does. Also the chip's debug log stream (on after every start) generates traffic that keeps waking the host.

## What the fix does (`kernel/`)
- 0001 `bluetooth.ko`: new module parameter `keep_links_on_suspend` (default off): do not drop connections for suspend.
- 0002 `btqca.ko`: switch the SoC debug log off on the WCN3990 at every Bluetooth start (before, only some chips).

## Install
Apply both patches, rebuild the two modules, copy them over the installed ones (`.../kernel/net/bluetooth/bluetooth.ko*` and
`.../kernel/drivers/bluetooth/btqca.ko*` in `/lib/modules/<version>/`, keep the originals), `sudo depmod`, then
```
echo "options bluetooth keep_links_on_suspend=1" | sudo tee /etc/modprobe.d/bt-keep-links.conf
sudo reboot
```
**Reboot. Do not unload and reload the Bluetooth modules live: that froze our phone.**

## Undo
Delete `/etc/modprobe.d/bt-keep-links.conf`, put the original modules back, `sudo depmod`, reboot.

## Status and limits
- The modules live in `/lib/modules`: a kernel package upgrade overwrites them.
- A Bluetooth scan or auto-connect service running during sleep still wakes the phone. We stop ours while asleep (personal tooling, not included).
- Some devices (our keyboard) send a battery report every ~5 s that the chip cannot filter, so wake bursts remain on a charger.
- Does not change Bluetooth call audio (fix 01).
