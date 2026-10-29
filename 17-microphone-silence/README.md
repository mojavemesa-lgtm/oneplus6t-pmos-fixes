# 17 - Phone microphone records only silence

Recordings, voice notes and dictation on the OnePlus 6T come out as pure silence even though the speaker works.

Keywords: OnePlus 6T postmarketOS microphone not working, pmOS no sound recording, fajita mainline mic silent, sdm845 wcd934x capture zeros, Linux phone microphone digital silence, arecord all zeros, Plasma Mobile voice recorder silent

**Status: works. Kernel patch in everyday use since 2026-10-27 (kernel 7.1.0-rc1-sdm845-hfp tree), recordings carry real sound again.
We did not run a long dictation re-test.** Needs a custom kernel (the codec driver is a module, see below).

## Symptom
The built-in microphone records digital silence: `arecord` writes a file of zeros, level meters stay flat, voice
recorders and dictation get nothing. Playback is fine. It can work for a while after you played some sound and
then stop, which makes it look random.

## Cause
In the mainline `wcd934x` codec driver (the audio chip in the OnePlus 6T, SDM845) the capture endpoints
(`AIF1 CAP`, `AIF2 CAP`, `AIF3 CAP`) have no dependency on the codec's master clock (`MCLK`). The capture chain
(ADC, decimators, SLIMbus transmit) needs that clock, but nothing switches it on for recording. Capture only
worked while the clock happened to be left on by earlier playback. When nothing else keeps it on (for example
after we let the audio chips sleep), the microphone returns zeros.

How we proved it: while recording, `cat /sys/kernel/debug/asoc/*/wcd934x-codec*/dapm/MCLK` said `Off`.
With the clock forced on (silence played to another sink), a 1 kHz tone was recorded with a normal peak.

## What the fix does
`kernel/0001-ASoC-wcd934x-capture-path-needs-MCLK.patch` adds three DAPM routes
(`AIF1 CAP`, `AIF2 CAP`, `AIF3 CAP` need `MCLK`). Seven added lines, nothing else.

## Install
Apply the patch to the sdm845-mainline `sdm845-7.1-rc1-r0` tree (see `../docs/BUILDING-A-KERNEL.md`).
`wcd934x` is a module, so after a kernel build you can replace only `snd-soc-wcd934x.ko` in
`/lib/modules/<version>/` and run `sudo depmod`, then reboot. Read `../docs/RECOVERY.md` before flashing a kernel.

## Undo
Put the original module back (keep a copy first), `sudo depmod`, reboot. For a flashed kernel see `../docs/RECOVERY.md`.

## Status and limits
- Not upstream as far as we know; a kernel package update will bring the bug back until it is re-applied.
- Checked on one phone, one kernel tree. The patch applies to the tree described in the main README.
