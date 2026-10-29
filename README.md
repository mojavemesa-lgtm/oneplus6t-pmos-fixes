# OnePlus 6T (fajita) on postmarketOS: a collection of fixes

Fixes and workarounds for the OnePlus 6T running postmarketOS with the mainline-based SDM845 kernel
and Plasma Mobile. Each folder is one fix with its own README: symptom, cause, what the fix does,
install, undo, status and limits.

**Made by a non-developer with an AI assistant (Claude). Tested on one phone only. No warranty.**
Some patches are admitted hacks and some are rough. Read the README of a fix before using it.

## Tested on

- Device: OnePlus 6T (fajita), Snapdragon 845 (sdm845)
- postmarketOS v26.06, Plasma Mobile (Plasma 6.6.6)
- Kernel: sdm845-mainline tag `sdm845-7.1-rc1-r0` plus the patches in this repo = release `7.1.0-rc1-sdm845-hfp`.
  The newest build ("k30") is the everyday kernel on both boot slots since 2026-10-29. Folders 17 to 22 were
  checked on that tree.
- Time frame: September to October 2026

## WARNING: flashing a kernel can brick your phone

Many fixes (01, 04, 05, 17 to 22) need a custom kernel written to the phone's boot partition. A bad kernel
means a phone that does not boot. The bootloader is not touched, so you can nearly always recover with
fastboot, but only if you made a backup first.

Quick recovery: hold Volume Up + Volume Down + Power to reach fastboot, connect to a PC and run
`fastboot flash boot_a boot-backup.img` (the backup you made before). If your phone boots from slot b, use
`boot_b`. `fastboot boot new.img` tries a kernel from RAM without writing it. Full steps, including the
last-resort EDL mode and traps to avoid, are in [docs/RECOVERY.md](docs/RECOVERY.md). Read it BEFORE
flashing anything.

Second warning: with a stock `qbootctl`, switching to boot slot b can leave the phone unbootable. Read
[23](23-ab-slot-switching-brick/) before you ever use slot b.

## The fixes, biggest wins first

The folder numbers never change; the list is ordered by how much each fix improves daily use.

- [18 Deep sleep and battery](18-deep-sleep-kernel/): the phone actually sleeps (about 26 mA asleep unplugged in our tests) instead of draining. Eight kernel patches plus a ModemManager patch.
- [02 VoLTE chipmunk audio](02-volte-chipmunk-fix/): sped-up voice on wideband calls. Works; no root needed.
- [17 Microphone records silence](17-microphone-silence/): one kernel patch for the capture path on WCN/WCD934x.
- [08 Texts lost with two SMS apps](08-two-sms-apps-lose-texts/): works; pick one app.
- [19 Screen-off hang (GPU/GMU)](19-screen-off-hang-gpu-gmu/): two kernel patches plus a kernel command-line option. Not checked on a stock pmOS kernel.
- [20 Random crash during boot](20-random-crash-during-boot/): glink and fastrpc fixes; 15 of 15 clean restarts.
- [04 Bluetooth chip hang](04-bt-chip-hang/): serial driver fixes (upstream), confirmed since flashing; a recovery script as stopgap.
- [05 USB-C charging, USB-PD and tethering](05-usb-c-pd-charging-tethering/): works with the chargers we tried; kernel patches, partly David Heidelberg's RFC; sent upstream, not merged.
- [23 A/B slot switching bricks the phone](23-ab-slot-switching-brick/): qbootctl patch plus a safe test script.
- [21 USB networking crash (dwc3)](21-usb-networking-crash-dwc3/): two kernel patches; only hours of testing so far.
- [01 Bluetooth headset calls](01-bluetooth-headset-calls/): voice calls through Bluetooth earbuds, both directions, HD voice. Needs a custom kernel (patches on top of Dylan Van Assche's branch).
- [22 Bluetooth stays connected in sleep](22-bluetooth-stays-connected-in-sleep/): keeps a Bluetooth keyboard or headset linked while the phone sleeps.
- [16 Camera: autofocus and colours](16-camera-autofocus-colour/): short path to install lolren's camera stack (rear cameras), plus a wider autofocus range. Front camera not fixed yet.
- [10 SIM slot fix at login](10-sim-slot-fix/): works on our phone; the slot number depends on yours.
- [07 Mobile data "connected" but dead](07-cell-data-watcher/): watcher script, a bandaid, works in testing.
- [09 Chatty daemon restart under Plasma](09-chatty-autorestart-plasma/): works.
- [11 Auto-rotate dead at boot / portrait on wake](11-autorotate-and-wake-rotation/): works; the powerdevil part needs a package rebuild.
- [24 Freeze watchdog and auto-restart](24-freeze-watchdog-auto-restart/): reboots with a blocked-task dump when storage hangs; generic settings only.
- [03 Verizon picture messages (MMS)](03-verizon-mms/): works, Verizon only; contains a labelled bandaid.
- [25 Alert slider feedback](25-alert-slider-feedback/): the hardware ring/vibrate/silent slider gives haptic or sound feedback.

## Plasma Mobile and app issues (not postmarketOS-specific)

These affect Plasma Mobile or single apps on any distribution, not just this phone.

- [06 Calls app freezes with the screen off](06-calls-freeze-screen-off/): works for 26 screen-off dials; an incoming locked-screen call is not tested yet.
- [12 Wallpaper falls back to default](12-wallpaper-falls-back-to-default/): one-line patch, works on 6.6.6, overwritten by updates.
- [13 Gwenview crash on close](13-gwenview-close-crash/): patch (also proposed to KDE), works, needs a package rebuild.
- [14 Session killed by the lock screen](14-session-crash-lockscreen-usr1/): preload shim, a bandaid, works.
- [15 Distrobox Chromium crashes KWin](15-distrobox-chromium-kwin-crash/): one config line, works.

## Other documents

- [docs/RECOVERY.md](docs/RECOVERY.md): backing up and recovering the boot partition
- [docs/BUILDING-A-KERNEL.md](docs/BUILDING-A-KERNEL.md): how we built the kernel
- [NOTICE.md](NOTICE.md): credits for the people whose work this builds on

## Known gaps

The kernel patches were developed on our own tree and checked with `git apply --check` against the commit
just before the first of them, not against a pristine release tag; expect small context fixes. Everything is as-is.

## Not yet included

- The userspace sleep daemon that works with fix 18 (still being cleaned up).
- Suspend while a charger is connected (not solved).
- EDL scripts that repair a damaged partition table (too risky to publish untested on other units).
- A hardening patch that rate-limits a dwc3 log message (a bandaid, left out on purpose).
- A safe-upgrade helper script (not verified enough).
- Front camera colours (fix 16 covers the rear cameras only).
- ModemManager data-bearer patches (not ready).

## Search terms

Fixes for the OnePlus 6T (codename fajita, models A6010 and A6013; the OnePlus 6 "enchilada" shares most of the
Snapdragon 845 / sdm845 hardware and many fixes may carry over, untested) running postmarketOS (pmOS) with a
mainline Linux kernel and Plasma Mobile: deep sleep and battery drain, microphone silence, VoLTE call audio,
Bluetooth headset calls, USB-C charging and tethering, boot crashes, A/B slot switching, camera.

## License

Everything here is **GPL-2.0-or-later**, see [LICENSE](LICENSE). Kernel patches follow the kernel's GPL-2.0 license;
scripts are released under the same license for simplicity. Upstream patches keep their authors' lines.
