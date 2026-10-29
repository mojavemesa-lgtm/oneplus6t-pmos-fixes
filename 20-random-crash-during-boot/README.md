# 20 - Random crash about 17 seconds into boot (Qualcomm CrashDump mode)

The phone sometimes dies during boot and shows a "Qualcomm CrashDump" screen; it needs a long power-button hold.

Keywords: OnePlus 6T postmarketOS boot crash, fajita mainline random reboot at boot, sdm845 CrashDump 05c6:900e, qcom_glink_native_rx panic, fastrpc NULL pointer dereference, Linux phone boot hang adsp cdsp, pmOS kernel panic in interrupt

**Status: fixed on our phone. In the everyday kernel since 2026-10-27, 15 of 15 test restarts clean (before: roughly 1
boot in 8 to 12). The glink guard is in the current kernel tree (k30); the fastrpc fix is NOT in that tree's source and was installed as a rebuilt module (see below).**

## Symptom
During boot, about 17 s in (just as the audio and compute DSPs load their firmware), the kernel panics:
`Kernel panic - Fatal exception in interrupt`, `qcom_glink_native_rx`. The bootloader then sits in Qualcomm CrashDump
mode (USB id `05c6:900e`). Earlier we mistook this for a "DSP hang".

## Cause
Two races in the same window, when the DSP sends a message before the receiving driver is ready:
1. `qcom_glink_rx_data()` calls `pm_wakeup_ws_event(channel->ept.rpdev->dev.power.wakeup, ...)`. `ept.rpdev` is only set
   later in `qcom_glink_create_ept()`, so a data packet arriving in between (for example for the fastrpc channel while
   fastrpc is still probing) dereferences NULL in interrupt context. That line is not in upstream; it came with the
   sdm845 base tree.
2. `fastrpc_rpmsg_callback()` can run before `fastrpc_rpmsg_probe()` has set up its data (set drvdata before lock init,
   no NULL check). Upstream commit `5401fb4fe10f` (Mukesh Ojha, Qualcomm, CVE-2026-53158 in our notes).

## What the fix does
- `kernel/0001`: use a local copy of `ept.rpdev` with a NULL check (built-in code, needs a new kernel image).
- `kernel/0002`: upstream `5401fb4fe10f`. `fastrpc` is a module: we build it and replace `fastrpc.ko` in
  `/lib/modules/<version>/kernel/drivers/misc/`.

## Install
Apply 0001 (and 0002) to the tree, rebuild, flash, copy the new `fastrpc.ko` (compressed `.ko.zst` on postmarketOS,
keep the original), `sudo depmod`. See `../docs/BUILDING-A-KERNEL.md`, `../docs/RECOVERY.md`.

## Undo
Flash the previous boot image; put the original `fastrpc.ko.zst` back.

## Status and limits
- Check that your kernel is not newer than the fix: 0002 is upstream in later kernels. 0001 is not upstream yet.
- Our kernel tree k30 contains 0001; applying 0002 to that tree is separate (module only), applied to the installed
  module on the phone on 2026-10-27.
- If a CrashDump still happens after this, read `/var/lib/systemd/pstore/` for the panic text: it is a different cause.
