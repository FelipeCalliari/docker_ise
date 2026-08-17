# Docker image for Xilinx ISE 14.7

Xilinx ISE 14.7 was released around 2013 and has since been discontinued.

Running it on a modern Linux distro usually means installing older libraries or working around ones that no longer fit.

This `Dockerfile` create a working environment with all the tools needed to develop with Xilinx's FPGAs and CPLDs for all families (CoolRunner, Spartan, Virtex, etc) up to Series 6.

## Requirements

- You must download Xilinx ISE 14.7 tar file from Xilinx's website.
- You must have an Xilinx License file, you can obtain a WebPack License, for example.
- Both `Xilinx_ISE_DS_14.7_1015_1.tar` and `Xilinx.lic` must be inside this folder when creating the Docker image.
 
## Building the image

With all the needed files, Dockerfile, etc in the same directory, just run:

```bash
./create_image.sh
```

This script will create an `http.server` using Python to host `Xilinx_ISE_DS_14.7_1015_1.tar` to Docker build process. This HACK seems a bit messy but will reduce the image size significantly (it will not create a layer with `Xilinx_ISE_DS_14.7_1015_1.tar` ~8GB).

## Running the image

Just run: 

```bash
./run_docker.sh                 # run ISE
./run_docker.sh --bash          # run bash as xilinx (user)
./run_docker.sh --root --bash   # run bash as root
```

This mounts your home directory inside `/home/xilinx/shared` and X11 socket into the container so the ISE GUI can run and display on your host.

## How to use

```bash
# Docker image creation. Do this only on the first time.
./create_image.sh

# Optional: install cable firmware + udev rules on the host
# (needed only if you want the JTAG cable loaded by the host,
# or to run ISE on the host itself; the container loads the
# firmware automatically via fxload)
./setup_host.sh

# After that, just run this command to start ISE
./run_docker.sh
```

## Programming the FPGAs

Programming the CPLDs and/or FPGAs traditionally requires the proprietary Jungo `windrvr6` driver, which only targets Linux 2.6.x (and maybe some early 3.x kernels) — a non-starter on current systems.

To work around this, the image installs the following tools instead:

- **[`usb-driver`](git://git.zerfleddert.de/usb-driver)** (a.k.a. `libusb-driver`): A `LD_PRELOAD`-able shim that reimplements the `windrvr6` API on top of `libusb`, so Xilinx's own tools (`impact`, `ise`) talk to the cable without the kernel driver.
- **`urJTAG`**: A command-line tool for JTAG-aware devices, with broad cable and board support via `libusb`, as a fallback/alternative to the Xilinx tools.
