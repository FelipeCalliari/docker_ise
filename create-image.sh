#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$(readlink -f "$0")")"

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No color

die() { echo -e "${RED}Error:${NC} $*" >&2; exit 1; }

IMAGE=${IMAGE:-xilinx-ise:14.7}

# The ISE tar file.
#
# Make sure this file or a hard link to it is in the same
# directory as this script.
XILINX_TAR=${XILINX_TAR:-Xilinx_ISE_DS_14.7_1015_1.tar}
XILINX_LIC=${XILINX_LIC:-Xilinx.lic}

# Install trimming -- see the ARG comments in the Dockerfile.
KEEP_SERIES7=${KEEP_SERIES7:-0}
INSTALL_PLANAHEAD=${INSTALL_PLANAHEAD:-1}
INSTALL_EDK=${INSTALL_EDK:-0}

NO_CACHE=()
for arg in "$@"; do
    case "$arg" in
        --no-cache) NO_CACHE=(--no-cache) ;;
        -h|--help)
            cat <<USAGE
Usage: $(basename "$0") [--no-cache]

Builds the Xilinx ISE image.

  --no-cache   Rebuild from scratch, ignoring the layer cache. Off by default.
               Measured at ~11 min on NVMe; most of that is compressing the
               image layers on export, not installing ISE. Expect
               substantially longer on a spinning disk.

Environment:
  IMAGE              Image tag to build (default: xilinx-ise:14.7)
  XILINX_TAR         ISE installer tar (default: Xilinx_ISE_DS_14.7_1015_1.tar)
  XILINX_LIC         Xilinx license file (default: Xilinx.lic)
  KEEP_SERIES7       1 to keep Artix-7/Kintex-7/Virtex-7/Zynq (default: 0)
  INSTALL_PLANAHEAD  0 to drop PlanAhead, ~2.4GB (default: 1)
  INSTALL_EDK        1 to keep EDK/SDK, ~5GB -- only needed for MicroBlaze or
                     PowerPC soft-core designs (default: 0)
USAGE
            exit 0
            ;;
        *) die "unknown option '$arg' (see --help)" ;;
    esac
done

[[ -f "$XILINX_TAR" ]] || die "could not find ${XILINX_TAR}"
[[ -f "$XILINX_LIC" ]] || die "could not find ${XILINX_LIC}"

# The usb-driver submodule is compiled during the build; without it the
# build fails halfway through the ~1h ISE installation.
[[ -f usb-driver/Makefile ]] || die "usb-driver/ is empty. Run: git submodule update --init"

echo -e "${GREEN}==>${NC} Building ${IMAGE}..."
docker build "${NO_CACHE[@]}" --progress=plain \
             --build-arg XILINX_TAR="${XILINX_TAR}" \
             --build-arg UID_GID="$(id -u)" \
             --build-arg KEEP_SERIES7="${KEEP_SERIES7}" \
             --build-arg INSTALL_PLANAHEAD="${INSTALL_PLANAHEAD}" \
             --build-arg INSTALL_EDK="${INSTALL_EDK}" \
             -f Dockerfile -t "${IMAGE}" .

echo -e "${GREEN}==>${NC} Done. Run ./run-docker.sh to start ISE."
