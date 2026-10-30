#!/bin/sh
# 2026-10-06: phone storage (UFS) hangs: stalls log "timedout waiting for doorbell" inside UFS clock
# scaling, then writes never complete and iowatch reboots. Pin the UFS clock to full speed, then turn
# clock scaling and clock gating off (gating off = no hibern8-with-clock-gating cycles).
# Order matters: disabling scaling while at the low clock leaves it stuck slow (seen: 50 MHz, ~15 MB/s).
U=/sys/devices/platform/soc@0/1d84000.ufshc
for d in "$U"/devfreq/*; do
  max=$(cat "$d/max_freq"); echo "$max" > "$d/min_freq"
done
for i in 1 2 3 4 5 6 7 8 9 10; do
  [ "$(cat "$d/cur_freq")" = "$max" ] && break; sleep 0.5
done
echo 0 > "$U/clkscale_enable"
echo 0 > "$U/clkgate_enable"
echo "ufs-fullspeed: freq=$(cat "$d/cur_freq") clkscale=$(cat $U/clkscale_enable) clkgate=$(cat $U/clkgate_enable)"
