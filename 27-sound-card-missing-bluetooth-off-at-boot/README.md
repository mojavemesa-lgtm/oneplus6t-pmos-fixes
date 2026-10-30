# 27 - Sound card missing when Bluetooth is off at boot

If Bluetooth is switched off (blocked) when the phone boots, there is no audio at all until the next reboot.

Keywords: OnePlus 6T postmarketOS no sound after boot bluetooth off, fajita mainline sound card missing, /proc/asound/cards empty, PulseAudio auto_null "muted, can't turn it on", devices_deferred "Bluetooth SCO Capture: codec dai not found", sdm845 WCN3990 SLIMbus EPROBE_DEFER, systemd-rfkill saved block, slim_set_laddr_on_demand

**Status: tested 2026-10-29 on kernel 7.1.0-rc1-sdm845 (our own build, see fix 01), postmarketOS v26.06.
Short testing so far: one phone, one day. Needs a new kernel image (a core change) plus the codec module.**

## Depends on fix 01
This only matters on kernels where the sdm845 sound card has the Bluetooth SCO links on SLIMBUS_7, that is
the kernel from [01](../01-bluetooth-headset-calls/) (Dylan Van Assche's `wcn3990-bluetooth-hfp-v4` branch
plus our patches 0001 to 0007). Without those links the card never waits for the WCN3990 and you do not
have this bug. The patch here is made against a tree that already contains all of 01 (in particular the
per-channel state of its patch 0002, which `wcn3990_start_stream()` comes from). We checked with
`git apply --check` against exactly that tree; we did not check it against a tree with only part of 01.

## Symptom
Bluetooth is blocked at boot (systemd-rfkill restores a saved block, for example after you turned
Bluetooth off before shutting down). Then:
- `/proc/asound/cards` is empty and PulseAudio only has `auto_null` ("muted, can't turn it on")
- `/sys/kernel/debug/devices_deferred` (as root) shows the sound card waiting with
  `Bluetooth SCO Capture: codec dai not found`
- Turning Bluetooth on later does not bring the sound back. Only a reboot with Bluetooth unblocked does.

## Cause
The WCN3990 chip appears on the SLIMbus (gets a logical address) only while its Bluetooth part is
powered. The SLIMbus core's `slim_device_probe()` returns `-EPROBE_DEFER` for any device without a logical
address, and the `wcn3990` codec registered its audio interfaces (DAIs) only when the device reported
`SLIM_DEVICE_STATUS_UP`. The sdm845 sound card has Bluetooth SCO links to those DAIs, so it stayed
deferred. Nothing retries a deferred probe when Bluetooth comes up later.

## What the fix does (`kernel/`)
One patch (two commits squashed), three files:
- SLIMbus core: new exported `slim_set_laddr_on_demand()` (the flag sits at the end of `struct
  slim_device`). A driver that calls it from `probe()` binds without a logical address.
- `wcn3990` codec: calls it, sets up its regmaps and registers the ASoC component in `probe()`, and fetches
  the logical addresses of the chip and its interface device in a new `wcn3990_enumerate()` when a stream
  starts (like Android's btfm driver does). With Bluetooth off, starting a SCO stream fails with `-ENODEV`
  and the sound card still exists.

## Result
Tested on our phone 2026-10-29:
- Boot with Bluetooth blocked: sound card present, speaker works, nothing deferred, one `slim_probe`.
- Unblocking Bluetooth later and making a call with earbuds (HFP) works; the log shows
  `WCN3990 logical address 0xcf, IFC 0xce` at the first SCO stream, and a clean shutdown afterwards.
- Normal boot with Bluetooth on: fine.

## Install
The change is in the SLIMbus core, which is built into the kernel, so you need a new kernel image as well
as the `snd-soc-wcn3990` module (and both must match). Read `../docs/RECOVERY.md` and make a boot backup
first. Apply on your tree (the one from 01) and build as in `../docs/BUILDING-A-KERNEL.md`:
```
git am kernel/0001-*.patch
```

## No kernel rebuild? Workaround
Keep Bluetooth unblocked at boot by deleting the saved block before `systemd-rfkill` restores it. A
oneshot unit, for example `/etc/systemd/system/rfkill-unblock-bt.service`:
```
[Unit]
Description=Forget saved Bluetooth rfkill block
Before=systemd-rfkill.service
DefaultDependencies=no

[Service]
Type=oneshot
ExecStart=/bin/rm -f /var/lib/systemd/rfkill/platform-898000.serial:bluetooth

[Install]
WantedBy=sysinit.target
```
Then `sudo systemctl enable rfkill-unblock-bt.service`. The name `platform-898000.serial:bluetooth` is the
one on our phone; check `ls /var/lib/systemd/rfkill/`. You can still turn Bluetooth off after boot.

## Undo
Boot the backup kernel image you made (or flash it back, see `../docs/RECOVERY.md`) and put back the old
module. For the workaround: `sudo systemctl disable --now rfkill-unblock-bt.service` and delete the unit.

## Status and limits
- One phone, one kernel, one day. Not tested on a stock postmarketOS kernel.
- With Bluetooth off, SCO calls through the phone's own Bluetooth cannot work (there is no chip to talk
  to); the stream error is the intended behaviour.
- The patch is ours and not sent upstream.
