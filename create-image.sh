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
# Make sure this file or a link to it is in the same
# directory as this script. With INSTALL_METHOD=bind it must be a real
# file or a hard link: BuildKit does not follow symlinks in the context.
XILINX_TAR=${XILINX_TAR:-Xilinx_ISE_DS_14.7_1015_1.tar}
XILINX_LIC=${XILINX_LIC:-Xilinx.lic}

# Install trimming -- see the ARG comments in the Dockerfile.
KEEP_SERIES7=${KEEP_SERIES7:-0}
INSTALL_PLANAHEAD=${INSTALL_PLANAHEAD:-1}
INSTALL_EDK=${INSTALL_EDK:-0}

# How the build gets the tar -- see the INSTALL_METHOD comment in the
# Dockerfile.
INSTALL_METHOD=${INSTALL_METHOD:-http}
# Local port the installer is served on with INSTALL_METHOD=http. Change it
# if another build (e.g. the Vivado one) is already using it.
INSTALLER_PORT=${INSTALLER_PORT:-8000}
INSTALLER_URL=http://127.0.0.1:${INSTALLER_PORT}

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
  INSTALL_METHOD     http to stream the tar from a local server, bind to
                     bind-mount it (~8GB more disk during the build)
                     (default: http)
  INSTALLER_PORT     Local port for INSTALL_METHOD=http (default: 8000)
USAGE
            exit 0
            ;;
        *) die "unknown option '$arg' (see --help)" ;;
    esac
done

# A symlink whose target is missing usually means the disk holding the
# installer is not mounted; say so instead of just "could not find".
check_file() {
    if [[ -L "$1" && ! -e "$1" ]]; then
        die "$1 is a broken symlink to $(readlink "$1") (is the disk mounted?)"
    fi
    [[ -f "$1" ]] || die "could not find $1"
}
check_file "$XILINX_TAR"
check_file "$XILINX_LIC"

TAR_NAME=$(basename "$XILINX_TAR")
case "$INSTALL_METHOD" in
    http)
        INSTALL_ARGS=(--network=host --build-arg INSTALLER_URL="${INSTALLER_URL}")
        ;;
    bind)
        [[ "$XILINX_TAR" == "$TAR_NAME" && ! -L "$XILINX_TAR" ]] ||
            die "INSTALL_METHOD=bind needs ${TAR_NAME} as a real file (or hard link) in this directory"
        INSTALL_ARGS=(--build-arg INSTALLER_SRC="${TAR_NAME}")
        ;;
    *) die "INSTALL_METHOD must be http or bind, not '${INSTALL_METHOD}'" ;;
esac

# The usb-driver submodule is compiled during the build; without it the
# build fails halfway through the ~1h ISE installation.
[[ -f usb-driver/Makefile ]] || die "usb-driver/ is empty. Run: git submodule update --init"

if [[ "$INSTALL_METHOD" == http ]]; then
    # Another server on that port would answer the build instead of ours.
    if curl -s -o /dev/null "${INSTALLER_URL}/"; then
        die "port ${INSTALLER_PORT} is already in use (set INSTALLER_PORT to use another)"
    fi

    # Serve only the installer, only on localhost. The symlink points to the
    # real file, so the installer may live anywhere (e.g. an external disk).
    SERVE_DIR=$(mktemp -d)
    ln -s "$(readlink -f "$XILINX_TAR")" "$SERVE_DIR/$TAR_NAME"
    python3 -m http.server --bind 127.0.0.1 --directory "$SERVE_DIR" "$INSTALLER_PORT" >/dev/null 2>&1 &
    SERVER_PID=$!
    # Stop the server even if the build fails.
    trap 'kill $SERVER_PID 2>/dev/null || true; rm -rf "$SERVE_DIR"' EXIT

    # Wait until the server answers. If python exits instead, the port is
    # most likely taken by something else.
    ready=0
    for _ in {1..50}; do
        if curl -sfI "${INSTALLER_URL}/${TAR_NAME}" >/dev/null; then
            ready=1
            break
        fi
        kill -0 "$SERVER_PID" 2>/dev/null || die "http.server failed to start (is port ${INSTALLER_PORT} in use?)"
        sleep 0.1
    done
    (( ready )) || die "http.server did not answer on ${INSTALLER_URL}"
fi

echo -e "${GREEN}==>${NC} Building ${IMAGE}..."
docker build "${NO_CACHE[@]}" "${INSTALL_ARGS[@]}" --progress=plain \
             --build-arg INSTALL_METHOD="${INSTALL_METHOD}" \
             --build-arg XILINX_TAR="${TAR_NAME}" \
             --build-arg UID_GID="$(id -u)" \
             --build-arg KEEP_SERIES7="${KEEP_SERIES7}" \
             --build-arg INSTALL_PLANAHEAD="${INSTALL_PLANAHEAD}" \
             --build-arg INSTALL_EDK="${INSTALL_EDK}" \
             -f Dockerfile -t "${IMAGE}" .

echo -e "${GREEN}==>${NC} Done. Run ./run-docker.sh to start ISE."
