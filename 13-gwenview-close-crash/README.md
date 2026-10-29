# 13 - Gwenview crashes when it is closed (or on pinch)

Gwenview crashes when you close it or pinch to zoom.

Keywords: Gwenview crash on close Plasma Mobile, pmOS Gwenview pinch crash, Linux phone image viewer crash, KDE Gwenview touch gesture crash, OnePlus 6T postmarketOS Gwenview

**Status: works (Gwenview 26.04.2, postmarketOS v26.06, 2026-10). Upstream: KDE merge request !376.**

## Symptom
Gwenview (image viewer) crashes on exit or on a pinch gesture on the touch screen.

## Root cause
`m_pinchGesture` in `waylandgestures` is never initialised to null, and is used in `init()`/`release()`
before it is set.

## What it does
Initialises it to `nullptr` and guards `init()`/`release()` with `isActive()`.

## Install
You need to rebuild the `gwenview` package with this patch (Alpine `aports/community/gwenview`, add the patch to
`source=` and `abuild -r`).

## Undo
`sudo apk fix gwenview` restores the stock package.

## Known limits
- A rebuilt package; it will be overwritten by the next Gwenview upgrade until KDE merges the fix.
