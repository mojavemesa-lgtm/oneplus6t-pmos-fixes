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
- **"Hephaestus"** (a user on the postmarketOS issue tracker) found that setting both q6voice
  topologies to 69488 cures the "chipmunk" far-end voice: pmaports issue #3713, comment from about
  2026-09-02. Fix 02 is just that, made permanent.
- The KDE `ImageStackView.qml`, powerdevil and gwenview fixes are small changes to KDE software
  (their licenses apply to those files; gwenview's pinch-gesture crash is also covered upstream by
  KDE merge request !376).
- Everything else was written by a non-developer together with an AI assistant (Claude, by
  Anthropic). Commits and patches carry an `Assisted-by: Claude` tag where it applies.
