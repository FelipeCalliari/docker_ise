#!/usr/bin/env bash
# Loads JTAG cable firmware (Xilinx Platform Cable USB) via fxload.
# udev does not run inside the container, so this must be done by hand:
# VID:PID is read straight from the usbfs device descriptor (udevadm
# has no database here) and the firmware is picked from the same table
# the udev rules use.
set -euo pipefail

RULES=/etc/udev/rules.d/xusbdfwu.rules
READY=03fd:0008     # PID the cable re-enumerates with once loaded

# "vid:pid" -> firmware, as in xusbdfwu.rules (used if it's missing).
declare -A FIRMWARE=(
    [03fd:0007]=/usr/share/xusbdfwu.hex
    [03fd:0009]=/usr/share/xusb_xup.hex
    [03fd:000d]=/usr/share/xusb_emb.hex
    [03fd:000f]=/usr/share/xusb_xlp.hex
    [03fd:0013]=/usr/share/xusb_xp2.hex
    [03fd:0015]=/usr/share/xusb_xse.hex
)
if [[ -r "$RULES" ]]; then
    while read -r vid pid fw; do
        FIRMWARE[${vid,,}:${pid,,}]=$fw
    done < <(sed -n 's/.*idVendor}=="\([0-9a-fA-F]*\)".*idProduct}=="\([0-9a-fA-F]*\)".*-I \([^ "]*\).*/\1 \2 \3/p' "$RULES")
fi

# Prints "vid:pid" of a usbfs node (idVendor/idProduct, little endian,
# at offset 8 of the device descriptor).
usb_id() {
    local -a b
    # Four hex bytes, whitespace-separated; word splitting is the point here.
    # shellcheck disable=SC2207
    b=($(od -An -tx1 -j8 -N4 "$1" 2>/dev/null)) || return 1
    [[ ${#b[@]} -eq 4 ]] || return 1
    echo "${b[1]}${b[0]}:${b[3]}${b[2]}"
}

ready_nodes() {
    local dev
    for dev in /dev/bus/usb/*/*; do
        if [[ -c "$dev" && "$(usb_id "$dev" || true)" == "$READY" ]]; then
            echo "$dev"
        fi
    done
}

expected=$(ready_nodes | wc -l)
for dev in /dev/bus/usb/*/*; do
    [[ -c "$dev" ]] || continue
    id=$(usb_id "$dev") || continue
    fw=${FIRMWARE[$id]:-}
    [[ -n "$fw" ]] || continue
    if [[ ! -f "$fw" ]]; then
        echo "[firmware] $dev ($id): $fw not found" >&2
        continue
    fi
    echo "[firmware] Loading $fw on $dev ($id)..."
    if fxload -t fx2 -I "$fw" -D "$dev"; then
        expected=$((expected + 1))
    else
        echo "[firmware] fxload failed on $dev" >&2
    fi
done

# Wait for the loaded cables to re-enumerate, then open the new nodes to
# the unprivileged user (host udev may have no rule for them).
for _ in {1..20}; do
    (( $(ready_nodes | wc -l) >= expected )) && break
    sleep 0.5
done
for dev in $(ready_nodes); do
    chmod 666 "$dev" 2>/dev/null || true
    echo "[firmware] Cable ready: $dev"
done
