# 12 - Wallpaper falls back to the default picture

**Status: works (plasma-workspace 6.6.6, postmarketOS v26.06, 2026-09-26). A package upgrade overwrites it.**

## Symptom
Sometimes after boot the custom wallpaper is replaced by the default image, and it stays that way.

## Root cause
A race in the wallpaper plugin's `ImageStackView.qml`: while the new image is still loading
(status Loading), the code treats "not Ready" as a failure and falls back to the default. It should only
react to a real error.

## What it does
One-line patch: change `status !== Image.Ready` to `status === Image.Error`.

## Install
```
cd /
sudo patch -p0 < /path/to/ImageStackView-race.patch   # path inside patch: usr/share/plasma/wallpapers/org.kde.image/contents/ui/ImageStackView.qml
```
Keep a backup first: `sudo cp -a /usr/share/plasma/wallpapers/org.kde.image/contents/ui/ImageStackView.qml{,.orig}`. Then log out and in.

## Undo
Restore the backup, or `sudo apk fix plasma-workspace`.

## Known limits
- Overwritten by every plasma-workspace update; re-apply.
- Only tested on 6.6.6.
