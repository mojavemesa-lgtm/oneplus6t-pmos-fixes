# Credits and what is whose work

- **Dylan Van Assche** wrote the base this work builds on: the `wcn3990-bluetooth-hfp-v4` kernel
  branch (WCN3990 Bluetooth audio over SLIMbus, second SLIMbus controller, SLIMBUS_7/8 ports).
  The fixes in `01-bluetooth-headset-calls/kernel/` sit on top of his branch. His own commits are not
  copied into this repository; fetch them from his tree (see that folder's README).
- **David Heidelberg** and **Alexey Minnekhanov**: patches 0001 to 0005 in
  `05-usb-c-pd-charging-tethering/kernel/` are a backport of David's RFC series "Qualcomm Type-C support for
  1st generation" (v1, 2026-09-26). Their authorship and Signed-off-by lines are untouched. That is
  their work, not ours; only context lines were adjusted so it applies to the older tag.
- **Viken Dadhaniya**: the serial RX DMA stall fix in `04-bt-chip-hang/geni-rx-dma-stall.patch` is
  his upstream commit b93062b6d8a1 (unchanged).
- **Viken Dadhaniya, Guangshuo Li, Jan Sebastian Goette**: the three serial UART DMA fixes in
  `04-bt-chip-hang/kernel/upstream/` are their upstream commits (452d6fa37ae9, 7ea38c49e717, e3c04834ae1a);
  the combined patch next to them only merges them for the 7.1-rc1 tree.
- **Rob Clark**: the a6xx GPU commit d9108bfdb746 in `19-screen-off-hang-gpu-gmu/` is his upstream work.
- **Shivam Rawat and Nitin Rawat**: the UFS lane-clock and UFS OPP changes in `18-deep-sleep-kernel/`
  build on their upstream UFS work.
- **Elson Serrao**: the dwc3 "forceRM" change in `21-usb-networking-crash-dwc3/` is his commit.
- **Mukesh Ojha**: the fastrpc fix 5401fb4fe10f in `20-random-crash-during-boot/` is his upstream commit (unchanged).
- **Michael Auer**: the ModemManager merge-request patches that `18-deep-sleep-kernel/modemmanager/0006` sits on
  (ModemManager MR 1511, patches 0002 and 0003) are his.
- **The qbootctl authors (linux-msm/qbootctl)**: `23-ab-slot-switching-brick/` patches their tool.
- **"Hephaestus"** (a user on the postmarketOS issue tracker) found that setting both q6voice
  topologies to 69488 cures the "chipmunk" far-end voice: pmaports issue #3713, comment from about
  2026-09-02. Fix 02 is just that, made permanent.
- The KDE `ImageStackView.qml`, powerdevil and gwenview fixes are small changes to KDE software
  (their licenses apply to those files; gwenview's pinch-gesture crash is also covered upstream by
  KDE merge request !376).
- **lolren** ([lolren/oneplus6t-pmos-fixes](https://github.com/lolren/oneplus6t-pmos-fixes), MIT): the whole
  camera stack in `16-camera-autofocus-colour/patches/` (libcamera, PipeWire, kernel and Snapshot patches,
  tuning files) is their work, copied unchanged; their license is in `patches/LICENSE-lolren-MIT`.
  libcamera `0001`-`0002` there are **Robert Mader**'s (Collabora), from postmarketOS's libcamera package.
- Everything else was written by a non-developer together with an AI assistant (Claude, by
  Anthropic). Commits and patches carry an `Assisted-by: Claude` tag where it applies.
