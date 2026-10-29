# 15 - Desktop crash when a Chromium (or Zen) in a distrobox container runs

Running Chromium (or Zen) in a distrobox crashes the desktop.

Keywords: Plasma Mobile KWin crash Chromium distrobox, postmarketOS distrobox Chromium crash compositor, OnePlus 6T Linux phone Chromium container KWin, Zen browser distrobox crash Wayland

**Status: works (2026-10; Chromium in an Alpine/Debian distrobox container, postmarketOS v26.06 host).**

## Symptom
Starting or using Chromium inside a distrobox container makes `kwin_wayland` crash with SIGBUS, which kills
your session.

## Root cause
Container and host share the home directory, so both use the same Mesa shader-cache folder. The container's
Mesa (22.x) and the host's Mesa (26.x) write different formats to one memory-mapped index file; the host's
KWin then reads the container's version and gets a SIGBUS.

## What it does
`00-mesa-cache` gives the container its own cache directory by setting `MESA_SHADER_CACHE_DIR`.

## Install (inside the container)
```
sudo mkdir -p /etc/chromium.d && sudo cp 00-mesa-cache /etc/chromium.d/
```
For other programs in the container, export the same variable in the container's shell profile.
Delete the shared cache once on the host: `rm -rf ~/.cache/mesa_shader_cache*`.

## Related: Zen browser crash
Zen crashed in its RDD (media decoder) process. Setting `media.hardware-video-decoding.enabled` to `false` in
the profile's `user.js` avoided it. A bandaid; no root cause found.

## Undo
Delete `/etc/chromium.d/00-mesa-cache` in the container.

## Known limits
- Only covers Chromium launcher scripts that read `/etc/chromium.d/`.
