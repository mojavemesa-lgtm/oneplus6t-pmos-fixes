# 02 - VoLTE "chipmunk" call audio

The other person sounds like a sped-up chipmunk on some calls.

Keywords: OnePlus 6T postmarketOS VoLTE chipmunk voice, fajita mainline call audio fast, pmOS wideband AMR-WB sped up voice, sdm845 q6voice topology 69488, Linux phone HD voice calls garbled, Plasma Mobile call audio

**Status: works. Confirmed on the earpiece on 2026-09-23, kernel 7.1.0-rc1-sdm845, postmarketOS v26.06.**
Needs no root and no custom kernel.

## Symptom
On some calls the other person sounds like a sped-up chipmunk (or you do to them). It happens when the
call uses the wideband voice codec (AMR-WB, "HD voice") over VoLTE, for example with callers on the
same carrier network.

## Root cause
The phone's voice DSP (q6voice) applies a "topology" (a chain of audio filters) to the call. The kernel
defaults (TX 69489 echo-cancel/noise-suppression, RX 69495) mishandle wideband audio on this phone.
Setting both to 69488 ("none", no processing) makes the audio correct. Credit: the fix was found by a
commenter calling themselves "Hephaestus" on postmarketOS pmaports issue #3713.

## What it does
`volte-chipmunk-fix.sh` sets two mixer controls (`VoiceMMode1 TX Topology` and `VoiceMMode1 RX Topology`)
to 69488. It looks the controls up by name, because their numeric ids change between kernels. It retries
for about a minute at login, since the sound card appears a little after the session starts.
The `.service` runs it once per login.

## Install
```
install -m755 volte-chipmunk-fix.sh ~/.local/bin/
mkdir -p ~/.config/systemd/user && cp volte-chipmunk-fix.service ~/.config/systemd/user/
systemctl --user enable --now volte-chipmunk-fix
```
Check: `amixer -c 0 cget name='VoiceMMode1 TX Topology'` should show 69488.

## Undo
```
systemctl --user disable --now volte-chipmunk-fix
amixer -c 0 cset name='VoiceMMode1 TX Topology' 69489
amixer -c 0 cset name='VoiceMMode1 RX Topology' 69495
```

## Known limits
- Trade-off: no echo cancellation or noise suppression on your voice. Speakerphone may echo (untested).
- Bluetooth calls: untested with this setting (see fix 01, which sets the mixers itself).
- Sound card number 0 is assumed; change `-c 0` if `aplay -l` shows otherwise.
