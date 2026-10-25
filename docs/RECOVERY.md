# If the phone does not boot after a kernel flash

Most of this repository is user-space (scripts, units) and cannot brick anything. The **kernel and
device-tree patches can**: a bad boot image means the phone shows a logo or loops. The good news:
flashing `boot_a` never touches the bootloader (abl/xbl), so **fastboot always still works** and you
can put the old image back.

## Before you flash anything: make an undo copy (2 minutes)

On the phone (pmOS, root needed). The A/B layout of the 6T puts the running pmOS in slot `_a`:

```
sudo dd if=/dev/disk/by-partlabel/boot_a of=$HOME/boot_a-backup.img bs=4M
sha256sum $HOME/boot_a-backup.img
```

Copy that file to your PC and check the checksum there too. **Copies can be silently truncated**
(one of ours was 60 MB of 64 MB), so compare sizes and checksums, do not trust the copy command.
A full backup of the other partitions is better still (see "Bigger backup" below).

## Getting into fastboot

1. Switch the phone off (hold Power about 10 s if stuck).
2. Hold **Volume Up + Volume Down + Power** until the fastboot screen appears.
3. Connect USB to the PC; `fastboot devices` must list the phone.

The fastboot screen times out and boots normally if nobody sends a command. So start a loop on the
PC first (`while ! fastboot devices | grep -q fastboot; do sleep 0.5; done; echo ready`), then press
the buttons, then send the command at once.

## Restore the known-good boot image

```
fastboot flash boot_a boot_a-backup.img
fastboot --set-active=a
fastboot reboot
```

If you had also installed a patched kernel package (apk) on the rootfs, put the stock one back once
the phone is up so `/lib/modules` matches the running kernel:

```
sudo apk add linux-postmarketos-qcom-sdm845=<stock version>
```

To **try an image without flashing** (RAM only, gone after reboot): `fastboot boot new-boot.img`.
Use this first for anything risky (device-tree edits, USB, charging, display, storage).

## Bigger backup (recommended before the first kernel experiment)

Raw dumps of all partitions except `userdata` (`dd` each `/dev/disk/by-partlabel/<name>`, compress,
checksum) plus a file-level copy of the root filesystem (`tar --numeric-owner --xattrs
--xattrs-include='*' --acls`). Do it over USB to a PC, in chunks, with checksums. If the rootfs
itself is damaged, boot any working pmOS or rescue image, recreate the filesystem and untar.

## Last resort

If fastboot is not reachable and USB shows the Qualcomm EDL id `05c6:9008`, the OnePlus
MsmDownloadTool (Windows) can reflash stock OxygenOS (wipes everything); afterwards reinstall pmOS.
We never needed this.

## Traps we hit

- **A PC does not see the phone in normal Linux** can simply be the USB port stuck in host mode, not a
  brick. See `05-usb-c-pd-charging-tethering`.
- **Never `echo stop` the audio DSP (adsp remoteproc)**: it hard-freezes the phone at once.
- **Never extract an archive with a top-level `lib/` `bin/` or `sbin/` into `/` with tar**: pmOS is
  "merged usr" and tar replaces the `/lib` symlink with a directory; nothing can start afterwards.
  (Repair was possible via fastboot RAM-boot plus the pmOS debug shell.)
- **Reboot over ssh**: `(sleep 1; sudo reboot) &` dies with the ssh session. Use
  `sudo systemd-run --on-active=2 /sbin/reboot` and check `uptime` before trusting a test.
