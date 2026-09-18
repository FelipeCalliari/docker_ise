FROM ubuntu:14.04

# Temporary mount point for bind mounts.
ENV TMP_MNT=/tmp/mnt
# Installation prefix of the ISE Design Suite.
ENV ISE_ROOT=/opt/Xilinx/14.7/ISE_DS

# --install-recommends is deliberate: the ISE installer pulls in libraries
# implicitly and the recommends happen to cover them. firefox is used by the
# ISE help/documentation viewer.
RUN <<-EOF
set -eux
DEBIAN_FRONTEND=noninteractive apt-get -qq update
DEBIAN_FRONTEND=noninteractive apt-get install -y --install-recommends \
    firefox ca-certificates udev \
    git gitk git-gui mercurial pkg-config gnat \
    vim fxload gnupg sudo apt-utils locales rpcbind \
    libusb-1.0-0 libftdi1 libftdi-dev libffi-dev \
    libusb-dev libglib2.0-0 libxtst6 libc6-dev-i386 \
    libncurses5 libqt4-core libqt4-network libx11-6 \
    libsm-dev libsm6 libxi6 libgconf-2-4 libxrender1 \
    libtcl8.4 libxrandr2 libfreetype6 libfontconfig1 \
    libxm4 libxp6 libstdc++5 lib32z1 libxi-dev \
    libxrender-dev libxrandr-dev libfontconfig-dev \
    libtinfo5 libtool bison tmux nano screen dosfstools \
    make cmake build-essential g++ gcc gcc-multilib \
    mtools xinetd wget curl rsync minicom urjtag \
    xfonts-75dpi xfonts-100dpi
locale-gen en_US.UTF-8
update-locale LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8
rm -rf /var/lib/apt/lists/*
mkdir -p ${TMP_MNT}
EOF

ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8
ENV TERM=xterm-256color

#### Don't use dash on Ubuntu

RUN <<-EOF
    set -eu
    if which dash >/dev/null 2>&1; then
        echo "dash dash/sh boolean false" | debconf-set-selections
        DEBIAN_FRONTEND=noninteractive dpkg-reconfigure dash
    else
        echo "Skipping dash reconfigure (not applicable)"
    fi
EOF

#### Install Xilinx

ARG XILINX_TAR

# Trim what gets kept from the install. Both prunes MUST happen inside the
# same RUN as the installation: a `rm` in a later layer hides the files but
# the earlier layer still carries them, so the image would not shrink.
#
# KEEP_SERIES7=0 drops Artix-7/Kintex-7/Virtex-7/Zynq-7000 (~3GB). ISE 14.7
# does support them, but Vivado is the right tool for those parts.
ARG KEEP_SERIES7=0
# PlanAhead (~3.6GB) is part of the edition and cannot be deselected in the
# answer file, so it is removed afterwards if unwanted. Kept by default:
# ISE Project Navigator's floorplanning entries launch it.
ARG INSTALL_PLANAHEAD=1
# EDK (~5GB: MicroBlaze/PowerPC soft-core tooling, the Eclipse-based SDK and
# its cross toolchains) is only needed to build a CPU into the fabric; a pure
# RTL flow never touches it. Logic Edition includes EDK in WebPACK/Logic/DSP
# as "Device Limited to Zynq-7000 EPP - Z7010, Z7020, Z7030 devices only".
# So with KEEP_SERIES7=0 there is no Zynq left for a Logic-Edition EDK to
# serve at all.
ARG INSTALL_EDK=0

COPY headless-install.conf /

RUN --mount=type=bind,src=${XILINX_TAR},dst=${TMP_MNT}/ise.tar <<-EOF
    rm -rf /xilinx
    set -eux
    mkdir -p /xilinx
    cd /xilinx
    tar xvf ${TMP_MNT}/ise.tar
    yes | /xilinx/*/bin/lin64/batchxsetup --batch /headless-install.conf
    cd /
    rm -rf /xilinx /headless-install.conf

    if [ "${KEEP_SERIES7}" = "0" ]; then
        find /opt/Xilinx/14.7/ISE_DS -maxdepth 6 -type d \
            \( -iname '*virtex7*' -o -iname '*kintex7*' -o -iname '*artix7*' \
               -o -iname '*zynq*' -o -iname '*7series*' -o -iname '*series7*' \) \
            -prune -exec rm -rf {} +
    fi

    if [ "${INSTALL_PLANAHEAD}" = "0" ]; then
        rm -rf ${ISE_ROOT}/PlanAhead
    fi

    if [ "${INSTALL_EDK}" = "0" ]; then
        rm -rf ${ISE_ROOT}/EDK
    fi

    mv ${ISE_ROOT}/ISE/lib/lin64/libstdc++.so.6 ${ISE_ROOT}/ISE/lib/lin64/libstdc++.so.6.distrib
    mv ${ISE_ROOT}/ISE/lib/lin64/libstdc++.so.6.0.8 ${ISE_ROOT}/ISE/lib/lin64/libstdc++.so.6.0.8.distrib
    ln /usr/lib/x86_64-linux-gnu/libstdc++.so.6 ${ISE_ROOT}/ISE/lib/lin64/libstdc++.so.6
    ln /usr/lib/x86_64-linux-gnu/libstdc++.so.6.0.19 ${ISE_ROOT}/ISE/lib/lin64/libstdc++.so.6.0.19
    ln -s /usr/lib/x86_64-linux-gnu/libQtNetwork.so.4 /usr/lib/x86_64-linux-gnu/libQt_Network.so
    ln -s /usr/lib/x86_64-linux-gnu/libXpm.so.4 /lib/x86_64-linux-gnu/libXp.so.6
