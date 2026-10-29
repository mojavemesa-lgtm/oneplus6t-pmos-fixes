# 19 - Phone hangs when the screen turns off (GPU, GMU, sync_state)

The screen goes dark and the phone freezes; only holding the power button for 10 seconds brings it back.

Keywords: OnePlus 6T postmarketOS screen off freeze, fajita mainline black screen hang, sdm845 freeze when screen turns off, Plasma Mobile hard hang power button hold, msm drm a6xx gmu timeout, fw_devlink.sync_state=timeout, MDSS icc_set_bw hang, Adreno 630 suspend

**Status: in our everyday kernel since 2026-10-27 and no screen-off hang since. HONEST CAVEAT: we never checked whether a
stock postmarketOS kernel shows the same hang, so we cannot prove these changes are what fixed it on our phone.**
They are good changes in their own right (two are upstream), but treat this as "likely", not "proven".

## Symptom
With a kernel from the same family as ours (7.1-rc1 sdm845), the display pipeline sometimes dies at the moment the
screen turns off. The phone does not respond, nothing in the log, only a long power hold helps.

## Likely causes (from reading code and logs, not from a stock-kernel reproduction)
1. The Adreno GPU's RSC sleep handshake never ran: since a 2025 change the test in `a6xx_rpmh_stop()` was inverted, so
   after a normal GMU start the GPU's RPMh state was never stopped. Upstream commit `d9108bfdb746` (Shivam Rawat,
   Qualcomm; in v7.2-rc4) fixes that and halts the GMU CM3 core before the GPU is powered down.
2. GMU firmware start can need longer than the default timeout: upstream `ba970587a0e1` (Rob Clark).
3. The GMU device node has no driver bound, so the `gcc`/`gpucc` clock controllers never get their `sync_state` and the
   display (MDSS) interconnect bandwidth request can hang. Booting with `fw_devlink.sync_state=timeout` forces
   `sync_state` after about 24 s. (A runtime attempt to force it crashed our phone; do it on the command line.)

## What the fix does
- `kernel/0001`: upstream d9108bfdb746 backport.
- `kernel/0002`: upstream ba970587a0e1 backport.
- Kernel command line: add `fw_devlink.sync_state=timeout`. For a pmbootstrap build this goes in the device's
  `deviceinfo_kernel_cmdline`; for a boot image you build yourself, in the `--cmdline` of `mkbootimg`.

## Install
Apply both patches, rebuild, flash (`../docs/BUILDING-A-KERNEL.md`, `../docs/RECOVERY.md`), add the command line option.
Check: `cat /proc/cmdline`; `cat /sys/devices/platform/soc@0/100000.clock-controller/state_synced` says 1.

## Undo
Flash your previous boot image.

## Status and limits
- Patch 0001 also changes GPU behaviour on every runtime-PM cycle; upstream has one open regression report for
  a different SoC (X1E80100 power-off). We saw none on the 6T.
- Newer kernels (7.2 and later) already contain 0001; 0002 may be there too.
- An earlier, more invasive attempt that powered the display down differently crashed on screen-off and was dropped.
