#!/usr/bin/env bash
set -euo pipefail

IMAGE=${IMAGE:-xilinx-ise:14.7}

if ! command -v sudo >/dev/null 2>&1; then
    echo "Error: sudo is required. Install it first (e.g. 'pacman -S sudo' on Arch)."
    exit 1
fi

if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
    echo "Error: image $IMAGE not found. Build it first: ./create-image.sh"
    exit 1
fi

if ! FXLOAD=$(command -v fxload); then
    echo "Error: fxload is required to load the cable firmware. Install it"
    echo "first (Arch: AUR 'fxload', e.g. 'yay -S fxload'; Debian/Ubuntu: 'apt install fxload')."
    exit 1
fi

# Distro detection
SERIAL_GROUP="uucp"     # Arch default
[[ -r /etc/os-release ]] && source /etc/os-release
case "$ID" in
    debian|ubuntu|linuxmint)
        SERIAL_GROUP="dialout"
        ;;
    opensuse*|sles)
        SERIAL_GROUP="dialout"
        ;;
    arch|manjaro)
        SERIAL_GROUP="uucp"
        ;;
esac

echo "==> Creating temporary container..."
ID=$(docker create "$IMAGE")
trap 'docker rm "$ID" >/dev/null 2>&1 || true' EXIT

echo "==> Adding user to serial device groups..."
# plugdev exists on Debian/Ubuntu; uucp/dialout cover Arch and SUSE.
if getent group plugdev >/dev/null; then
    if ! id -nG | grep -qw plugdev; then
        sudo usermod -aG plugdev "$USER"
        echo "    User '$USER' added to plugdev."
    fi
else
    echo "    plugdev does not exist on this distro, skipping."
fi
if ! id -nG | grep -qw "$SERIAL_GROUP"; then
    sudo usermod -aG "$SERIAL_GROUP" "$USER"
    echo "    User '$USER' added to $SERIAL_GROUP."
fi

echo "==> Installing cable firmware (xusb*.hex) to /usr/share..."
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"; docker rm "$ID" >/dev/null 2>&1 || true' EXIT
# The container is only created, not started, so list with a throwaway run.
for fw in $(docker run --rm --entrypoint sh "$IMAGE" -c 'ls /usr/share/xusb*.hex 2>/dev/null'); do
    name=$(basename "$fw")
    docker cp "$ID:$fw" "$TMP_DIR/$name"
    sudo cp "$TMP_DIR/$name" /usr/share/
    echo "    /usr/share/$name"
done

echo "==> Installing udev rules (xusbdfwu.rules)..."
docker cp "$ID:/etc/udev/rules.d/xusbdfwu.rules" "$TMP_DIR/"
# Match only the usb_device (SUBSYSTEMS also fires for its interfaces)
# and call the host's fxload. libusb's fxload (Arch AUR) has no -D, it
# takes the device as -p bus,dev.
SED=(-e '/RUN+=/{s/SUBSYSTEMS=="usb"/SUBSYSTEM=="usb", ENV{DEVTYPE}=="usb_device"/; s/ATTRS{/ATTR{/g}'
     -e "s#/sbin/fxload#$FXLOAD#")
FXLOAD_USAGE=$("$FXLOAD" -h 2>&1 || true)
if [[ "$FXLOAD_USAGE" == *"-p <bus,addr>"* ]]; then
    SED+=(-e 's/-D \$tempnode/-p $env{BUSNUM},$env{DEVNUM}/')
fi
sed "${SED[@]}" "$TMP_DIR/xusbdfwu.rules" > "$TMP_DIR/xusbdfwu.rules.host"
sudo cp "$TMP_DIR/xusbdfwu.rules.host" /etc/udev/rules.d/xusbdfwu.rules
echo "    /etc/udev/rules.d/xusbdfwu.rules"

# Fallback: allow any user to access the cable, so group membership
# alone is enough on every distro.
cat <<'EOF' | sudo tee /etc/udev/rules.d/50-xilinx-cable.rules >/dev/null
# Xilinx Platform Cable USB / Digilent JTAG cables: grant access to all users
ACTION=="add", SUBSYSTEMS=="usb", ATTRS{idVendor}=="03fd", MODE="666"
ACTION=="add", SUBSYSTEMS=="usb", ATTRS{idVendor}=="1443", MODE="666"
EOF
echo "    /etc/udev/rules.d/50-xilinx-cable.rules"

echo "==> Reloading udev..."
sudo udevadm control --reload-rules
sudo udevadm trigger

echo
echo "Done. Log out/in for group changes, then unplug and replug the"
echo "JTAG cable for the firmware to be loaded."
