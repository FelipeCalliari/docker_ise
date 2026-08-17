FROM ubuntu:14.04

# Temporary mount point for bind mounts.
ENV TMP_MNT=/tmp/mnt

RUN <<-EOF
set -e
apt-get -qq update
apt-get install -y --install-recommends \
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
apt-get -qq -y upgrade
locale-gen en_US.UTF-8
update-locale LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8
rpcbind
rm -rf /var/lib/apt/lists/*
mkdir -p ${TMP_MNT}
EOF

ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8
ENV TERM=xterm-256color

#### Don't use dash on Ubuntu

RUN <<-EOF
    which dash &> /dev/null && (\
    echo "dash dash/sh boolean false" | debconf-set-selections && \
    DEBIAN_FRONTEND=noninteractive dpkg-reconfigure dash) || \
    echo "Skipping dash reconfigure (not applicable)"
EOF

#### Install Xilinx

ARG SERVER_HOST
ARG XILINX_TAR

COPY headless-install.sh /

RUN --mount=type=bind,src=${XILINX_TAR},dst=${TMP_MNT}/ise.tar <<-EOF
    rm -rf /xilinx
    set -eux
    mkdir -p /xilinx
    cd /xilinx
    tar xvf ${TMP_MNT}/ise.tar
    yes | /xilinx/*/bin/lin64/batchxsetup --batch /headless-install.sh
    cd /
    rm -rf /xilinx
    mv /opt/Xilinx/14.7/ISE_DS/ISE/lib/lin64/libstdc++.so.6 /opt/Xilinx/14.7/ISE_DS/ISE/lib/lin64/libstdc++.so.6.distrib
    mv /opt/Xilinx/14.7/ISE_DS/ISE/lib/lin64/libstdc++.so.6.0.8 /opt/Xilinx/14.7/ISE_DS/ISE/lib/lin64/libstdc++.so.6.0.8.distrib
    ln /usr/lib/x86_64-linux-gnu/libstdc++.so.6 /opt/Xilinx/14.7/ISE_DS/ISE/lib/lin64/libstdc++.so.6
    ln /usr/lib/x86_64-linux-gnu/libstdc++.so.6.0.19 /opt/Xilinx/14.7/ISE_DS/ISE/lib/lin64/libstdc++.so.6.0.19
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
    cd /opt/usb-driver
    make
    ./setup_pcusb /opt/Xilinx/14.7/ISE_DS/ISE
EOF

# ENV LD_LIBRARY_PATH=/lib:/lib64:/usr/lib:/usr/lib64
ENV LD_PRELOAD=/opt/usb-driver/libusb-driver.so

# Load the JTAG cable firmware at startup. udev does not run inside
# the container, so fxload must load the firmware by hand.
COPY firmware-load.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/firmware-load.sh
ENV GUEST_USER=xilinx
ENV GUEST_HOME=/home/${GUEST_USER}
ENV UID_GID=1000

RUN <<EOF
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
RUN <<EOF
echo "${GUEST_USER} ALL=(ALL) NOPASSWD: /usr/local/bin/firmware-load.sh" > /etc/sudoers.d/${GUEST_USER}-firmware
chmod 440 /etc/sudoers.d/${GUEST_USER}-firmware
echo "sudo -n /usr/local/bin/firmware-load.sh 2>/dev/null" >> ${GUEST_HOME}/.bashrc
EOF

ADD Xilinx.lic /home/${GUEST_USER}/.Xilinx/

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
CMD sudo -n /usr/local/bin/firmware-load.sh; source /opt/Xilinx/14.7/ISE_DS/settings64.sh && ise

