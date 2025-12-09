#!/bin/bash -e

# Rootfs Directory
TARGET_ROOTFS_DIR="binary"

# Safe Exit
cleanup() {
    # Try to unmount the mount point (to avoid leftover files)
    if mount | grep -q "$TARGET_ROOTFS_DIR"; then
        echo -e "\033[47;31m WARNING: Unmounting $TARGET_ROOTFS_DIR... \033[0m"
        sudo -n ./ch-mount.sh -u "$TARGET_ROOTFS_DIR" 2>/dev/null || true
    fi
    
    # Clean up residual files (secure deletion)
    if [ -d "$TARGET_ROOTFS_DIR" ]; then
        echo -e "\033[47;31m WARNING: Removing $TARGET_ROOTFS_DIR... \033[0m"
        sudo -n rm -rf "$TARGET_ROOTFS_DIR" 2>/dev/null || true
    fi
    
    echo -e "\033[47;31m ERROR: Script failed. Cleaned up. \033[0m"
    exit 1
}

trap cleanup ERR

# Check if we can run sudo without password
if ! sudo -n true 2>/dev/null; then
    echo -e "\033[47;31m ERROR: This script requires sudo privileges without password prompt.\033[0m"
    echo -e "\033[47;31m Please configure sudoers to allow running sudo without password for your user.\033[0m"
    echo -e "\033[47;31m Add this line to /etc/sudoers using 'sudo visudo':\033[0m"
    echo -e "\033[47;31m your_username ALL=(ALL) NOPASSWD: ALL\033[0m"
    exit 1
fi

# Safe Initialization
if mount | grep -q "$TARGET_ROOTFS_DIR"; then
    sudo -n ./ch-mount.sh -u "$TARGET_ROOTFS_DIR" 2>/dev/null || true
fi

# Target System
if [ ! $TARGET ]; then
	echo "---------------------------------------------------------"
	echo "Please enter TARGET version number:"
	echo "Please enter the version of the root file system to be built:"
	echo "[0] Exit Menu"
	echo "[1] gnome"
	echo "[2] xfce"
	echo "[3] lite"
	echo "[4] gnome-full"
	echo "[5] xfce-full"
	echo "---------------------------------------------------------"
	read input

	case $input in
		0)
			exit;;
		1)
			TARGET=gnome
			;;
		2)
			TARGET=xfce
			;;
		3)
			TARGET=lite
			;;
		4)
			TARGET=gnome-full
			;;
		5)
			TARGET=xfce-full
			;;
		*)
			echo -e "\033[47;36m input TARGET version number error, exit ! \033[0m"
			exit;;
	esac
    echo -e "\033[47;36m set TARGET=$TARGET...... \033[0m"
fi

# Architecture
if [ "$ARCH" == "armhf" ]; then
	ARCH='armhf'
elif [ "$ARCH" == "arm64" ]; then
	ARCH='arm64'
else
    ARCH="arm64"
    echo -e "\033[47;36m set default ARCH=arm64...... \033[0m"
fi

# Create rootfs 
if [ ! -d $TARGET_ROOTFS_DIR ] ; then

    sudo -n mkdir -p "$TARGET_ROOTFS_DIR"

    UBUNTU_BASE_FILE="../ubuntu-base-20.04.1-base-arm64.tar.gz"
    if [ ! -e $UBUNTU_BASE_FILE ]; then
        echo -e "\033[47;36m Error: $UBUNTU_BASE_FILE not found! \033[0m"
        exit 1
    fi
    sudo -n tar -xzf $UBUNTU_BASE_FILE -C $TARGET_ROOTFS_DIR/
    sudo -n cp sources.list $TARGET_ROOTFS_DIR/etc/apt/sources.list
    sudo -n cp -b /etc/resolv.conf $TARGET_ROOTFS_DIR/etc/resolv.conf

    if [ "$ARCH" == "armhf" ]; then
	    sudo -n cp -b /usr/bin/qemu-arm-static $TARGET_ROOTFS_DIR/usr/bin/
    elif [ "$ARCH" == "arm64"  ]; then
	    sudo -n cp -b /usr/bin/qemu-aarch64-static $TARGET_ROOTFS_DIR/usr/bin/
    fi
fi

# Safety check for dpkg
if [ -d "$TARGET_ROOTFS_DIR/var/lib/dpkg/info" ]; then
    echo -e "\033[47;36m Detected dpkg info directory, fixing... \033[0m"
    sudo -n rm -rf "$TARGET_ROOTFS_DIR/var/lib/dpkg/info"
    sudo -n mkdir -p "$TARGET_ROOTFS_DIR/var/lib/dpkg/info"
fi

# Define package sets
GNOME_PACKAGES="ubuntu-desktop-minimal rsyslog sudo dialog apt-utils ntp evtest onboard"
XFC_PACKAGES="xubuntu-core onboard rsyslog sudo dialog apt-utils ntp evtest udev"
LITE_PACKAGES="rsyslog sudo dialog apt-utils ntp evtest acpid"
FULL_PACKAGES="net-tools openssh-server ifupdown alsa-utils ntp network-manager gdb inetutils-ping libssl-dev vsftpd tcpdump can-utils i2c-tools strace vim iperf3 ethtool netplan.io toilet htop pciutils usbutils curl whiptail gnupg bc xinput gdisk parted gcc sox libsox-fmt-all gpiod libgpiod-dev python3-pip python3-libgpiod guvcview ffmpeg"

# Change Root
echo -e "\033[47;36m Change root.................... \033[0m"

