# 07 - Mobile data says "connected" but nothing works

Mobile data says connected but nothing loads.

Keywords: OnePlus 6T postmarketOS mobile data connected no internet, fajita mainline ModemManager data dead, pmOS cellular data stops working, sdm845 qmapmux data watcher, Linux phone LTE no data, Plasma Mobile mobile data

**Status: works in testing (2026-10-21 onward, NetworkManager + ModemManager, postmarketOS v26.06).**
Tested on Verizon; should work on any carrier once you set the connection name.

## Symptom
Mobile data shows connected, but no websites load. Happens after the carrier drops the data session.
NetworkManager keeps the old connection on an interface that no longer exists. We saw it stay dead for
about 55 minutes until someone toggled data by hand.

## Root cause
NetworkManager does not notice that the modem's data interface vanished (a bearer was deleted behind its
back) and never redials. Cause in NetworkManager/ModemManager not investigated further. This script is a
bandaid, not a fix of that cause.

## What it does
`cell-data-watch` checks every 30 s that a ping out of the mobile interface works. After 3 failures
(~90 s) it turns the connection off and on, at most once per 5 minutes. It does nothing if mobile data is
off, Wi-Fi is carrying the traffic, or a voice call is in progress.

## Install
```
# edit CONN= at the top to your mobile-data connection name (nmcli c show)
sudo install -m755 cell-data-watch /usr/local/bin/
sudo cp cell-data-watch.service /etc/systemd/system/
sudo systemctl enable --now cell-data-watch
```

## Undo
`sudo systemctl disable --now cell-data-watch; sudo rm /usr/local/bin/cell-data-watch /etc/systemd/system/cell-data-watch.service`

## Known limits
- Pings 9.9.9.9 and 1.1.1.1 (public DNS servers) to test the link; change them if you do not want that.
- It cannot fix a carrier-side outage.
