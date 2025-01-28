#!/usr/bin/env bash

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No color

# The ISE tar file.
#
# Make sure this file or a hard link to it is in the same
# directory as this script.
XILINX_TAR=Xilinx_ISE_DS_14.7_1015_1.tar
if [ ! -f $XILINX_TAR ]; then
    echo -e "${RED}Error:${NC} could not find ${XILINX_TAR}"
    exit 1
fi

XILINX_LIC="Xilinx.lic"
if [ ! -f $XILINX_LIC ]; then
    echo -e "${RED}Error:${NC} could not find ${XILINX_LIC}"
    exit 1
fi

# # Run http.server in background to serve the installation files..
# echo -e "${GREEN}Success:${NC} running http.server and docker build.."
# tmux new -s createdocker -d "python3 -m http.server"

# build docker
docker build --build-arg XILINX_TAR="${XILINX_TAR}" \
             --build-arg SERVER_HOST=host.docker.internal:8000 \
             --add-host=host.docker.internal:host-gateway \
             -f Dockerfile -t xilinx-ise:14.7 .

# # close tmux session
# tmux kill-session -t createdocker