sudo -n ./ch-mount.sh -m $TARGET_ROOTFS_DIR
# Configure System
cat <<EOF | sudo -n chroot $TARGET_ROOTFS_DIR/

export DEBIAN_FRONTEND=noninteractive
export APT_INSTALL="apt-get install -fy --allow-downgrades"

export LC_ALL=C.UTF-8

apt-get -y update
apt-get -f -y upgrade

# enter root username without password
sed -i "s~\(^ExecStart=.*\)~# \1\nExecStart=-/bin/sh -c '/bin/bash -l </dev/%I >/dev/%I 2>\&1'~" /usr/lib/systemd/system/serial-getty@.service

# Install base packages
case "$TARGET" in
    gnome|gnome-full) pkg_list="$GNOME_PACKAGES" ;;
    xfce|xfce-full) pkg_list="$XFC_PACKAGES" ;;
    lite) pkg_list="$LITE_PACKAGES" ;;
    *) echo "Invalid TARGET: $TARGET"; exit 1 ;;
esac
$APT_INSTALL $pkg_list

# Install full packages
$APT_INSTALL $FULL_PACKAGES

\${APT_INSTALL} ttf-wqy-zenhei xfonts-intl-chinese

if [[ "$TARGET" == "gnome-full" ||  "$TARGET" == "xfce-full" ]]; then
    apt purge ibus firefox -y

    echo -e "\033[47;36m Install English fonts.................... \033[0m"
    \${APT_INSTALL} language-pack-en-base gnome-user-docs-en language-pack-gnome-en

    # set default xinput for fcitx
    \${APT_INSTALL} fcitx fcitx-table fcitx-googlepinyin fcitx-pinyin fcitx-config-gtk
    sed -i 's/default/fcitx/g' /etc/X11/xinit/xinputrc

    \${APT_INSTALL} ipython3 jupyter

    ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
    timedatectl set-timezone Asia/Shanghai

    # Uncomment en_US.UTF-8 for inclusion in generation
    sed -i 's/^# *\(en_US.UTF-8\)/\1/' /etc/locale.gen
    echo "LANG=en_US.UTF-8" >> /etc/default/locale

    # Generate locale
    locale-gen en_US.UTF-8

    # Export env vars
    echo "LC_ALL=en_US.UTF-8" >> /etc/environment    
    echo "LANG=en_US.UTF-8" >> /etc/environment
    echo "LANGUAGE=en_US:en" >> /etc/environment

    \${APT_INSTALL} $(check-language-support)
fi

if [[ "$TARGET" == "gnome" || "$TARGET" == "gnome-full" ]]; then
    \${APT_INSTALL} mpv acpid gnome-sound-recorder
elif [[ "$TARGET" == "xfce" || "$TARGET" == "xfce-full" ]]; then
    \${APT_INSTALL} mpv acpid gnome-sound-recorder
elif [ "$TARGET" == "lite" ]; then
    \${APT_INSTALL}  
fi

pip3 install python-periphery -i https://mirrors.aliyun.com/pypi/simple/

HOST=linaro

# Create user
useradd -G sudo -m -s /bin/bash linaro
echo "linaro:linaro" | chpasswd
gpasswd -a linaro video
gpasswd -a linaro audio
echo "root:root" | chpasswd

# allow root login
sed -i '/pam_securetty.so/s/^/# /g' /etc/pam.d/login

# hostname
echo linaro > /etc/hostname

# set localtime
ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime

# workaround 90s delay
services=(NetworkManager systemd-networkd)
for service in ${services[@]}; do
  systemctl mask ${service}-wait-online.service
done

# disbale the wire/nl80211
systemctl mask wpa_supplicant-wired@
systemctl mask wpa_supplicant-nl80211@
systemctl mask wpa_supplicant@

# Make systemd less spammy

sed -i 's/#LogLevel=info/LogLevel=warning/' \
  /etc/systemd/system.conf

sed -i 's/#LogTarget=journal-or-kmsg/LogTarget=journal/' \
  /etc/systemd/system.conf

# check to make sure sudoers file has ref for the sudo group
SUDOEXISTS="\$(awk '\$1 == "%sudo" { print \$1 }' /etc/sudoers)"
if [ -z "\$SUDOEXISTS" ]; then
  # append sudo entry to sudoers
  echo "# Members of the sudo group may gain root privileges" >> /etc/sudoers
  echo "%sudo	ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers
fi

# make sure that NOPASSWD is set for %sudo
# expecially in the case that we didn't add it to /etc/sudoers
# just blow the %sudo line away and force it to be NOPASSWD
sed -i '/%sudo/ c \%sudo ALL=(ALL) NOPASSWD: ALL' /etc/sudoers

apt-get clean
rm -rf /var/lib/apt/lists/*

sync

EOF

echo -e "\033[47;36m Mounting rootfs... \033[0m"
sudo -n ./ch-mount.sh -m "$TARGET_ROOTFS_DIR"

cat <<EOF | sudo -n chroot "$TARGET_ROOTFS_DIR" /bin/bash
# ... [All configuration commands remain unchanged] ...
EOF

echo -e "\033[47;36m Unmounting rootfs... \033[0m"
sudo -n ./ch-mount.sh -u "$TARGET_ROOTFS_DIR" 2>/dev/null || true

DATE=$(date +%Y%m%d)
echo -e "\033[47;36m Run tar pack ubuntu-base-$TARGET-$ARCH-$DATE.tar.gz \033[0m"
sudo -n tar zcf ubuntu-base-$TARGET-$ARCH-$DATE.tar.gz $TARGET_ROOTFS_DIR