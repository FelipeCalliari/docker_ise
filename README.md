# Docker image for Xilinx ISE 14.7

Xilinx ISE 14.7 was released around 2013 and has since been discontinued.

Running it on a modern Linux distro usually means installing older libraries or working around ones that no longer fit.

This `Dockerfile` create a working environment with all the tools needed to develop with Xilinx's FPGAs and CPLDs for all families (CoolRunner, Spartan, Virtex, etc) up to Series 6.

## Requirements

- Docker with BuildKit (Docker 23 or newer) — the build uses `RUN --mount=type=bind`.
- Clone with submodules, otherwise the build fails partway through the ISE install:

  ```bash
  git clone --recurse-submodules <repo>
  # or, in an existing clone:
  git submodule update --init
  ```
- You must download Xilinx ISE 14.7 tar file from Xilinx's website.
- You must have an Xilinx License file, you can obtain a WebPack License, for example.
- Both `Xilinx_ISE_DS_14.7_1015_1.tar` and `Xilinx.lic` must be inside this folder when creating the Docker image.

## Building the image

With all the needed files, Dockerfile, etc in the same directory, just run:

```bash
./create-image.sh              # reuses the layer cache
./create-image.sh --no-cache   # full rebuild from scratch
```

A full rebuild takes **~8 min** on NVMe. The breakdown is not what you would
guess: installing ISE is ~1 min, `apt` is ~3 min, and **~4 min goes to
compressing the image layers on export**. Build time therefore tracks image
size, which is what the trimming options below are really buying you — with
everything installed, the same build took ~11 min. On a spinning disk, expect
this to be several times longer.

### Trimming the install

The image is ~20GB on disk (5.8GB compressed) by default. Three build args
control what is kept; all three act **inside the install layer**, since a
later `rm` would hide files without shrinking the image.

| Build arg | Default | Effect |
|---|---|---|
| `KEEP_SERIES7` | `0` | Drops Artix-7/Kintex-7/Virtex-7/Zynq-7000 (~3GB, spread across `ISE/`, `PlanAhead/data/parts/` and `ISE/data/cse/cseflash/`). Use Vivado for those parts. |
| `INSTALL_EDK` | `0` | Drops EDK/SDK (~5GB): XPS, the Eclipse-based SDK and the MicroBlaze/PowerPC/ARM cross toolchains. Only needed to put a soft-core CPU in the fabric. |
| `INSTALL_PLANAHEAD` | `1` | Keeps PlanAhead (~2.4GB); ISE's floorplanning menu entries launch it. |

Restore anything you need via the environment, e.g.:

```bash
KEEP_SERIES7=1 INSTALL_EDK=1 ./create-image.sh
```

Note that picking a smaller edition in `headless-install.conf` is **not** an
alternative to `INSTALL_EDK=0`: Xilinx's edition matrix (XMP075) lists EDK as
included in WebPACK/Logic/DSP too, "Device Limited to Zynq-7000 EPP". Measured,
Logic Edition saved only ~0.1GB over System Edition once the prunes are applied.

The ~8 GB installer tar is **bind-mounted** into the build (`RUN --mount=type=bind`)
rather than copied, so it never becomes an image layer. A `.dockerignore` keeps the
rest of the directory out of the build context.

## Running the image

Just run: 

```bash
./run-docker.sh                 # run ISE as xilinx (user)
./run-docker.sh --root          # run ISE as root
./run-docker.sh --bash          # run bash as xilinx (user)
./run-docker.sh --root --bash   # run bash as root
```

In a shell, load the ISE environment before calling the tools (`ise`, `impact`, ...):

```bash
source /opt/Xilinx/14.7/ISE_DS/settings64.sh
```

This mounts your home directory inside `/home/xilinx/shared` and X11 socket into the container so the ISE GUI can run and display on your host.

### Environment variables

| Variable | Default | Used by |
|---|---|---|
| `IMAGE` | `xilinx-ise:14.7` | all scripts |
| `XILINX_TAR` | `Xilinx_ISE_DS_14.7_1015_1.tar` | `create-image.sh` |
| `XILINX_LIC` | `Xilinx.lic` | `create-image.sh` |
| `SHARED_DIR` | `$HOME` | `run-docker.sh` — host dir mounted at `~/shared` |
| `NETWORK` | `host` | `run-docker.sh` — Docker network mode |
| `LICENSE_MAC` | `01:ab:23:cd:45:ef` | `run-docker.sh` — only applied when `NETWORK` is not `host` |

