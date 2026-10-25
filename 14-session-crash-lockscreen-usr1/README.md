# 14 - Whole desktop session dies when the lock screen is used

**Status: works (Plasma 6.6.6, postmarketOS v26.06, 2026-09-26 onward).**

## Symptom
Occasionally, locking or unlocking the phone ends your whole session: you are back at the login screen
with every app closed.

## Root cause
`kscreenlocker` calls `kill(0, SIGUSR1)` when its lock greeter is not running. PID 0 means "every process in my
process group", which includes the whole session, and SIGUSR1 kills them.

## What it does
`usr1guard.c` is a tiny shared library (loaded with `LD_PRELOAD` into KWin only) that drops exactly that one call
and unsets itself in processes other than `kwin_wayland_wrapper`. `kwin-usr1-guard.conf` is the systemd drop-in that
loads it. This hides the effect; the proper fix belongs in kscreenlocker.

## Install
```
mkdir -p ~/.local/lib/kwin-usr1-guard
cc -shared -fPIC -o ~/.local/lib/kwin-usr1-guard/usr1guard.so usr1guard.c
mkdir -p ~/.config/systemd/user/plasma-kwin_wayland.service.d
cp kwin-usr1-guard.conf ~/.config/systemd/user/plasma-kwin_wayland.service.d/
systemctl --user daemon-reload      # takes effect at next login
```

## Undo
Delete the drop-in, `systemctl --user daemon-reload`, log in again.

## Known limits
- BANDAID: a preload shim hides the effect and can go wrong if KWin's start-up changes. Not tested with other KWin versions.
- Needs a C compiler (`apk add build-base`).
