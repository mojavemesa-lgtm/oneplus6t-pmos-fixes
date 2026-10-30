# 28 - Random storage hangs (UFS clock scaling): keep the storage clock at full speed

The phone slowly locks up (apps hang, then the whole UI) because a write to the internal storage never finishes.
This stops it from happening. Folder [24](../24-freeze-watchdog-auto-restart/) is the safety net that reboots
after such a hang; this folder is the workaround that prevents it.

Keywords: OnePlus 6T postmarketOS storage hang, fajita UFS freeze, sdm845 ufshcd timedout waiting for doorbell to clear, devfreq 1d84000.ufshc dvfs failed with (-16), clkscale_enable, clkgate_enable, jbd2 folio_wait_writeback hang, Linux phone freezes after days

**Status: in daily use since 2026-10-06. No storage hang and no doorbell warning since (24 days at the time of writing);
before it we saw a few doorbell warnings a day and a full hang every one to two weeks. This is a workaround, not a
kernel fix. Generic postmarketOS setup, no custom kernel needed.**

## Symptom
- Every so often (days apart) the phone freezes and needs a long power-button hold, or, with fix 24 installed, reboots by itself.
- In the kernel log, hours or days before: `ufshcd-qcom 1d84000.ufshc: ufshcd_wait_for_pending_cmds: timedout waiting for doorbell to clear`
  and `devfreq 1d84000.ufshc: dvfs failed with (-16) error`.
- With fix 24's blocked-task dump: `jbd2` waiting in `folio_wait_writeback`, other tasks in `do_get_write_access`. A storage
  request was sent and never completed, with no error logged.

## Cause (as far as we know)
The UFS driver changes the storage clock up and down with load ("clock scaling") and stops the clock when idle
("clock gating", which goes through the hibern8 low-power state). The doorbell warning comes from the scaling path: before
changing speed it waits for pending requests, and they had been stuck for over a second. Occasionally one never comes back
and the disk stalls for good. A similar report on another Qualcomm device: commaai/vamOS issue 83 (hibern8 exit racing clock
gating). The real fix belongs in the kernel driver; we have not found it.

## What it does
At boot, `ufs-fullspeed.sh`:
1. sets the UFS devfreq minimum to its maximum (200 MHz on ours) and waits until the clock is there,
2. then turns clock scaling off (`clkscale_enable = 0`),
3. and clock gating off (`clkgate_enable = 0`). Auto-hibern8 is left as it is.

**The order matters.** If you only run `echo 0 > clkscale_enable` while the clock happens to be at its low step, it stays
there: we got stuck at 50 MHz, about 15 MB/s. Pinned at full speed we measured about 300 MB/s read and 190 MB/s write.

## Install (as root)
```
install -d /usr/local/lib/ufs-fullspeed && install -m755 ufs-fullspeed.sh /usr/local/lib/ufs-fullspeed/
cp ufs-fullspeed.service /etc/systemd/system/ && systemctl enable --now ufs-fullspeed
```
Check: `journalctl -b -t ufs-fullspeed.sh` should show `freq=200000000 clkscale=0 clkgate=0` (or your device's maximum).

## Undo
`systemctl disable ufs-fullspeed`, delete the unit and `/usr/local/lib/ufs-fullspeed`, reboot.

## Status and limits
- Battery: the storage no longer slows down or stops its clock when idle. We did not see a difference we could measure; our
  deep-sleep figures in [18](../18-deep-sleep-kernel/) (about 26 mA asleep) were taken with this running.
- With scaling off, the doorbell warning can no longer appear (it came from the scaling path), so "no warnings" alone does not
  prove the hang is gone; the real test is weeks without a hang. Keep fix 24 installed as a safety net.
- If hangs still happen with this on, the next things to try are turning auto-hibern8 off as well, or a kernel patch.
- The sysfs path is for the sdm845 UFS controller (`1d84000.ufshc`); other phones use a different address.
