# 25 - Alert slider gives no feedback (no chime or buzz when you move it)

Moving the OnePlus 6T's ring / vibrate / silent switch gives nothing you can feel or hear, so you cannot tell which mode you are in.

Keywords: OnePlus 6T postmarketOS alert slider, fajita mainline ring silent switch feedback, pmOS alert slider vibrate chime, feedbackd profile sdm845, Plasma Mobile mute switch, Linux phone hardware ring switch, ABS_SND_PROFILE

**Status: works on our phone (2026-10-07, Plasma Mobile). The chime sound is a taste choice; change it in the script.**

## Symptom
The slider changes the feedbackd profile (full / quiet / silent) correctly but gives no cue when you move it.

## Background (useful on its own)
The slider is the input device "Alert slider" (`/dev/input/by-path/platform-alert-slider-event`, driver `gpio-keys`). It reports one
absolute axis (code 34, `ABS_SND_PROFILE`) with values 0, 1, 2 (silent, vibrate, ring: the usual OnePlus order). The package
`feedbackd` ships `fbd-alert-slider`, which turns it into the feedbackd profile `silent` / `quiet` / `full`.
Read it: `busctl --user get-property org.sigxcpu.Feedback /org/sigxcpu/Feedback org.sigxcpu.Feedback Profile`.

## What the fix does
`slider-feedback` (a user service) watches the feedbackd `Profile` property. After the slider settles (350 ms, because moving from
silent to ring passes the middle notch) it plays: ring = chime + 120 ms buzz, vibrate = buzz, silent = nothing.

## Install
Needs Python with `gi` (py3-gobject3), `paplay` (pulseaudio-utils) and feedbackd.
```
install -m755 slider-feedback ~/.local/bin/
mkdir -p ~/.config/systemd/user && cp slider-feedback.service ~/.config/systemd/user/
systemctl --user enable --now slider-feedback
```
Test without touching the slider:
`busctl --user set-property org.sigxcpu.Feedback /org/sigxcpu/Feedback org.sigxcpu.Feedback Profile s quiet`

## Undo
`systemctl --user disable --now slider-feedback` and delete the two files.

## Status and limits
- The chime path in the script is the Ocean sound theme; change `CHIME` if you do not have it.
- Which physical notch is which is the standard OnePlus layout plus the profile names, not checked on every unit.
