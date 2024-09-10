#!/bin/bash

mkdir -p config

# DISPLAY=`ipconfig getifaddr en0`:0

docker run -it \
           -v /tmp/.X11-unix:/tmp/.X11-unix \
           -v "$HOME/.Xauthority":/home/xilinx/.Xauthority:ro \
           -e DISPLAY="$DISPLAY" \
           -v "$HOME":/home/xilinx/shared \
           -v "$PWD/config":/home/xilinx/.config/Xilinx \
           -v /etc/localtime:/etc/localtime:ro \
           -e QT_X11_NO_MITSHM=1 \
           --net=host --ipc=host \
           xilinx_ise
