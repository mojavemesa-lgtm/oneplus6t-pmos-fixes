# 16 - Camera: autofocus, colours, rear camera checker pattern

Camera: autofocus does not work, colours are wrong, or the rear camera shows a checker pattern.

Keywords: OnePlus 6T postmarketOS camera, fajita mainline camera autofocus, pmOS rear camera checker pattern, sdm845 IMX371 IMX519 camera Linux phone, Snapdragon 845 libcamera lolren, Plasma Mobile camera

**Status: rear cameras work (autofocus, decent colour). Tested 2026-10-09, kernel 7.1.0-rc1-sdm845,
postmarketOS v26.06. The front camera is still grey on our phone (see "Front camera" below).**

This is not our own fix. All the real work is **lolren's** camera stack
([lolren/oneplus6t-pmos-fixes](https://github.com/lolren/oneplus6t-pmos-fixes) and
[lolren/advanced-snapshot](https://github.com/lolren/advanced-snapshot)). Their repo does a lot of things
and is hard to follow, so this page is the short path we took to get just the camera part, plus one
setting change that our phone needed.

## Symptom
With stock postmarketOS the main camera is washed out and blurry, it never focuses (the lens motor is
never moved), colours look bad, the second rear camera shows a checker pattern, and the front camera
is grey / nearly black-and-white.

## Root cause
- postmarketOS uses libcamera's "simple" pipeline with a software ISP. It has **no autofocus**, so the
  focus motor (LC898217) just sits at one end. The motor itself is fine.
- There is **no tuning file for the main sensor (IMX519)** and no gain helper for it, so exposure and
  colour are guessed.
- The front sensor (IMX371) is read out in a full-resolution "Quad Bayer" mode that the software ISP
  can't turn into proper colour. That needs a kernel driver change (a binned mode), see below.

lolren's patched libcamera adds contrast autofocus, manual focus, gain helpers for all three sensors
and tuning files with colour correction. Their Advanced Snapshot app uses it (tap to focus, manual
focus slider).

## Install (rear cameras, no kernel change)
On the phone. First save the stock packages so you can go back:
```
mkdir -p ~/camera-backup && cd ~/camera-backup
apk fetch libcamera libcamera-ipa pipewire-spa-libcamera
```
Download lolren's camera release `runtime-r44-camera-r35` and check it:
```
mkdir -p ~/camstage && cd ~/camstage
for f in SHA256SUMS oneplus6t-camera-r35-r36-aarch64.tar.gz; do
  wget https://github.com/lolren/oneplus6t-pmos-fixes/releases/download/runtime-r44-camera-r35/$f
done
grep camera-r35-r36-aarch64.tar.gz SHA256SUMS | sha256sum -c   # must say OK
tar xzf oneplus6t-camera-r35-r36-aarch64.tar.gz
```
Install only the camera packages from `stage/candidate`:
```
cd ~/camstage/stage/candidate
sudo apk add --allow-untrusted --force-overwrite \
  aarch64/libcamera-99990.7.2-r35.apk aarch64/libcamera-ipa-99990.7.2-r35.apk \
  aarch64/pipewire-spa-libcamera-1.6.8-r8.apk \
  aarch64/advanced-snapshot-0.1.0-r36.apk noarch/advanced-snapshot-lang-0.1.0-r36.apk
```
(`--force-overwrite` is needed because their pipewire plugin replaces one file owned by `pipewire-libs`.
`--allow-untrusted` because the packages are signed with lolren's own key, not postmarketOS's; the
sha256 check above is what tells you the files are the ones they published.)

Then widen the autofocus range (next section) and open **Advanced Snapshot**. Restart the session
(or reboot) if the camera app was already open.

What we skipped on purpose:
- lolren's `install-camera-generation` script: in our try it pinned a helper package name that no
  longer downloads, so it stopped. Installing the packages by hand works.
- lolren's helper package (`oneplus6t-pmos-fixes-...-r44.apk`): it also installs an audio routing
  service, a mobile data watchdog and PipeWire config. Those clashed with our call audio fixes
  (01, 02, 07), so we left it out. The camera works without it.

## The one change we made: autofocus range
lolren's tuning lets autofocus search lens positions 400 to 800. On our phone the far-focus position
(landscapes, anything past a few metres) is about 200, so distant things never got sharp. We checked
this by moving the lens by hand while watching the preview: 0 is blurry (past infinity), about 200 is
sharp far away, 800 is already close-up. `widen-af-range.sh` copies lolren's tuning files for the two
rear cameras into `/etc/libcamera/ipa/simple/` (which overrides `/usr/share`) with the range set to
150 to 900:
```
sudo sh widen-af-range.sh
```
If your phone focuses fine far away with the stock 400..800, skip this. Units differ a little between
phones, so if distant things are still soft, lower 150 further.

## Build it yourself (NixOS, other distros, your own packages)
If you can't use lolren's postmarketOS packages, `patches/` has the plain source patches, taken out of
their pmaports packaging so you don't have to dig. These are **exactly** the files their r35 camera
release was built from: every file's SHA-512 matches the checksums in lolren's
`packaging/pmaports/0001-oneplus6t-camera-stack.patch`, and `patches/SHA256SUMS` lists them again. All of
it is lolren's work (MIT, `patches/LICENSE-lolren-MIT`), except libcamera `0001`-`0002`, which come from
postmarketOS's own libcamera package (Robert Mader, Collabora).

- `libcamera-0.7.2/` (23 patches, apply in number order on the `v0.7.2` tag): `0001`-`0002` = pmaports'
  base patches (turn on the software ISP for the simple pipeline). `0003`-`0006` = gain helpers and
  properties for IMX371/IMX376/IMX519. `0007`-`0023` = software-ISP controls: contrast autofocus,
  autofocus windows, manual focus (`LensPosition`), exposure, sharpness, white balance, colour matrix,
  test pattern. Checked 2026-10-30: all 23 apply cleanly on a fresh libcamera v0.7.2 clone.
- `pipewire-1.6.8/` (2 patches, on the `1.6.8` tag): lets the PipeWire libcamera plugin pass the
  autofocus and array controls through to apps. Only the `spa-libcamera` plugin changes. Applies cleanly.
  Without these, apps going through PipeWire (Snapshot) can't trigger autofocus.
- `kernel-sdm845/` (5 patches, postmarketOS `linux-postmarketos-qcom-sdm845` 7.1-rc1 tree):
  `0001`-`0003` = the **front camera** fix (IMX371 2304x1728 binned mode, the matching link frequency in
  the device tree, gain range). `0004` = IMX376 gain range, `0005` = IMX519 preview at 30 fps. All five
  apply cleanly in order on that tree. lolren's series has two more (`0006` panel brightness, `0007`
  venus video firmware); they aren't camera, so they aren't here. On another kernel version the
  line numbers may need a nudge.
- `tuning/` = lolren's tuning files for the three sensors (the same files their r35 package installs to
  `/usr/share/libcamera/ipa/simple/`). They need the patched libcamera; stock libcamera may reject some
  keys. Our wider autofocus range (section above) is `widen-af-range.sh`, applied on top of these.
- `gnome-snapshot-50.0/` (6 patches on GNOME Snapshot 50.0): tap to focus, focus box, exposure/colour
  controls, still photos at full frame. Use these if you'd rather patch stock Snapshot. The app we
  actually use is lolren's **Advanced Snapshot**, a separate repo: build
  [lolren/advanced-snapshot](https://github.com/lolren/advanced-snapshot) at commit
  `df308e9d95ba9d90ac6866010db3b95ce9d11de4` (the one their r36 package uses).

Order that matters: the libcamera patches first (the PipeWire and Snapshot patches use the controls they
add), then PipeWire, then the app. The kernel part is only needed for the front camera.

What we tested ourselves: the rear-camera stack, as lolren's built packages, on our phone. We have not
built these patches ourselves, and we haven't flashed the front-camera kernel patches (see below), so
treat the front camera part as lolren's result, not ours.

## Front camera
Still grey on our phone. lolren has three kernel patches for it (IMX371 2304x1728 binned mode, a
device-tree link frequency, and a gain range fix: `patches/kernel-sdm845/0001`-`0003` here). We have
built a kernel with them but have **not flashed and tested it yet**, so we can't vouch for it. Kernel
changes can stop the phone booting: read [docs/RECOVERY.md](../docs/RECOVERY.md) first.

## Undo
```
sudo sh widen-af-range.sh --undo
sudo apk del advanced-snapshot advanced-snapshot-lang
sudo apk add --allow-untrusted ~/camera-backup/libcamera-*.apk ~/camera-backup/libcamera-ipa-*.apk \
  ~/camera-backup/pipewire-spa-libcamera-*.apk
sudo apk fix pipewire-libs
```

## Known limits
- Colour is a measured correction from lolren, not a factory calibration. Good, not Android-good.
- Autofocus is contrast-based in software: it hunts a little and is slower than on Android.
- lolren's libcamera has version `99990.x` so normal upgrades don't replace it. But a PipeWire upgrade
  can put the stock `libspa-libcamera.so` back; if the camera vanishes from apps after an upgrade,
  reinstall the `pipewire-spa-libcamera` package above.
- Other camera apps (Plasma Camera, Megapixels) can show a picture but don't have the focus controls.
