# 11 - Auto-rotate dead after boot; screen turns back to portrait on wake

**Status: works (Plasma 6.6.6, postmarketOS v26.06, 2026-09/10).**

## Symptoms
1. After boot, auto-rotate does nothing ("No accelerometer").
2. If you rotate to landscape and the screen sleeps, it wakes up in portrait.

## Root causes
1. `iio-sensor-proxy` starts about 20 s after boot, but the sensor hub (SLPI) registry loads only after about 23 s
   via `hexagonrpcd`. The proxy gives up and stays dead until restarted.
2. Plasma's power daemon (`powerdevil`) re-applies a screen configuration saved at the time it started,
   which includes the old rotation, when waking the screen.

## What it does
- `wait-for-sensors.conf`: a drop-in that makes `iio-sensor-proxy` wait until 35 s of uptime.
- `powerdevil-dont-revert-rotation.patch`: a source patch for powerdevil 6.6.6 (`kwinbrightness.cpp/.h`):
  read the live configuration and carry over only brightness and dimming.

## Install
Drop-in (root):
```
sudo mkdir -p /etc/systemd/system/iio-sensor-proxy.service.d
sudo cp wait-for-sensors.conf /etc/systemd/system/iio-sensor-proxy.service.d/
sudo systemctl daemon-reload
```
The powerdevil patch needs a rebuilt `powerdevil` package (from the Alpine aports tree, add the patch, `abuild -r`) and
reinstall; nothing is installable as a script. The patch is against 6.6.6 and may not apply to other versions.

## Undo
Delete the drop-in and `daemon-reload`; `sudo apk fix powerdevil` returns the stock package.

## Known limits
- Boot is delayed for the sensor service only, not for the rest of the system.
- Part 2 depends on the exact powerdevil version.
