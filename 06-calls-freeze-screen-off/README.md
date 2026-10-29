# 06 - GNOME Calls freezes after several calls with the screen off

Calls app freezes after several calls with the screen off.

Keywords: OnePlus 6T postmarketOS GNOME Calls freeze, Plasma Mobile Calls app hang screen off, pmOS KWin freeze dialing, Linux phone call app frozen, fajita calls screen off

**Status: 26 screen-off dials OK after the change (Plasma Mobile 6.6.6, postmarketOS v26.06, 2026-10).
NOT yet tested: a real incoming call arriving while the screen is locked.**

## Symptom
After about five calls made or received with the screen off, the Calls app hangs (frozen window, no
ringing, call screen never appears). Restarting Calls fixes it temporarily.

## Root cause (as far as known)
KWin's `scale` effect (the zoom animation when windows open or close) holds on to the buffers of
windows that are hidden while the screen is off. Every call adds a window, and eventually the
compositor stops answering Calls. Turning the effect off removes the problem.

## What the fix does
Turns off the `scale` effect (windows no longer zoom open) and makes the Calls daemon restart itself if it
crashes (`calls-daemon-restart.conf`: `Restart=on-failure`), because Plasma does not do that for the
autostart unit.

## Install
```
kwriteconfig6 --file kwinrc --group Plugins --key scaleEnabled false
qdbus6 org.kde.KWin /KWin reconfigure          # or: qdbus org.kde.KWin /KWin reconfigure
mkdir -p ~/.config/systemd/user/'app-org.gnome.Calls\x2ddaemon@autostart.service.d'
cp calls-daemon-restart.conf ~/.config/systemd/user/'app-org.gnome.Calls\x2ddaemon@autostart.service.d'/restart.conf
systemctl --user daemon-reload
```
(Check the unit name with `systemctl --user list-units | grep -i calls`.)

## Undo
```
kwriteconfig6 --file kwinrc --group Plugins --key scaleEnabled true
qdbus6 org.kde.KWin /KWin reconfigure
rm ~/.config/systemd/user/app-org.gnome.Calls*/restart.conf && systemctl --user daemon-reload
```

## Related repair
If Calls shows an empty history or will not start after a crash, its call-history database
(`~/.local/share/calls/records.db`) may have a mismatched write-ahead log. With Calls stopped, back up the
three files `records.db`, `records.db-wal`, `records.db-shm`, delete the `-wal` and `-shm` files, and start Calls.

## Known limits
- This is a workaround for the symptom; the exact KWin leak is not reported upstream by us.
- Loses the window open/close zoom animation (and the overview effect that shares the plugin).
