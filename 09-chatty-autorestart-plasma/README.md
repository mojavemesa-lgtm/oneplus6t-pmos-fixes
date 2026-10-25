# 09 - Chatty does not come back after it crashes (Plasma Mobile)

**Status: works (tested 2026-09-25 onward, postmarketOS v26.06, Plasma Mobile).**

## Symptom
If the Chatty background daemon crashes or is killed, no more SMS notifications arrive until you log in again.

## Root cause
Chatty's shipped user unit says `Requisite=gnome-session-initialized.target`, which only exists in a
GNOME/Phosh session. Under Plasma, D-Bus activation after a crash fails with a "dependency" error. The
XDG autostart route does not honour `X-GNOME-AutoRestart`.

## What it does
A local copy of the unit without that requirement, with `Restart=always`, started from
`plasma-workspace.target`; plus a `Hidden=true` autostart entry so Chatty is not started twice.

## Install
```
mkdir -p ~/.config/systemd/user/plasma-workspace.target.wants ~/.config/autostart
cp sm.puri.Chatty-daemon.service ~/.config/systemd/user/
ln -s ../sm.puri.Chatty-daemon.service ~/.config/systemd/user/plasma-workspace.target.wants/
cp sm.puri.Chatty-daemon.desktop ~/.config/autostart/
systemctl --user daemon-reload && systemctl --user restart sm.puri.Chatty-daemon
```

## Undo
Remove those three files/links, then `systemctl --user daemon-reload`.

## Known limits
- The unit is a copy of the package's: after a Chatty update diff it against `/usr/lib/systemd/user/sm.puri.Chatty-daemon.service`.
- Combine with fix 08 if Spacebar is also installed.
