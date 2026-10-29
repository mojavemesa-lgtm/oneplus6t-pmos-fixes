# 10 - "No modem" / no signal after boot: SIM in the wrong slot

No modem or no signal after boot because the SIM is in the wrong slot.

Keywords: OnePlus 6T postmarketOS no modem after boot, fajita mainline SIM slot no signal, pmOS SIM not detected, ModemManager SIM slot switch, Linux phone dual SIM wrong slot, sdm845 no service

**Status: works on our phone (postmarketOS v26.06, 2026-09/10). The slot number is specific to where YOUR SIM is.**

## Symptom
After boot the modem is registered but no SIM is used, or Calls says "no modem". Fixed by hand with
`mmcli -m 0 --set-primary-sim-slot=1`.

## Root cause
The OnePlus 6T has two SIM slots; ModemManager sometimes starts with slot 2 as primary. Switching the primary slot
resets the modem, and the Calls daemon (which started earlier) does not reconnect to the restarted ModemManager.

## What it does
`fix_sim.sh` restarts ModemManager, waits, sets the primary SIM slot to 1. `fix-sim-login` runs it at login and then
restarts the Calls daemon. `fix-sim.desktop` is the autostart entry.

## Install
```
sudo install -m755 fix_sim.sh /usr/local/bin/
install -m755 fix-sim-login ~/.local/bin/
cp fix-sim.desktop ~/.config/autostart/
echo "$USER ALL=(ALL) NOPASSWD: /usr/local/bin/fix_sim.sh" | sudo tee /etc/sudoers.d/fix-sim
```
Change `--set-primary-sim-slot=1` to 2 if your SIM is in the second slot.

## Undo
Remove the autostart file, the scripts and the sudoers file.

## Known limits
- Slow (about 40 s at login). A dual-SIM phone with a SIM in each slot is untested.
- Restarting ModemManager during login drops an active call.
