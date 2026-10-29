# 24 - Phone freezes and needs a 10 second power hold: automatic restart and a crash log

Random freezes where only a long power-button hold helps, and no log is left behind.

Keywords: OnePlus 6T postmarketOS freeze, fajita mainline random hang power button hold, pmOS pstore ramoops crash log, systemd RuntimeWatchdogSec, sdm845 UFS write hang jbd2, Linux phone auto reboot after hang, kernel.panic reboot

**Status: the storage-hang watcher worked on a real hang (2026-10-06). The hardware-watchdog and panic-reboot settings are NOT
proven by a real event, and the cause of the storage hang is unknown. This is a mitigation, not a cure.**
Generic postmarketOS setup, no custom kernel needed.

## Symptom
The phone freezes (UI dead, often after heavy disk writes) and stays frozen until you hold power. After the reboot the journal has nothing from the freeze.

## What we found
Two freezes (2026-09-29, 2026-10-06) were silent storage hangs: a write to the UFS root disk never completed (journal commit
waiting forever, no kernel error lines). Because PID 1 keeps running, the hardware watchdog never fires. Earlier
`ufshcd_wait_for_pending_cmds: timedout waiting for doorbell to clear` lines were the only hint; heavy bulk writes looked like the trigger.

## What it does
- `iowatch.sh` + `iowatch.service`: every 30 s write and fsync a small file on the root filesystem. If that does not finish
  for 180 s: dump all blocked tasks (`sysrq w`, `m`) into the kernel log, then reboot (`sysrq b`). It runs from a copy of busybox
  in RAM so the watcher cannot itself block on the disk. The stacks survive the reboot in ramoops.
- `50-freeze-watchdog.conf`: `RuntimeWatchdogSec=30s`. Caveat: on this phone a watchdog bite ends in Qualcomm CrashDump mode (a power hold is still needed), so this alone does not reboot a hard hang.
- `50-freeze-sync.conf`: journald writes to disk every 10 s instead of 5 minutes, so the lead-up to a hang is kept.
- `90-panic-reboot.conf`: `kernel.panic = 5`: reboot 5 s after a panic instead of waiting for the watchdog.

## Install (as root)
```
install -d /usr/local/lib/iowatch && install -m755 iowatch.sh /usr/local/lib/iowatch/
cp iowatch.service /etc/systemd/system/ && systemctl enable --now iowatch
install -D 50-freeze-watchdog.conf /etc/systemd/system.conf.d/50-freeze-watchdog.conf && systemctl daemon-reexec
install -D 50-freeze-sync.conf /etc/systemd/journald.conf.d/50-freeze-sync.conf && systemctl restart systemd-journald
install -D 90-panic-reboot.conf /etc/sysctl.d/90-panic-reboot.conf
```
The unit expects `/bin/busybox` and `/lib/ld-musl-aarch64.so.1` (postmarketOS default).

## After a freeze
Read the newest files in `/var/lib/systemd/pstore/` (`console-ramoops-0`, `dmesg-ramoops-*`) first; look for `iowatch: root-fs write+sync stuck`. Then `journalctl --list-boots`.

## Undo
`systemctl disable --now iowatch`, delete the unit and `/usr/local/lib/iowatch`, delete the three `.conf` files, `systemctl daemon-reexec`.

## Status and limits
- A long power hold wipes RAM, so that crash log can be lost. Reboots done by iowatch keep it.
- Not a fix for the hang itself. Later kernels may have fixed it.
