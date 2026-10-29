# 01 - Bluetooth headset calls (HFP) on the OnePlus 6T

Calls through Bluetooth earbuds or a headset have no sound, or one direction only.

Keywords: OnePlus 6T postmarketOS Bluetooth headset calls, fajita mainline HFP no audio, pmOS Bluetooth earbuds phone call microphone, sdm845 WCN3990 SLIMbus SCO, Linux phone HD voice mSBC, Plasma Mobile Bluetooth call audio

**Status: works for us, on one phone, with two different earbuds and a PC acting as a headset.**
Real cellular (VoLTE) calls, audio both ways, HD voice (mSBC) included. Tested by the maintainer
2026-10-16 to 2026-10-21 on postmarketOS v26.06, kernel `7.1.0-rc1-sdm845` (sdm845-mainline tag
`sdm845-7.1-rc1-r0` plus the patches below), Plasma Mobile, PulseAudio 17. **This needs a custom
kernel. Read `../docs/RECOVERY.md` first.**

## The symptom

You pair Bluetooth earbuds, music works, but when you answer a phone call the voice stays on the
phone's earpiece and nothing reaches the earbuds. Or the call connects to the earbuds and is **silent**
(sometimes). Or the mic of the earbuds is not used. After a call, music may look like it is playing but
stay silent.

## Why it happens (root causes, there are several)

1. **The WCN3990 Bluetooth chip does not carry call audio over the Bluetooth data link (HCI).** On this
   phone voice audio goes chip -> SLIMbus -> the audio DSP (ADSP), like on Android. Mainline Linux had
   no driver for that path, so PulseAudio's own "HFP" device is dead (its writes fail). Dylan Van
   Assche's `wcn3990-bluetooth-hfp-v4` kernel branch adds the pieces (second SLIMbus controller, a
   WCN3990 ASoC codec, SLIMBUS_7/8 audio ports). It was close but "no audio comes through".
2. **The SLIMbus driver never tells the ADSP that a stream was removed** (`qcom-ngd-ctrl` has no
   `.disable_stream`). The next stream on the same channel often leaves the chip's receive port inactive
   -> silent call. This was most of the silence: about 1 call in 4 worked, now 13 of 13.
3. The WCN3990 codec used **one "enabled" flag for both receive and transmit**, which leaked the
   transmit stream on every call.
4. The q6afe driver picked the wrong SLIMbus device for SLIMBUS_7/8 (it must check the DAI id, not the
   AFE hardware id).
5. **q6voice only picks up which audio ports to use when the voice stream is created**, i.e. when
   `q6voiced` opens the voice PCM at dial time. Switching the mixers afterwards had no effect. A
   userspace helper has to make `q6voiced` close and reopen the PCMs after the switch.
6. In a call the headset has to switch from music mode (A2DP) to phone mode (HFP) and back. PulseAudio's
   dead HFP sink reports a delay that grows with the call, and streams that move off it come back padded
   with that much silence. That is the "music is silent after a call" bug.
7. Calls were narrowband (8 kHz). With a small change they can be wideband mSBC (16 kHz, "HD voice").

## What the fix does

