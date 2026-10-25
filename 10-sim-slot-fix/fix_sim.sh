#!/bin/sh
# Robust SIM slot fix for OnePlus 6T (Updated Service Paths)

echo "Restarting ModemManager to clear failed state..."
sudo systemctl restart ModemManager 2>/dev/null

echo "Waiting for modem to initialize (20s)..."
sleep 20

echo "Verifying modem is available..."
MODEM_ID=$(mmcli -L | grep -oP '(?<=Modem/)[0-9]+' | head -1)
if [ -z "$MODEM_ID" ]; then
    echo "ERROR: No modem found after restart."
    exit 1
fi
echo "Modem $MODEM_ID found."

echo "Switching primary SIM slot to 1..."
mmcli -m "$MODEM_ID" --set-primary-sim-slot=1

echo "Waiting for SIM slot to take effect (15s)..."
sleep 15

# Check the status
echo "Current modem status:"
mmcli -m "$MODEM_ID" | grep -E "state|failed reason|SIM"

echo "Done. If state is 'registered', you should have signal soon."
