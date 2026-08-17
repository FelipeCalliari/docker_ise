#!/usr/bin/env bash
# Loads JTAG cable firmware (Xilinx Platform Cable / Digilent) via fxload.
# udev does not run inside the container, so this must be done by hand.
set -euo pipefail

CABLE_READY_03FD=0008
CABLE_READY_1443=0007

for dev in /dev/bus/usb/*/*; do
    [[ -e "$dev" ]] || continue
    info=$(udevadm info -q property -n "$dev" 2>/dev/null || true)
    vid=$(echo "$info" | sed -n 's/^ID_VENDOR_ID=//p')
    pid=$(echo "$info" | sed -n 's/^ID_MODEL_ID=//p')
    [[ -n "$vid" ]] || continue

    case "$vid" in
        03fd) [[ "$pid" == "$CABLE_READY_03FD" ]] && continue ;;
        1443) [[ "$pid" == "$CABLE_READY_1443" ]] && continue ;;
        *) continue ;;
    esac

    echo "[firmware] Loading cable firmware on $dev ($vid:$pid)..."
    for fw in /usr/share/xusb*.hex; do
        [[ -f "$fw" ]] || continue
        if fxload -D "$dev" -I "$fw" -t fx2 2>/dev/null; then
            echo "[firmware] OK: $fw"
            break
        fi
    done
done