Kernel (`kernel/`, apply in order on top of Dylan's branch, see below):

- 0001 slimbus: send channel removal to the ADSP when a stream is disabled (the big one).
- 0002 wcn3990 codec: separate state for the receive and transmit channels.
- 0003 q6afe: use SLIMbus device 2 for SLIMBUS_7/8, compared on the DAI id.
- 0004 Bluetooth: use the offload data path for eSCO (hack-ish, see the patch text).
- 0005 HACK: LPCM data format on the SLIMbus stream for the WCN3990.
- 0006 device tree: the OnePlus 6/6T dai-links for the Bluetooth SCO ports.
- 0007 wideband (mSBC): maps PulseAudio's mSBC request to controller-side mSBC and adds a card control
  `BT SCO Rate` (8000/16000) so the SLIMBUS_7 side runs at the right rate. If the backend rate does not
  match the air codec you get a silent downlink and a faint crunch uplink.
- Do **not** change `transport_unit_size` to 0 (Android's value): audio becomes zeros here. 16 stays for
  CVSD and 1 for mSBC.

Userspace (`userspace/`):

- `bt-hfp-call` + `systemd-user/bt-hfp-call.service`: watches `callaudiod`'s AudioMode. When a call starts
  and an HFP headset is connected it switches the card to HFP, sets `BT SCO Rate` from the negotiated
  codec, points the voice mixers at SLIMBUS_7, and asks `q6voiced` to reopen the voice PCMs. After the
  call it restores A2DP. It also pauses media players for the call (MPRIS, via `playerctl`) and resumes
  them, and keeps other streams off PulseAudio's HFP sink (they go to a stand-in "call_hold" sink).
  The proven order matters: headset into HFP first, then mixers + PCM reopen.
- `q6voiced/q6voiced-sigusr1-reopen.patch` + `q6voiced-reopen.conf`: a patch to the pmOS `q6voiced` daemon
  (v0.2.1) so `SIGUSR1` closes and reopens the voice PCMs, and the systemd drop-in that runs it.
- `bt-hfp-bridge` + `bt-hfp-bridge-trigger` (+ service): **optional.** Exposes the headset mic/speaker to
  PulseAudio outside calls through MultiMedia5/6 <-> SLIMBUS_7. Needed only if you want, for example, a
  wake-word listener on the headset mic. Note it keeps the headset in the poor-sounding phone mode; the
  trigger script's policy actually puts headsets back to A2DP when no call is up. Skip it if unsure.
- `pulseaudio/enable-msbc.sh`: sets `module-bluetooth-discover enable_msbc=true` in your per-user
  `default.pa` (HD voice). `client-noautospawn.conf`: keeps these helpers from ever auto-starting
  PulseAudio.
- No ALSA UCM changes: the scripts set the mixers directly.
- The scripts contain optional hooks for a "call greeting" feature (files `call-greeting.pending`, a lock
  file). They do nothing when that feature is absent.

## Install steps

**1. Kernel.** The kernel base is not in this repository; get it yourself:

```
git clone https://gitlab.com/sdm845-mainline/linux.git && cd linux
git checkout sdm845-7.1-rc1-r0
# Dylan Van Assche's branch (WCN3990 SLIMbus HFP), add his commits on top:
git remote add dylan https://gitlab.com/dylanvanassche/linux.git && git fetch dylan wcn3990-bluetooth-hfp-v4
# cherry-pick his WCN3990 / SLIMBUS_7/8 / second SLIMbus controller / oneplus-common commits
# (we used 13 commits: wcn3990 initial codec, SLIMBUS_7/8 q6dsp + sdm845 ports, secondary SLIMbus
#  controller dts, dual Slimbus address hack, two qmi encoder fixes by Bjorn Andersson, oneplus enable).
git am /path/to/01-bluetooth-headset-calls/kernel/000*.patch
```

His branch changes over time; the patches here were made against the state of early October 2026 and may
need small context fixes. Then follow `../docs/BUILDING-A-KERNEL.md`. We ran the result as a separate
kernel release (`7.1.0-rc1-sdm845-hfp`), and for the SLIMbus/WCN3990/Bluetooth changes as
**hand-copied modules** (`slim-qcom-ngd-ctrl`, `snd-soc-wcn3990`, `snd-soc-sdm845`, `bluetooth`) into
`/lib/modules/<release>/` followed by a reboot. A live `rmmod`/`modprobe` does NOT re-register the codec.

**2. Userspace** (as your normal user, on the phone):

```
install -m755 userspace/bt-hfp-call userspace/bt-hfp-bridge userspace/bt-hfp-bridge-trigger ~/.local/bin/
mkdir -p ~/.config/systemd/user/bt-hfp-call.service.d
cp userspace/systemd-user/bt-hfp-call.service ~/.config/systemd/user/
cp userspace/systemd-user/bt-hfp-call.service.d-noautospawn.conf ~/.config/systemd/user/bt-hfp-call.service.d/noautospawn.conf
cp pulseaudio/client-noautospawn.conf ~/.config/pulse/        # create the directory if needed
sh pulseaudio/enable-msbc.sh
sudo apk add playerctl callaudiod alsa-utils                  # if not installed
```

**3. q6voiced reopen.** Build `q6voiced` with `q6voiced/q6voiced-sigusr1-reopen.patch` (source:
https://gitlab.postmarketos.org/postmarketOS/q6voiced , needs `tinyalsa-dev`), install the binary as
`/usr/local/bin/q6voiced-reopen`, then:

```
sudo mkdir -p /etc/systemd/system/q6voiced.service.d
sudo cp userspace/q6voiced/q6voiced-reopen.conf /etc/systemd/system/q6voiced.service.d/reopen.conf
sudo systemctl daemon-reload && sudo systemctl restart q6voiced
```

Allow the script to send the signal without a password (replace `youruser`):

```
echo 'youruser ALL=(root) NOPASSWD: /usr/bin/systemctl kill -s USR1 q6voiced' | sudo tee /etc/sudoers.d/q6voiced-reopen
```

**4. Reboot, pair the headset, make a call.** Then `systemctl --user enable --now bt-hfp-call`.
`~/.cache/bt-hfp-call.log` shows each step. A call to a time-announcement line is a good test.

## How to undo

```
systemctl --user disable --now bt-hfp-call bt-hfp-bridge-trigger
rm ~/.local/bin/bt-hfp-call ~/.local/bin/bt-hfp-bridge ~/.local/bin/bt-hfp-bridge-trigger
rm -r ~/.config/systemd/user/bt-hfp-*
sudo rm /etc/systemd/system/q6voiced.service.d/reopen.conf && sudo systemctl daemon-reload && sudo systemctl restart q6voiced
```

Kernel: put the stock `boot_a` and modules back (`../docs/RECOVERY.md`). Quick partial revert of HD voice
only: set `enable_msbc=false` (calls go back to narrowband).

## Known limits

- **Custom kernel required**; not upstream. A pmOS kernel update replaces your kernel/modules: re-apply.
- Patches 0004 and 0005 are admitted hacks. Treat the whole set as a working proof, not as polished
  upstream material. (They were sent to Dylan Van Assche to rework as he likes.)
- Uplink (headset mic into the call) was proven end to end only with a PC as the headset (a recording line
  played back the beeps); with real earbuds it was confirmed by listening. Not tested on other earbuds.
- The first stream after boot is fine; we saw about half the calls fail on a PC test rig *before* patch 0001
  and 13/13 after. Intermittent silence may still exist; the test is the WCN3990 register `0x080`
  (receive port status) which reads 0 when bad.
- A headset connected through `bt-hfp-bridge` stays in phone mode: music sounds bad. Use A2DP policy
  (the shipped trigger script) or skip the bridge.
- The call recorder of a call-recording setup cannot see a Bluetooth call (far side goes DSP -> SLIMBUS_7).
- Wideband calls need the headset to negotiate mSBC; if a call is silent, check `dmesg` for
  `codec id 5` and the wcn3990 `rate 16000` line and the log line "... 16000 Hz".
- Bluetooth address: this phone gets a new random address each boot in our setup, which is irrelevant to
  the fix but explains paired devices not reconnecting after a reboot for us.
- Not tested: Android Auto, LE Audio (impossible: the chip is Bluetooth 5.0 without ISO), other Qualcomm
  phones (the SHIFT6mq author reported the codec only initialised with a speaker connected).
