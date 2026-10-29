# Storage-hang watchdog.
# Every 30 s a child process writes+fsyncs a small file on the root fs.
# If that probe hasn't finished in 180 s the disk is stuck: dump all blocked
# tasks to the kernel log (kept in ramoops across the reboot), then reboot.
# Runs from a copy of busybox in /run (RAM) so the watcher itself can't block on disk.
# Undo: systemctl disable --now iowatch; rm /etc/systemd/system/iowatch.service /usr/local/lib/iowatch -r
export PATH=/run/iowatch/bin
PROBE=/var/tmp/.iowatch-probe
LIMIT=180
while :; do
  rm -f /run/iowatch/done
  ( echo "$(date +%s)" > $PROBE && sync -f $PROBE 2>/dev/null || sync; touch /run/iowatch/done ) &
  n=0
  while [ ! -e /run/iowatch/done ]; do
    sleep 5; n=$((n+5))
    if [ $n -ge $LIMIT ]; then
      echo "iowatch: root-fs write+sync stuck for ${LIMIT}s, dumping blocked tasks and rebooting" > /dev/kmsg
      echo w > /proc/sysrq-trigger
      sleep 10
      echo m > /proc/sysrq-trigger
      sleep 5
      echo b > /proc/sysrq-trigger
    fi
  done
  wait
  sleep 30
done
