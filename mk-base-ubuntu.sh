#!/bin/bash
set -Eeuo pipefail

if [ -z "${TARGET:-}" ]; then
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

if [ "${ARCH:-}" == "armhf" ]; then
	ARCH='armhf'
elif [ "${ARCH:-}" == "arm64" ]; then
	ARCH='arm64'
else
    ARCH="arm64"
    echo -e "\033[47;36m set default ARCH=arm64...... \033[0m"
fi

TARGET_ROOTFS_DIR="binary"

sudo rm -rf $TARGET_ROOTFS_DIR/

if [ ! -d $TARGET_ROOTFS_DIR ] ; then
    sudo mkdir -p $TARGET_ROOTFS_DIR

    UBUNTU_BASE_FILE="./ubuntu-base-22.04.5-base-arm64.tar.gz"
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

cleanup() {
    set +e
    ./ch-mount.sh -u "$TARGET_ROOTFS_DIR" >/dev/null 2>&1 || true
}
on_error() {
    local code=$?
    cleanup
    exit "$code"
}
trap cleanup INT TERM EXIT
trap on_error ERR

echo -e "\033[47;36m Change root.................... \033[0m"

./ch-mount.sh -u "$TARGET_ROOTFS_DIR" >/dev/null 2>&1 || true
sudo rm -f "$TARGET_ROOTFS_DIR/etc/resolv.conf"
sudo cp -Lf /etc/resolv.conf "$TARGET_ROOTFS_DIR/etc/resolv.conf"
./ch-mount.sh -m "$TARGET_ROOTFS_DIR"

sudo chroot "$TARGET_ROOTFS_DIR" /usr/bin/env TARGET="$TARGET" ARCH="$ARCH" /bin/bash <<'EOF'

export DEBIAN_FRONTEND=noninteractive
export APT_INSTALL="apt-get install -fy --allow-downgrades -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold"

# pre-installed software

export LC_ALL=C.UTF-8

# Ensure DNS works inside chroot
mkdir -p /etc
echo "nameserver 8.8.8.8" > /etc/resolv.conf
echo "nameserver 1.1.1.1" >> /etc/resolv.conf

apt-get -y update
apt-get -f -y upgrade

# Install systemd tools and basic system utilities
${APT_INSTALL} systemd systemd-sysv util-linux sysvinit-utils

# Install basic network tools first
${APT_INSTALL} iproute2 net-tools inetutils-ping ifupdown network-manager openssh-server curl wget dnsutils wireless-tools wpasupplicant

apt-get update

if [ "$TARGET" == "gnome" ]; then
    ${APT_INSTALL} ubuntu-desktop-minimal gdm3 rsyslog sudo dialog apt-utils ntp evtest onboard
    dpkg -l | grep -q ubuntu-desktop-minimal || { echo "ubuntu-desktop-minimal install failed"; exit 1; }
    dpkg -l | grep -q gdm3 || { echo "gdm3 install failed"; exit 1; }
elif [ "$TARGET" == "xfce" ]; then
    ${APT_INSTALL} xubuntu-core lightdm onboard rsyslog sudo dialog apt-utils ntp evtest udev
    dpkg -l | grep -q xubuntu-core || { echo "xubuntu-core install failed"; exit 1; }
    dpkg -l | grep -q lightdm || { echo "lightdm install failed"; exit 1; }
elif [ "$TARGET" == "lite" ]; then
    ${APT_INSTALL} rsyslog sudo dialog apt-utils ntp evtest acpid
elif [ "$TARGET" == "gnome-full" ]; then
    ${APT_INSTALL} ubuntu-desktop gdm3 rsyslog sudo dialog apt-utils ntp evtest onboard
    dpkg -l | grep -q ubuntu-desktop || { echo "ubuntu-desktop install failed"; exit 1; }
    dpkg -l | grep -q gdm3 || { echo "gdm3 install failed"; exit 1; }
elif [ "$TARGET" == "xfce-full" ]; then
    ${APT_INSTALL} xubuntu-desktop lightdm onboard rsyslog sudo dialog apt-utils ntp evtest udev
    dpkg -l | grep -q xubuntu-desktop || { echo "xubuntu-desktop install failed"; exit 1; }
    dpkg -l | grep -q lightdm || { echo "lightdm install failed"; exit 1; }
fi

${APT_INSTALL} alsa-utils ntp gdb libssl-dev \
    vsftpd tcpdump can-utils i2c-tools strace vim iperf3 ethtool netplan.io htop pciutils usbutils curl \
    whiptail gnupg bc xinput gdisk parted gcc sox libsox-fmt-all gpiod libgpiod-dev python3-pip python3-libgpiod \
    guvcview git tree wpasupplicant lsof lsb-release

${APT_INSTALL} lsb-core || true

# Common board-side compatibility deps for DKMS modules, Python helpers and
# vendor binaries that still link against legacy ncurses/tinfo ABI.
${APT_INSTALL} dkms build-essential kmod pkg-config python3 python-is-python3 python3-dev python3-venv \
    python3-setuptools python3-wheel libncurses5 libtinfo5 libatomic1

${APT_INSTALL} ttf-wqy-zenhei xfonts-intl-chinese

if [[ "$TARGET" == "gnome-full" ||  "$TARGET" == "xfce-full" ]]; then
    apt purge ibus firefox -y

    echo -e "\033[47;36m Install English fonts.................... \033[0m"
    ${APT_INSTALL} language-pack-en-base gnome-user-docs-en language-pack-gnome-en

    # set default xinput for fcitx
    ${APT_INSTALL} fcitx fcitx-table fcitx-googlepinyin fcitx-pinyin fcitx-config-gtk
    sed -i 's/default/fcitx/g' /etc/X11/xinit/xinputrc

    ${APT_INSTALL} ipython3 jupyter

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

    ${APT_INSTALL} $(check-language-support)
fi

if [[ "$TARGET" == "gnome" || "$TARGET" == "gnome-full" ]]; then
    ${APT_INSTALL} mpv acpid gnome-sound-recorder
elif [[ "$TARGET" == "xfce" || "$TARGET" == "xfce-full" ]]; then
    ${APT_INSTALL} mpv acpid gnome-sound-recorder
elif [ "$TARGET" == "lite" ]; then
    ${APT_INSTALL}  
fi

pip3 install python-periphery Adafruit-Blinka -i https://mirrors.aliyun.com/pypi/simple/

HOST=ubuntu-22.04.5

# Create user
useradd -G sudo -m -s /bin/bash linaro
echo "linaro:linaro" | chpasswd
gpasswd -a linaro video
gpasswd -a linaro audio
echo "root:linaro" | chpasswd

# allow root login
sed -i '/pam_securetty.so/s/^/# /g' /etc/pam.d/login

# hostname
echo Rockchip > /etc/hostname
cat > /etc/hosts <<'HOSTS_EOF'
127.0.0.1 localhost
127.0.1.1 Rockchip

::1 localhost ip6-localhost ip6-loopback
ff02::1 ip6-allnodes
ff02::2 ip6-allrouters
HOSTS_EOF

# set localtime
ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime

# workaround 90s delay
services=(NetworkManager systemd-networkd)
for service in ${services[@]}; do
  systemctl mask ${service}-wait-online.service
done

if [[ "$TARGET" == "gnome" || "$TARGET" == "gnome-full" || "$TARGET" == "xfce" || "$TARGET" == "xfce-full" ]]; then
  systemctl set-default graphical.target
fi

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

./ch-mount.sh -u "$TARGET_ROOTFS_DIR"
trap - INT TERM EXIT ERR

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
