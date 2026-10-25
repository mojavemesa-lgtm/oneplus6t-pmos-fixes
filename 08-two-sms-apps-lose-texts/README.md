# 08 - Texts vanish when two messaging apps are installed (Spacebar + Chatty)

**Status: works (postmarketOS v26.06, Plasma Mobile, 2026-09/10).**

## Symptom
Some incoming SMS never show up in the app you use, or appear and then disappear.

## Root cause
Both Spacebar (KDE) and Chatty (GNOME/Phosh) run a background daemon that reads new SMS from the modem
and then **deletes them from the modem**. Whichever app gets there first takes the message; the other app
never sees it. Having both daemons running splits your messages between two databases.

## What it does
Pick one app and stop the other app's daemon from starting. Here we keep Chatty and hide Spacebar's
daemon: `org.kde.spacebar.daemon.desktop` is a copy of the autostart entry with `Hidden=true`, which
disables it in your user's autostart.

## Install
```
mkdir -p ~/.config/autostart
cp org.kde.spacebar.daemon.desktop ~/.config/autostart/
systemctl --user stop app-org.kde.spacebar.daemon@autostart.service
```
(To keep Spacebar and drop Chatty instead, do the same with Chatty's autostart/daemon entry.)

## Undo
`rm ~/.config/autostart/org.kde.spacebar.daemon.desktop` and log in again.

## Known limits
- Messages already deleted from the modem are gone; you only prevent future loss.
- Spacebar as an app can still be launched; it just will not receive in the background.
