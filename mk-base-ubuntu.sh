#!/bin/bash -e

if [ ! $TARGET ]; then
	echo "---------------------------------------------------------"
	echo "Please enter TARGET version number:"
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

if [ "$ARCH" == "armhf" ]; then
	ARCH='armhf'
elif [ "$ARCH" == "arm64" ]; then
	ARCH='arm64'
else
    ARCH="arm64"
    echo -e "\033[47;36m set default ARCH=arm64...... \033[0m"
fi

TARGET_ROOTFS_DIR="binary"

sudo rm -rf $TARGET_ROOTFS_DIR/

if [ ! -d $TARGET_ROOTFS_DIR ] ; then
    sudo mkdir -p $TARGET_ROOTFS_DIR

    UBUNTU_BASE_FILE="../ubuntu-base-20.04.1-base-arm64.tar.gz"
    if [ ! -e $UBUNTU_BASE_FILE ]; then
        echo -e "\033[47;36m Error: $UBUNTU_BASE_FILE not found! \033[0m"
        exit 1
    fi

    sudo -n tar -xzf $UBUNTU_BASE_FILE -C $TARGET_ROOTFS_DIR/
    sudo cp sources.list $TARGET_ROOTFS_DIR/etc/apt/sources.list
    sudo cp -b /etc/resolv.conf $TARGET_ROOTFS_DIR/etc/resolv.conf

    if [ "$ARCH" == "armhf" ]; then
	    sudo cp -b /usr/bin/qemu-arm-static $TARGET_ROOTFS_DIR/usr/bin/
    elif [ "$ARCH" == "arm64"  ]; then
	    sudo cp -b /usr/bin/qemu-aarch64-static $TARGET_ROOTFS_DIR/usr/bin/
    fi
fi

finish() {
    ./ch-mount.sh -u $TARGET_ROOTFS_DIR
    echo -e "error exit"
    exit -1
}
trap finish ERR

echo -e "\033[47;36m Change root.................... \033[0m"

./ch-mount.sh -m $TARGET_ROOTFS_DIR

cat <<EOF | sudo chroot $TARGET_ROOTFS_DIR/

export DEBIAN_FRONTEND=noninteractive
export APT_INSTALL="apt-get install -fy --allow-downgrades"

export LC_ALL=C.UTF-8

apt-get -y update
apt-get -f -y upgrade

if [ "$TARGET" == "gnome" ]; then
    apt install -y ubuntu-desktop-minimal rsyslog sudo dialog apt-utils ntp evtest onboard
    mv /var/lib/dpkg/info/ /var/lib/dpkg/info_old/
    mkdir /var/lib/dpkg/info/
    apt-get update
    apt install -y ubuntu-desktop-minimal rsyslog sudo dialog apt-utils ntp evtest onboard
    mv /var/lib/dpkg/info_old/* /var/lib/dpkg/info/
elif [ "$TARGET" == "xfce" ]; then
    apt install -y xubuntu-core onboard rsyslog sudo dialog apt-utils ntp evtest udev
    mv /var/lib/dpkg/info/ /var/lib/dpkg/info_old/
    mkdir /var/lib/dpkg/info/
    apt-get update
    apt install -y xubuntu-core onboard rsyslog sudo dialog apt-utils ntp evtest udev
    mv /var/lib/dpkg/info_old/* /var/lib/dpkg/info/
elif [ "$TARGET" == "lite" ]; then
    apt install -y rsyslog sudo dialog apt-utils ntp evtest acpid
elif [ "$TARGET" == "gnome-full" ]; then
    apt install -y ubuntu-desktop-minimal rsyslog sudo dialog apt-utils ntp evtest onboard
    mv /var/lib/dpkg/info/ /var/lib/dpkg/info_old/
    mkdir /var/lib/dpkg/info/
    apt-get update
    apt install -y ubuntu-desktop-minimal rsyslog sudo dialog apt-utils ntp evtest onboard
    mv /var/lib/dpkg/info_old/* /var/lib/dpkg/info/
elif [ "$TARGET" == "xfce-full" ]; then
    apt install -y xubuntu-desktop onboard rsyslog sudo dialog apt-utils ntp evtest udev
    mv /var/lib/dpkg/info/ /var/lib/dpkg/info_old/
    mkdir /var/lib/dpkg/info/
    apt-get update
    apt install -y xubuntu-desktop onboard rsyslog sudo dialog apt-utils ntp evtest udev
    mv /var/lib/dpkg/info_old/* /var/lib/dpkg/info/
fi

\${APT_INSTALL} net-tools openssh-server ifupdown alsa-utils ntp network-manager gdb inetutils-ping libssl-dev \
    vsftpd tcpdump can-utils i2c-tools strace vim iperf3 ethtool netplan.io toilet htop pciutils usbutils curl \
    whiptail gnupg bc xinput gdisk parted gcc sox libsox-fmt-all gpiod libgpiod-dev python3-pip python3-libgpiod \
    guvcview

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

pip3 install python-periphery Adafruit-Blinka -i https://mirrors.aliyun.com/pypi/simple/

HOST=ubuntu-2020.04

# Create user
useradd -G sudo -m -s /bin/bash linaro
echo "linaro:linaro" | chpasswd
gpasswd -a linaro video
gpasswd -a linaro audio
echo "root:linaro" | chpasswd

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
SUDOEXISTS="$(awk '$1 == "%sudo" { print $1 }' /etc/sudoers)"
if [ -z "$SUDOEXISTS" ]; then
  # append sudo entry to sudoers
  echo "# Members of the sudo group may gain root privileges" >> /etc/sudoers
  echo "%sudo	ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers
fi

# make sure that NOPASSWD is set for %sudo
# expecially in the case that we didn't add it to /etc/sudoers
# just blow the %sudo line away and force it to be NOPASSWD
sed -i -e '
/\%sudo/ c \
%sudo    ALL=(ALL) NOPASSWD: ALL
' /etc/sudoers

apt-get clean
rm -rf /var/lib/apt/lists/*

sync

EOF

./ch-mount.sh -u $TARGET_ROOTFS_DIR

if mount | grep -q "$TARGET_ROOTFS_DIR"; then
    echo -e "\033[47;31m WARNING: Some mount points still active, forcing unmount...\033[0m"
    # Kill any processes using the mount points
    sudo lsof +D "$TARGET_ROOTFS_DIR" 2>/dev/null | awk 'NR>1 {print $2}' | xargs -r sudo kill -9 2>/dev/null || true
    sleep 1
    # Force unmount
    sudo umount -f "$TARGET_ROOTFS_DIR"/proc 2>/dev/null || true
    sudo umount -f "$TARGET_ROOTFS_DIR"/sys 2>/dev/null || true
    sudo umount -f "$TARGET_ROOTFS_DIR"/dev 2>/dev/null || true
    sudo umount -f "$TARGET_ROOTFS_DIR"/run 2>/dev/null || true
    sudo umount -f "$TARGET_ROOTFS_DIR" 2>/dev/null || true
fi

DATE=$(date +%Y%m%d)
echo -e "\033[47;36m Run tar pack ubuntu-base-$TARGET-$ARCH-$DATE.tar.gz \033[0m"
sudo tar zcfv ubuntu-base-$TARGET-$ARCH-$DATE.tar.gz $TARGET_ROOTFS_DIR
echo -e "\033[47;36m Rootfs creation completed successfully! \033[0m"