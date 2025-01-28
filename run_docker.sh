#!/usr/bin/env bash

#DISPLAY=$(ifconfig br0 | awk '/inet / {print $6}'):0
#echo "$DISPLAY"

# Set MAC Address
LICENSE_MAC=${LICENSE_MAC:-"01:ab:23:cd:45:ef"}

# Set XAUTHORITY, if not set
XAUTHORITY="${XAUTHORITY:-${HOME}/.Xauthority}"
#echo "$XAUTHORITY"

docker run -it --rm \
    -v /etc/localtime:/etc/localtime:ro \
    -v /tmp/.X11-unix:/tmp/.X11-unix \
    -v "$XAUTHORITY":/home/xilinx/.Xauthority:ro \
    -v "$HOME":/home/xilinx/shared \
    -v "$HOME"/.config/Xilinx:/home/xilinx/.config/Xilinx \
    -v /dev:/dev --device-cgroup-rule='c *:* rmw' \
    -e QT_X11_NO_MITSHM=1 \
    -e DISPLAY="$DISPLAY" \
    --net=host --ipc=host \
    --mac-address "$LICENSE_MAC" \
    --name docker-ise \
    xilinx-ise:14.7 "$@"

#bash
