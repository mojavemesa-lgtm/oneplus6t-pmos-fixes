# 18 - Real deep sleep (battery drain while the screen is off)

The phone never goes into its deepest sleep state on mainline Linux, so the battery drains fast even with the screen off.

Keywords: OnePlus 6T postmarketOS battery drain sleep, fajita mainline suspend, sdm845 deep sleep, Snapdragon 845 AOSD CXSD never reached, pmOS standby drain, Linux phone suspend wake alarm late, sdm845 interconnect BCM ALC SH4, qcom_stats aosd, RPMh, PDC SPMI wake

**Status: works on our phone. Kernel #30 (built 2026-10-28, everyday kernel on both boot slots since 2026-10-29).
Calls, texts, the power key and alarms wake it. Still open: Wi-Fi-on and charger-in cases, Bluetooth wake bursts.**
Needs a custom kernel. Not upstream.

## Symptom
On the stock mainline kernel the phone drains roughly 50 mA with the screen off (an owner-measured figure on stock
postmarketOS; Android on the same phone about 25 mA). The SoC counters for the deepest sleep modes
(`/sys/kernel/debug/qcom_stats/aosd` and `cxsd`, "count") stay at 0 forever. After a naive fix the phone does reach
deep sleep but then wakes minutes late: power key and alarm clock are seen very late.

## Causes (three, found with a lot of measuring)
1. **Votes left by the bootloader.** The bootloader leaves bus (BCM) votes on two RPMh blocks, `ALC` (0x50010) and
   `SH4` (0x5002c). Mainline's `sdm845` interconnect driver has no node for them, so nobody drops the votes, and the
   always-on processor refuses to power the SoC down. We found this by RAM-booting Android's recovery on the same phone,
   comparing state with mainline, and zeroing candidate votes by hand: ALC plus SH4 together gave the first
   deep sleep ever seen on mainline here. (Zeroing one alone, or `IP0` which the modem data path needs, froze the phone.
   Do not experiment with this on your daily phone.)
2. **Wake interrupt wiring.** The device tree wires the PMIC arbiter interrupt (power key, RTC alarm, charger) straight
   to the GIC interrupt controller, which is powered down in deep sleep. The interrupt is only latched and arrives
   minutes later. Routing it through the PDC (wake-capable) interrupt controller, as downstream and newer SoCs do, fixes it.
3. **Small leaks that stop the SoC from collapsing:** UFS lane clocks keep the oscillator (`bi_tcxo`) busy
   (enable count 37 down to 8 after the fix), UFS and display keep CX power-domain votes through suspend, and the
   camera I2C controller leaks a runtime-PM reference over resume.
   A separate crash we hit on the way: if the RSC hardware reports "TX done" late, mainline `rpmh` returned early and
   the freed request was later written (use-after-free Oops after a deep-sleep wake). Patch 0003.

## What the patches do (`kernel/`, apply in order)
- 0001 device tree: SPMI arbiter interrupt through `pdc_intc` (cause 2).
- 0002 `sdm845` interconnect: ALC and SH4 added as node-less BCMs and zeroed at `sync_state` (cause 1).
  Logs `dropped 2 unclaimed BCM vote(s)`. Deliberately NOT IP0.
- 0003 `rpmh`: keep waiting after a TX-done timeout instead of freeing the request.
- 0004 UFS: enable only the lane clocks (upstream commit `f07317a8d57f`, Nitin Rawat, Qualcomm).
- 0005 UFS: drop the OPP vote in `ufshcd_suspend()` and restore it in resume (ours).
- 0006 `i2c-qcom-cci`: system sleep via `pm_runtime_force_suspend/resume` (upstream `b08c9857aa1f`).
- 0007 / 0008 display: DSI and DPU stop zeroing the OPP behind the clocks' back (upstream `06b7ba2065`, `811c38907eab`).

`modemmanager/0006-...patch` is an optional ModemManager change (see "Modem" below).

## Measured results (our phone, our tools, early tests)
- Before: `aosd`/`cxsd` counters never move.
- RAM-booted test kernel, 60 s suspend: counters +42 in 50 s, a 30 s RTC alarm woke it after 28 s (on time).
- Everyday kernel, charger in: +83 counts in 61 s. Power-key tap wakes immediately. A call wakes it and rings in about
  3 s; a text arrives in 3 s.
- Unplugged: about 26 mA while asleep, 57 mA average with the phone in a pocket (mixed use). The stock figure above
  is a single rough owner measurement, not a controlled test.

## Needed besides the kernel
- **Something has to suspend the phone** (power key, `systemctl suspend`, or your own idle logic). The sleep daemon we
  use is tied to our own setup and is not included. With the plain systemd suspend the kernel part applies as is.
- **Calls wake the phone only if the modem wake switch is on:** `echo enabled | sudo tee
  /sys/bus/rpmsg/devices/*IPCRTR*/power/wakeup` (default is disabled; mainline only wake-enables IPA by default).
  We also turn the Wi-Fi radio off before sleeping, otherwise it wakes the phone often.
- Boot with `fw_devlink.sync_state=timeout` (see fix 19). Our reading, not proven: the interconnect `sync_state` that
  drops the votes only fires when all consumers have bound, which a driverless node can block.
- **Modem (optional).** With data connected, the modem wakes the phone every few seconds. Android avoids this by
  putting the modem in a "terse" state when the screen goes off. ModemManager has this since 1.24 but only on a
  logind sleep event; upstream MR 1511 (Michael Auer) adds the data-bearer part. `modemmanager/0006-...patch`
  (ours, on top of that MR and its bearer commit) lets a sleep daemon enter and leave terse mode with `SIGUSR1`/`SIGUSR2`.
  Built as an Alpine package (`1.25.95_git20260527`); a newer package version replaces it on `apk upgrade`.

## Install
Apply 0001-0008 to the sdm845-mainline `sdm845-7.1-rc1-r0` tree (`../docs/BUILDING-A-KERNEL.md`). UFS, interconnect and
rpmh are built into the kernel, so this is a full kernel rebuild and flash. Use the safe test flow of fix 23 (slot b with
automatic fallback) and `../docs/RECOVERY.md`. Check after boot: `dmesg | grep "unclaimed BCM"`;
`cat /sys/kernel/debug/qcom_stats/aosd` before and after a suspend (root).

## Undo
Flash your previous boot image (`../docs/RECOVERY.md`).

## Status and limits
- Patches were checked to apply in order on our baseline tree, not on a pristine tag. Context may need small fixes.
- Wi-Fi on, and charger plugged in, still wake the phone more than we like. Bluetooth devices cause wake bursts on a charger.
- A power-key press after a very long overnight charge once failed to wake the phone; root cause unproven, not claimed fixed.
- Measurements are from one phone and are not a benchmark.
