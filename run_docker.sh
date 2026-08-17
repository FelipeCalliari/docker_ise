#!/usr/bin/env bash

#DISPLAY=$(ifconfig br0 | awk '/inet / {print $6}'):0
#echo "$DISPLAY"

# Set MAC Address
LICENSE_MAC=${LICENSE_MAC:-"01:ab:23:cd:45:ef"}

# Set XAUTHORITY, if not set
XAUTHORITY="${XAUTHORITY:-${HOME}/.Xauthority}"
#echo "$XAUTHORITY"

# Consume --root/--bash from the arguments and run
# the container as root / with a shell
GUEST_USER="xilinx"
GUEST_HOME="/home/xilinx"
USE_BASH=0
DOCKER_ARGS=("$@")

for i in "${!DOCKER_ARGS[@]}"; do
    case "${DOCKER_ARGS[$i]}" in
        --root)
            GUEST_USER="root"
            GUEST_HOME="/root"
            unset 'DOCKER_ARGS[$i]'
            ;;
        --bash)
            USE_BASH=1
            unset 'DOCKER_ARGS[$i]'
            ;;
    esac
done

if [[ "$USE_BASH" == 1 ]]; then
    DOCKER_ARGS+=("/bin/bash")
fi

# JTAG / USB / Digilent (major 189)
RUN_ARGS=(-v /dev/bus/usb:/dev/bus/usb)
RUN_ARGS+=(--device-cgroup-rule='c 189:* rmw')

# Serial FTDI (major 188) e USB CDC (major 166)
for d in /dev/ttyUSB* /dev/ttyACM*; do
    [[ -e "$d" ]] || continue
    major=$(stat -c '%t' "$d")
    major_dec=$((16#$major))
    RUN_ARGS+=(-v "$d:$d")
    RUN_ARGS+=(--device-cgroup-rule="c $major_dec:* rmw")
done

docker run -it --rm \
    -u "$GUEST_USER" \
    -e HOME="$GUEST_HOME" \
    -v /etc/localtime:/etc/localtime:ro \
    -v /tmp/.X11-unix:/tmp/.X11-unix \
    -v "$XAUTHORITY":"$GUEST_HOME"/.Xauthority:ro \
    -v "$HOME":"$GUEST_HOME"/shared \
    -v "$HOME"/.config/Xilinx:"$GUEST_HOME"/.config/Xilinx \
    "${RUN_ARGS[@]}" \
    -e QT_X11_NO_MITSHM=1 \
    -e DISPLAY="$DISPLAY" \
    --net=host --ipc=host \
    --mac-address "$LICENSE_MAC" \
    --name docker-ise \
    xilinx-ise:14.7 "${DOCKER_ARGS[@]}"

#bash