EOF

#### USB driver wrapper for Digilent / Platform Cable (libusb-driver)

#RUN <<-EOF
#    cd /opt/Xilinx/14.7/ISE_DS/ISE/bin/lin64/digilent/
#    bash install_digilent.sh
#EOF

COPY usb-driver/ /opt/usb-driver

RUN <<-EOF
    set -eux
    cd /opt/usb-driver
    make
    ./setup_pcusb ${ISE_ROOT}/ISE
EOF

# ENV LD_LIBRARY_PATH=/lib:/lib64:/usr/lib:/usr/lib64
ENV LD_PRELOAD=/opt/usb-driver/libusb-driver.so

# Load the JTAG cable firmware at startup. udev does not run inside
# the container, so fxload must load the firmware by hand.
COPY firmware-load.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/firmware-load.sh
ENV GUEST_USER=xilinx
ENV GUEST_HOME=/home/${GUEST_USER}

# Match the host user's uid/gid so files in the bind-mounted home keep the
# right owner. create-image.sh passes --build-arg UID_GID="$(id -u)".
ARG UID_GID=1000

RUN <<EOF
set -eux
groupadd -g ${UID_GID} ${GUEST_USER}
useradd -d ${GUEST_HOME} -s /bin/bash -m ${GUEST_USER} -u ${UID_GID} -g ${UID_GID}
passwd -d ${GUEST_USER}
usermod -aG plugdev ${GUEST_USER}
usermod -aG dialout ${GUEST_USER}
mkdir -p ${GUEST_HOME}/.Xilinx
EOF

# Allow the guest user to load the cable firmware (needs write access
# to /dev/bus/usb, which belongs to root on the host). And load the
# cable firmware on every interactive shell too (e.g. --bash).
# /etc/motd is only shown on PAM logins, so .bashrc prints it.
RUN <<EOF
set -eux
echo "${GUEST_USER} ALL=(ALL) NOPASSWD: /usr/local/bin/firmware-load.sh" > /etc/sudoers.d/${GUEST_USER}-firmware
chmod 440 /etc/sudoers.d/${GUEST_USER}-firmware
rm -f /etc/motd
cat > /etc/motd <<'MOTD'

 Xilinx ISE 14.7 (docker)

 The JTAG cable firmware is loaded when the shell starts. udev does not
 run inside the container, so if the cable is plugged in later (or is
 not detected by iMPACT), load the firmware by hand:

     sudo firmware-load.sh

MOTD
echo "cat /etc/motd" >> ${GUEST_HOME}/.bashrc
echo "sudo -n /usr/local/bin/firmware-load.sh 2>/dev/null" >> ${GUEST_HOME}/.bashrc
echo "cat /etc/motd" >> /root/.bashrc
echo "/usr/local/bin/firmware-load.sh 2>/dev/null" >> /root/.bashrc
EOF

COPY Xilinx.lic /home/${GUEST_USER}/.Xilinx/

COPY <<EOF /home/${GUEST_USER}/.config/Xilinx/ISE.conf
[14.7]
Project%20Navigator/TipOfDay/ShowTipAtStartUp=false
ECS/Settings/ISETEXTEDITOR="bUseSpace=true;bShowWhitespace=false;bShowEol=false;bShowIndent=false;bUseBlackColorScheme=false;tabWidth=4;font=Courier,12,-1,5,50,0,0,0,0,0;longLinesLimit=80;bShowLineNumbers=true;bShowOutline=false;"
EOF

RUN chown -hR ${GUEST_USER}:${GUEST_USER} ${GUEST_HOME}

USER ${GUEST_USER}
WORKDIR ${GUEST_HOME}
ENV HOME=${GUEST_HOME}
SHELL ["/bin/bash", "-c"]
CMD sudo -n /usr/local/bin/firmware-load.sh; source ${ISE_ROOT}/settings64.sh && ise

