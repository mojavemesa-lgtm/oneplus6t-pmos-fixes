# 04 - Bluetooth chip hangs ("Reading QCA version information failed (-110)")

Bluetooth suddenly dies and only a reboot brings it back.

Keywords: OnePlus 6T postmarketOS Bluetooth not working after boot, fajita mainline hci0 Reading QCA version information failed -110, pmOS Bluetooth chip hang, sdm845 WCN3990 qcom geni serial DMA, Linux phone Bluetooth dead second power cycle

**Status: kernel fix is an upstream commit, flashed 2026-10-08 (r1 build, 7.1.0-rc1-sdm845) and the hang
has not recurred since. The recovery script is a stopgap that worked in tests.**

## Symptom
Bluetooth suddenly dies, usually while a device disconnects. The log (`journalctl -k`) repeats
`hci0: Reading QCA version information failed (-110)` forever and only a reboot helps. Seen three times in
September 2026.

## Root cause
The kernel's Qualcomm "geni" serial driver can lose track of its DMA receive buffer after a flow-control
(RTS) event, so bytes from the Bluetooth chip stop arriving. Fixed upstream by commit `b93062b6d8a1`
("serial: qcom-geni: fix RX DMA stall..." by Viken Dadhaniya; in Linux 7.2). The Bluetooth chip is wired
to this serial port.

## What the fix does
- `geni-rx-dma-stall.patch`: the upstream commit, for the 7.1 sdm845-mainline tree. The Bluetooth driver
  is built into the kernel, so you must rebuild and flash the kernel (see `../docs/BUILDING-A-KERNEL.md`
  and `../docs/RECOVERY.md`).
- `bt-crash-recover.sh` + service: until you have the patched kernel, it watches the kernel log and, when
  it sees the hang, power-cycles the chip by unbinding and rebinding the serial driver, then powers
  Bluetooth on and reconnects paired devices. It refuses to act while hci0 is still powered, because
  unbinding a powered chip crashes the kernel.

## Second cause: UART DMA bugs after boot (added 2026-10-29)

On the 7.1-rc1 kernel, Bluetooth also failed on roughly every second setup after boot (the same `-110` log
line, chip never answers). Three fixes to the same geni serial driver cured it; 10 clean boots in a row on
the k27 build, and they are part of the current k30 tree:

- `452d6fa37ae9` (Viken Dadhaniya): kfifo underflow in the TX path.
- `7ea38c49e717` (Guangshuo Li): stale DMA completions after a flush.
- `e3c04834ae1a` (Jan Sebastian Goette): TX DMA flush handling.

Files in `kernel/`:
- `0001-serial-qcom-geni-uart-dma-flush-fixes-combined.patch`: the three fixes folded into one patch that
  applies to the sdm845-mainline 7.1-rc1 tree (the originals do not apply one after another there).
- `upstream/`: the three original upstream patches, unchanged, for newer trees where they apply directly.

Install: `git am kernel/0001-*.patch`, rebuild, flash (see `../docs/BUILDING-A-KERNEL.md`).

## Install
Kernel: `git am geni-rx-dma-stall.patch`, rebuild, flash.
Stopgap (as root):
```
sudo install -m755 bt-crash-recover.sh /usr/local/bin/
sudo cp bt-crash-recover.service /etc/systemd/system/
sudo systemctl enable --now bt-crash-recover
```

## Undo
`sudo systemctl disable --now bt-crash-recover`; for the kernel see `../docs/RECOVERY.md`.

## Known limits
- The script needs `bluetoothctl`, `btmgmt`, `script` (util-linux). The serial device name `serial0-0` is
  specific to this phone's device tree.
- This chip has no stored Bluetooth address. After a power cycle it comes back "unconfigured" unless an
  address is re-applied; the script does that from `/run/bt-addr` if you create that file at boot.
- Never write to the driver's `unbind` file by hand while Bluetooth is powered on.