### Changing the container's MAC address

Some Xilinx licenses are node-locked to a MAC address. To present a specific MAC to
the tools inside the container you must **leave host networking**: Docker silently
ignores `--mac-address` under `--net=host`, because in that mode the container shares
the host's network namespace and simply sees the host's real interfaces (`wlan0`,
`eth0`, ...) — there is no container interface to assign a MAC to.

So set `NETWORK` to anything other than `host`, and `run-docker.sh` will add
`--mac-address` for you:

```bash
NETWORK=bridge LICENSE_MAC=01:ab:23:cd:45:ef ./run-docker.sh
```

Check that it took effect inside the container:

```bash
NETWORK=bridge ./run-docker.sh --bash
# then:
cat /sys/class/net/eth0/address     # should print the MAC you asked for
```

Two things change when you drop `--net=host`:

- `--ipc=host` is dropped with it (it only exists to pair with host networking).
  `QT_X11_NO_MITSHM=1` is already set, so the GUI does not depend on shared IPC.
- The container gets its own network namespace, so a **floating license server**
  reachable only on the host's loopback would no longer be visible. Node-locked
  licenses (the usual WebPACK case) are unaffected.

If the GUI stops working on bridge networking, the X11 cookie is usually the cause —
the container is no longer on the host's network namespace, so `DISPLAY=:0` over the
UNIX socket still works, but a `DISPLAY` pointing at `localhost:0` (TCP) will not.

### What `setup-host.sh` changes on your host

It is optional, and it needs `sudo`. It:

- adds your user to `plugdev` and to the distro's serial group (`uucp` on Arch,
  `dialout` on Debian/Ubuntu/SUSE);
- copies the cable firmware (`xusb*.hex`) out of the image into `/usr/share/`;
- installs `/etc/udev/rules.d/xusbdfwu.rules` and `/etc/udev/rules.d/50-xilinx-cable.rules`.

To undo it, remove those two rules files and the `/usr/share/xusb*.hex` copies, then
`sudo udevadm control --reload-rules`. Group membership can be reverted with
`sudo gpasswd -d "$USER" plugdev`.

## Troubleshooting

- **Cable not detected by iMPACT** — udev does not run inside the container, so the
  firmware is loaded at shell/container startup. If the cable was plugged in later,
  run `sudo firmware-load.sh` inside the container.
- **GUI does not open** — check that `$DISPLAY` is set and that `$XAUTHORITY` points at
  a readable cookie file. On a Wayland session without one, try
  `xhost +si:localuser:$USER` on the host.
- **Build fails right after the ISE install starts** — `usb-driver/` is empty; run
  `git submodule update --init`.

## How to use

```bash
# Docker image creation. Do this only on the first time.
./create-image.sh

# Optional: install cable firmware + udev rules on the host.
# The container loads the firmware via fxload only when it starts;
# with the host rules, the cable is also loaded when plugged in
# later (otherwise run `sudo firmware-load.sh` inside the container).
./setup-host.sh

# After that, just run this command to start ISE
./run-docker.sh
```

## Programming the FPGAs

Programming the CPLDs and/or FPGAs traditionally requires the proprietary Jungo `windrvr6` driver, which only targets Linux 2.6.x (and maybe some early 3.x kernels) — a non-starter on current systems.

To work around this, the image installs the following tools instead:

- **[`usb-driver`](https://git.zerfleddert.de/git/usb-driver)** (a.k.a. `libusb-driver`): A `LD_PRELOAD`-able shim that reimplements the `windrvr6` API on top of `libusb`, so Xilinx's own tools (`impact`, `ise`) talk to the cable without the kernel driver.
- **`urJTAG`**: A command-line tool for JTAG-aware devices, with broad cable and board support via `libusb`, as a fallback/alternative to the Xilinx tools.

## Development

```bash
make help    # list the available targets
make lint    # shellcheck + hadolint
```

## License

This repository is MIT-licensed (see `LICENSE`). It does **not** distribute Xilinx ISE:
obtaining `Xilinx_ISE_DS_14.7_1015_1.tar` and a valid `Xilinx.lic`, and complying with
Xilinx's licence terms, is up to you. Both files are gitignored.
