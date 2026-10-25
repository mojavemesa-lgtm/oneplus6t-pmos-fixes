# OnePlus 6T (fajita) on postmarketOS: a collection of fixes

Fixes and workarounds for the OnePlus 6T running postmarketOS with the mainline-based SDM845 kernel
and Plasma Mobile. Each folder is one fix with its own README: symptom, cause, what the fix does,
install, undo, status and limits.

**Made by a non-developer with an AI assistant (Claude). Tested on one phone only. No warranty.**
Some patches are admitted hacks and some are rough. Read the README of a fix before using it.

## Tested on

- Device: OnePlus 6T (fajita), Snapdragon 845
- postmarketOS v26.06, Plasma Mobile (Plasma 6.6.6)
- Kernel: sdm845-mainline tag `sdm845-7.1-rc1-r0` (7.1.0-rc1-sdm845); the Bluetooth call test kernel was `7.1.0-rc1-sdm845-hfp`
- Time frame: September to October 2026

## WARNING: flashing a kernel can brick your phone

Several fixes (01, 04, 05) need a custom kernel written to the phone's boot partition. A bad kernel
means a phone that does not boot. The bootloader is not touched, so you can nearly always recover with
fastboot, but only if you made a backup first.

Quick recovery: hold Volume Up + Volume Down + Power to reach fastboot, connect to a PC and run
`fastboot flash boot_a boot-backup.img` (the backup you made before). If your phone boots from slot b, use
`boot_b`. `fastboot boot new.img` tries a kernel from RAM without writing it. Full steps, including the
last-resort EDL mode and traps to avoid, are in [docs/RECOVERY.md](docs/RECOVERY.md). Read it BEFORE
flashing anything.

## The fixes

- [01 Bluetooth headset calls](01-bluetooth-headset-calls/): voice calls through Bluetooth earbuds, both directions, HD voice. Works in our tests; needs a custom kernel (patches on top of Dylan Van Assche's branch).
- [02 VoLTE chipmunk audio](02-volte-chipmunk-fix/): sped-up voice on wideband calls. Works; no root needed.
- [03 Verizon picture messages (MMS)](03-verizon-mms/): works, Verizon only; contains a labelled bandaid.
- [04 Bluetooth chip hang](04-bt-chip-hang/): upstream kernel fix, confirmed since flashing; a recovery script as stopgap.
- [05 USB-C charging, USB-PD and tethering](05-usb-c-pd-charging-tethering/): works with the chargers we tried; kernel patches, partly David Heidelberg's RFC; sent upstream, not merged.
- [06 Calls app freezes with the screen off](06-calls-freeze-screen-off/): works for 26 screen-off dials; an incoming locked-screen call is not tested yet.
- [07 Mobile data "connected" but dead](07-cell-data-watcher/): watcher script, a bandaid, works in testing.
- [08 Texts lost with two SMS apps](08-two-sms-apps-lose-texts/): works; pick one app.
- [09 Chatty daemon restart under Plasma](09-chatty-autorestart-plasma/): works.
- [10 SIM slot fix at login](10-sim-slot-fix/): works on our phone; the slot number depends on yours.
- [11 Auto-rotate dead at boot / portrait on wake](11-autorotate-and-wake-rotation/): works; the powerdevil part needs a package rebuild.
- [12 Wallpaper falls back to default](12-wallpaper-falls-back-to-default/): one-line patch, works on 6.6.6, overwritten by updates.
- [13 Gwenview crash on close](13-gwenview-close-crash/): patch (also proposed to KDE), works, needs a package rebuild.
- [14 Session killed by the lock screen](14-session-crash-lockscreen-usr1/): preload shim, a bandaid, works.
- [15 Distrobox Chromium crashes KWin](15-distrobox-chromium-kwin-crash/): one config line, works.

Camera: not covered here. Please see lolren's separate project at https://github.com/lolren/oneplus6t-pmos-fixes .

## Other documents

- [docs/RECOVERY.md](docs/RECOVERY.md): backing up and recovering the boot partition
- [docs/BUILDING-A-KERNEL.md](docs/BUILDING-A-KERNEL.md): how we built the kernel
- [NOTICE.md](NOTICE.md): credits for the people whose work this builds on

## Known gaps

The kernel patches were developed on our own tree and have not been re-applied to a pristine checkout for this repo;
expect small context fixes. Everything is as-is.

## License

Everything here is **GPL-2.0-or-later**, see [LICENSE](LICENSE). Kernel patches follow the kernel's GPL-2.0 license;
scripts are released under the same license for simplicity. Upstream patches keep their authors' lines.
