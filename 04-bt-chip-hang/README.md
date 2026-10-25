# 04 - Bluetooth chip hangs ("Reading QCA version information failed (-110)")

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
