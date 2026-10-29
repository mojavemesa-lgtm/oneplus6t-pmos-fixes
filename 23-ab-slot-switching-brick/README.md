# 23 - Switching boot slots (A/B) bricked the phone: fixed qbootctl and a safe kernel-test flow

WARNING FOR EVERY SDM845 postmarketOS USER: `qbootctl -s b` on the OnePlus 6T can leave the phone unable to boot.

Keywords: OnePlus 6T postmarketOS qbootctl bricked, fajita A/B slot switch bootloop fastboot, sdm845 qbootctl -s b unbootable, Failed to load/authenticate boot image Device Error, fastboot boot fails after slot switch, OnePlus 6T EDL GPT repair, pmOS test kernel safe slot b, ABL ValidateSlotGuids

**Status: works on our phone. Slot switching tested in both directions; the safe test flow has been used for every kernel since
2026-10-27. A udev race found on 2026-10-28 is fixed in the script.**

## Symptom
After `sudo qbootctl -s b` (postmarketOS `qbootctl` package) the phone loops into the bootloader with
"Failed to load/authenticate boot image: Device Error". Even `fastboot boot` fails. `fastboot --set-active=a` then made it worse
(neither slot booted). Recovery needed EDL mode and a GPT repair.

## Cause
The OnePlus bootloader (ABL) keeps slot state twice in the GPT: in attribute bits and in the partition type GUIDs (the active
slot carries the real type GUIDs, the inactive slot a marker GUID). The linux-msm `qbootctl` always writes the real GUID to the
`_a` partitions and the marker to `_b`, whatever slot you ask for. `-s b` therefore marked B active but left it with the marker
GUID. ABL refused B and its fallback moved the marker onto A as well. Switching also moves the UFS boot LUN through
`/dev/bsg/ufs-bsg0`; without `CONFIG_SCSI_UFS_BSG` that step is silently skipped. `qbootctl -m`, `-c` and the status dump are safe; only `-s` is dangerous.

## What the fix does
- `qbootctl/0001-...patch` (for `bootctrl_impl.c` of https://github.com/linux-msm/qbootctl): the requested slot gets the real
  GUID and the other the marker; every `<name>_a`/`<name>_b` pair in `/dev/disk/by-partlabel` is swapped, like ABL does
  (including LOGO, bluetooth, dsp, mdtp, odm); cross-LUN pairs (xbl) only get the active flag. Not sent upstream yet.
- `abtest/abtest.py`: kernel-test flow. The everyday kernel lives on slot A (the "home" slot, `/etc/ab-home-slot`). A test kernel
  is written to `boot_b` and gets exactly ONE boot; slot B is never marked "successful". Any later restart (crash, watchdog,
  10 s power hold) makes the bootloader mark B unbootable and fall back to A by itself. Commands (root): `abtest status`,
  `abtest flash IMG`, `abtest go`, `abtest rearm`, `abtest home`, `abtest promote` (B to A, A backed up first), `abtest mark-if-home`.
- `abtest/gptstate.py`: read-only GPT check (active slot has real type GUIDs, other has the marker, boot LUN 1 for A, 2 for B).

## Install
1. Kernel with `CONFIG_SCSI_UFS_BSG=y` (check `/dev/bsg/ufs-bsg0`).
2. Make slot B's firmware a copy of slot A's (xbl, abl, tz, hyp, aop, dtbo, vbmeta, modem, dsp, bluetooth ...: `dd` each `_a` to
   `_b`, compare checksums) and `boot_b` a copy of `boot_a`. Back up the original slot B partitions first.
3. Build the patched qbootctl (`git am`, `meson setup build && ninja -C build`), install over `/usr/bin/qbootctl` (keep the
   original). An `apk upgrade` of qbootctl brings the buggy one back; `abtest` refuses to switch if the sha256 differs from the
   one in `/usr/local/lib/abtest/qbootctl-fixed.sha256` (create that file from your fixed binary).
4. Install `abtest.py` as `/usr/local/bin/abtest`; `echo a | sudo tee /etc/ab-home-slot`; make the qbootctl boot-time service
   call `abtest mark-if-home` instead of `qbootctl -m` (systemd drop-in).
5. Test: `sudo abtest flash my-kernel.img && sudo abtest go`.

## Undo
`sudo abtest home`, or reboot once more (ABL falls back to A). Restore a boot partition from a backup: `../docs/RECOVERY.md`.

## Status and limits
- Only the OnePlus 6T was tested. Other sdm845 phones probably behave the same; check with `gptstate.py` before trusting it.
- If the phone is already bricked this way: EDL (`05c6:9008`) plus a GPT repair is the way out. Our repair scripts are not included yet.
- When in doubt use `abtest go --no-reboot`, check, then reboot.
