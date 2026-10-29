# 05 - USB-C: charging, USB Power Delivery, host/device switching, 5 V power out and tethering

The phone charges badly (trickle, flapping), USB tethering fails, or it cannot power or host USB devices.

Keywords: OnePlus 6T postmarketOS USB-C charging, fajita mainline USB PD, pmOS power bank charging stops, sdm845 PMI8998 typec gen1 qcom_smbx, Linux phone USB host device switching, OnePlus 6T 5V OTG out, USB tethering pmOS

**Status: works in our tests (7.1.0-rc1-sdm845, postmarketOS v26.06; on the everyday kernel since 2026-10-24, daily use since): PC port,
a power bank and one PD charger model. Not tested: a thick C-to-C cable above 1 A, other chargers.**
The set was sent upstream (to the people named below); it is not merged.

## Symptom
Out of the box on the mainline kernel the OnePlus 6T:
- does not charge properly from some chargers/power banks (stuck at a trickle, or flapping),
- does not act as a USB device to a PC reliably after a cable flip, so USB tethering/gadget fails,
- hits a "PD hard-reset storm" with some chargers: the charger keeps resetting the connection.

## Root causes (short)
The PMI8998 power chip has an old-style ("gen1") USB-C port controller that mainline had no driver for;
the charger driver (`qcom_smbx`) fought with the Type-C code over the role register, restarted charger
detection every second, ignored the negotiated PD current, and advertised a 15 W sink requirement that
some chargers refuse. And the postmarketOS tethering script removed its USB gadget config unsafely.

## What the patches do (`kernel/`, apply in order)
- 0001-0005: backport of the gen1 Type-C port driver and device tree nodes. **These are the work of
  David Heidelberg (with Alexey Minnekhanov); their RFC on the linux-arm-msm list, kept with their
  authorship.** Not ours.
- 0006-0009: PMI8998 VBUS regulator support and removal of a workaround write that broke VBUS.
- 0010: the charger driver stops touching the Type-C role register.
- 0011: device tree enables the VBUS regulator on the OnePlus phones.
- 0012: periodic AICL re-run (the charger re-measures what current the source can give).
- 0013: do not restart charger-type detection (APSD) every second.
- 0014: the charger follows the PD current negotiated by the Type-C stack.
- 0015: device tree: link charger to the Type-C port.
- 0016: lower `op-sink-microwatt` from 15 W to 5 W, which ends the hard-reset storm.

`pmaports/`: two small patches to postmarketOS's `50-tethering.sh` (use `rmdir` instead of `rm -rf` on
the gadget config; only cycle the UDC if it exists).

## Install
Apply the kernel patches to the sdm845-mainline `sdm845-7.1-rc1-r0` tree (see `../docs/BUILDING-A-KERNEL.md`,
`../docs/RECOVERY.md`), rebuild and flash. The pmaports patches apply to the `postmarketos-base-ui-networkmanager`
package (`git am` in a pmaports checkout and `pmbootstrap build`), or edit the installed
`50-tethering.sh` by hand.

## Undo
Flash your previous `boot_a` backup (`../docs/RECOVERY.md`); `sudo apk fix postmarketos-base-ui-networkmanager`.

## Known limits
- Kernel flashing carries brick risk (recoverable via fastboot). Read the recovery doc first.
- Patches were checked on our own tree only; they were not re-applied to a pristine tag for this repo. Context
  may need small fixes.
- Power-bank charging problems seen on this phone are addressed by 0012-0016.
