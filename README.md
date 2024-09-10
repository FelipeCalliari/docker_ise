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
./run_docker.sh
```


