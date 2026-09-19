#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$(readlink -f "$0")")"

IMAGE=${IMAGE:-xilinx-ise:14.7}
SHARED_DIR=${SHARED_DIR:-$HOME}

# Optional MAC address for licenses node-locked to one. Docker silently
# ignores --mac-address under --net=host (the container sees the host's real
# interfaces), so setting it moves the default network to bridge.
LICENSE_MAC=${LICENSE_MAC:-}
if [[ -n "$LICENSE_MAC" ]]; then
    NETWORK=${NETWORK:-bridge}
else
    NETWORK=${NETWORK:-host}
fi

usage() {
    cat <<USAGE
Usage: $(basename "$0") [--root] [--bash] [-- <docker run args>...]

  --root   Run as root instead of the 'xilinx' user
  --bash   Start an interactive shell instead of the ISE GUI

Environment:
  IMAGE        Image to run (default: xilinx-ise:14.7)
  NETWORK      Docker network mode (default: host, or bridge when LICENSE_MAC
               is set -- --mac-address is a no-op on host)
  LICENSE_MAC  MAC address for a node-locked license (default: none). Must be
               unicast, e.g. 02:ab:23:cd:45:ef
  SHARED_DIR   Host directory mounted at <home>/shared (default: \$HOME)
USAGE
}

# Consume --root/--bash from the arguments and run the container as root /
# with a shell. Everything after a bare '--' is passed through untouched.
GUEST_USER="xilinx"
GUEST_HOME="/home/xilinx"
USE_BASH=0
DOCKER_ARGS=()

while (( $# )); do
    case "$1" in
        --root) GUEST_USER="root"; GUEST_HOME="/root" ;;
        --bash) USE_BASH=1 ;;
        -h|--help) usage; exit 0 ;;
        --) shift; DOCKER_ARGS+=("$@"); break ;;
        *) DOCKER_ARGS+=("$1") ;;
    esac
    shift
done

# /bin/bash goes first: anything after '--' is arguments to it.
if [[ "$USE_BASH" == 1 ]]; then
    DOCKER_ARGS=("/bin/bash" "${DOCKER_ARGS[@]}")
fi

if [[ -n "$LICENSE_MAC" ]]; then
    if [[ ! "$LICENSE_MAC" =~ ^([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}$ ]]; then
        echo "Error: LICENSE_MAC '$LICENSE_MAC' is not a MAC address (xx:xx:xx:xx:xx:xx)." >&2
        exit 1
    fi
    # An odd first octet is a multicast address, which the bridge refuses
    # ("cannot assign requested address").
    if (( (16#${LICENSE_MAC:0:2} & 1) != 0 )); then
        echo "Error: LICENSE_MAC '$LICENSE_MAC' is multicast; the first octet must be even." >&2
        exit 1
    fi
    if [[ "$NETWORK" == "host" ]]; then
        echo "Error: LICENSE_MAC has no effect with NETWORK=host; unset NETWORK or pick e.g. bridge." >&2
        exit 1
    fi
fi

docker image inspect "$IMAGE" >/dev/null 2>&1 \
    || { echo "Error: image $IMAGE not found. Build it first: ./create-image.sh" >&2; exit 1; }

# Only the GUI path needs X; a plain shell does not.
if [[ -z "${DISPLAY:-}" ]]; then
    if (( ${#DOCKER_ARGS[@]} == 0 )); then
        echo "Error: \$DISPLAY is not set; the ISE GUI has nowhere to draw." >&2
        exit 1
    fi
    echo "Warning: \$DISPLAY is not set; GUI tools will not start." >&2
fi

RUN_ARGS=()

# X11: pass the socket and the auth cookie read-only. Not every setup keeps a
# cookie file (some Wayland/XWayland sessions), so mount it only if it exists.
XAUTHORITY="${XAUTHORITY:-${HOME}/.Xauthority}"
if [[ -r "$XAUTHORITY" ]]; then
    RUN_ARGS+=(-v "$XAUTHORITY:$GUEST_HOME/.Xauthority:ro")
else
    echo "Warning: no readable Xauthority at '$XAUTHORITY'." >&2
    echo "         If the GUI fails to open, run: xhost +si:localuser:$USER" >&2
fi

# JTAG / USB / Digilent (major 189)
RUN_ARGS+=(-v /dev/bus/usb:/dev/bus/usb)
RUN_ARGS+=(--device-cgroup-rule='c 189:* rmw')

# Serial FTDI (major 188) e USB CDC (major 166)
for d in /dev/ttyUSB* /dev/ttyACM*; do
    [[ -e "$d" ]] || continue
    major=$(stat -c '%t' "$d")
    major_dec=$((16#$major))
    RUN_ARGS+=(-v "$d:$d")
    RUN_ARGS+=(--device-cgroup-rule="c $major_dec:* rmw")
done

RUN_ARGS+=(--net="$NETWORK")
if [[ "$NETWORK" == "host" ]]; then
    RUN_ARGS+=(--ipc=host)
else
    # Off the host network the hostname defaults to the container ID, and the
    # X cookie (keyed by <hostname>/unix:<display>) is no longer found. Keep
    # the host's name. uname -n, since 'hostname' is not installed everywhere.
    RUN_ARGS+=(--hostname "$(uname -n)")
    if [[ -n "$LICENSE_MAC" ]]; then
        RUN_ARGS+=(--mac-address "$LICENSE_MAC")
    fi
fi

docker run -it --rm \
    -u "$GUEST_USER" \
    -e HOME="$GUEST_HOME" \
    -v /etc/localtime:/etc/localtime:ro \
    -v /tmp/.X11-unix:/tmp/.X11-unix \
    -v "$SHARED_DIR":"$GUEST_HOME"/shared \
    -v "$HOME"/.config/Xilinx:"$GUEST_HOME"/.config/Xilinx \
    "${RUN_ARGS[@]}" \
    -e QT_X11_NO_MITSHM=1 \
    -e DISPLAY="${DISPLAY:-}" \
    --name "docker-ise-$$" \
    "$IMAGE" "${DOCKER_ARGS[@]}"
