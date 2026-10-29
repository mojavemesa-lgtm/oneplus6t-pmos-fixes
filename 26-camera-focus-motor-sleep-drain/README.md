# 26 - Camera focus motors stay powered and drain the battery in sleep

The two rear camera focus motors are powered all the time, even with the camera closed and the phone asleep.

Keywords: OnePlus 6T postmarketOS battery drain sleep camera, fajita mainline lc898217xc VCM always on, pmOS deep sleep 55 mA, sdm845 main_cam_vaf sub_cam_vaf regulator, wireplumber libcamera monitor battery, unbalanced disables for main_cam_vaf, Linux phone camera actuator runtime PM

**Status: tested 2026-10-29 on kernel 7.1.0-rc1-sdm845 (our own build, see fix 18), postmarketOS v26.06.
Short testing so far: 4 suspend cycles with no warnings, both rear cameras still stream.**

## Symptom
With deep sleep working (fix 18), the phone's sleep current stayed at about 55 to 64 mA instead of the
about 25 mA it can reach. About 30 mA of that was the two camera focus motors (voice coil motors, VCM,
driver `lc898217xc`), whose power rails (`main_cam_vaf` and `sub_cam_vaf`, 2.8 V, plus `lvs1`) were on
around the clock.

## Cause
The `lc898217xc` driver in the kernel this was tested on (from the sdm845-mainline tree) powers the motor
whenever its `/dev/v4l-subdev*` node is open, and powers it off only when the last user closes it.
WirePlumber's libcamera monitor opens every camera node at login and keeps them open for as long as it
runs. So the motors were never powered off, camera in use or not.

A second, smaller bug showed up once the motor could actually power off: the driver has only runtime
power-management callbacks and none for system sleep. The power-management core then treats it as having
none, and on resume from sleep marks it "active" without calling its power-on code. The rails stay off
while the driver thinks they are on, and the next power-off turns them off twice, which prints a kernel
warning: `unbalanced disables for main_cam_vaf`.

## What the fix does (`kernel/`)
- 0001: the motor's power now follows the camera sensor it belongs to, not open file handles. At probe
  the driver finds the sensor whose device-tree node has `lens-focus` pointing at it and adds a
  runtime-PM device link (`DL_FLAG_STATELESS | DL_FLAG_PM_RUNTIME`), so the motor is powered exactly
  while its sensor is (that is, while the camera streams). Opening and closing the node no longer powers
  it. A focus position written while the motor is off is kept and written to the motor when it powers
  on. If no linked sensor is found the driver falls back to the old behaviour.
- 0002: adds system sleep callbacks (`pm_runtime_force_suspend` / `pm_runtime_force_resume`), which
  removes the "unbalanced disables" warning.

Both patches are ours and not sent upstream.

## Result
A/B test on our phone, same conditions, asleep and unplugged: about 25 mA with the fix, 55 to 64 mA
without. 0 warnings over 4 `rtcwake` suspend cycles. Both rear cameras (IMX519 main and IMX376K) still
stream at 30 fps with `cam`, and the focus motor is active only while streaming.

## Install (module only, no kernel flash)
Only one module changes, so you can rebuild and replace just that module. You need the source tree and
config of the kernel you are running (the module must match it exactly). In that tree, apply the patches
and build the folder (building only `lc898217xc.ko` as a single target fails in modpost, so build the
whole folder):
```
git am 0001-*.patch 0002-*.patch
make M=drivers/media/i2c modules
zstd -19 drivers/media/i2c/lc898217xc.ko
```
On the phone, keep a backup of the old module, then put the new one in place and reboot:
```
M=/lib/modules/$(uname -r)/kernel/drivers/media/i2c/lc898217xc.ko.zst
sudo cp $M ~/lc898217xc.ko.zst.orig
sudo cp lc898217xc.ko.zst $M
sudo depmod -a
sudo reboot
```
If your kernel stores modules uncompressed (`.ko`) or with another compression, match that instead.

## How to check
With the camera closed:
```
cat /sys/bus/i2c/drivers/lc898217xc/*/power/runtime_status
dmesg | grep lc898217xc
```
Both should say `suspended` (the main motor is `16-0072` on our phone). `dmesg` should show
`power follows sensor ...` for each motor. While a camera app is streaming, that camera's motor says
`active`. After a suspend and resume, `dmesg | grep unbalanced` should print nothing.

## No kernel rebuild? Workaround
Stop WirePlumber while the phone sleeps (and start it again on wake), or turn off its libcamera monitor
permanently with a drop-in file, for example `~/.config/wireplumber/wireplumber.conf.d/no-libcamera.conf`:
```
wireplumber.profiles = {
  main = {
    monitor.libcamera = disabled
  }
}
```
The drop-in costs you the cameras in PipeWire-based camera apps; apps that use libcamera directly still
work. Stopping WirePlumber also stops audio routing until it is started again.

## Undo
Put the backup back and reboot:
```
sudo cp ~/lc898217xc.ko.zst.orig /lib/modules/$(uname -r)/kernel/drivers/media/i2c/lc898217xc.ko.zst
sudo depmod -a
sudo reboot
```
A kernel package upgrade also replaces the module with the stock one.

## Status and limits
- Tested on one phone, one kernel, one day. Not tested on a stock postmarketOS kernel.
- Relies on the device tree linking each sensor to its motor with `lens-focus` (the OnePlus 6T tree does).
- The front camera has no focus motor and is not affected.
