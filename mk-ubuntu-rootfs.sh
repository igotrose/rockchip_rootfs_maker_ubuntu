#!/bin/bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SDK_TOP_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
KERNEL_DEB_DIR="$SDK_TOP_DIR/output/bsp-debs"

# Directory contains the target rootfs
TARGET_ROOTFS_DIR="binary"

if [ -z "${SOC:-}" ]; then
    echo "---------------------------------------------------------"
    echo "Please enter soc number:"
    echo "Please enter the number of the CPU to build:"
    echo "[0] Exit Menu"
    echo "[1] rk3128"
    echo "[2] rk3528"
    echo "[3] rk3562"
    echo "[4] rk3566/rk3568"
    echo "[5] rk3588/rk3588s"
    echo "---------------------------------------------------------"
    read input

    case $input in
        0)
            exit;;
        1)
            SOC=rk3128
            ;;
        2)
            SOC=rk3528
            ;;
        3)
            SOC=rk3562
            ;;
        4)
            SOC=rk356x
            ;;
        5)
            SOC=rk3588
            ;;
        *)
            echo 'input soc number error, exit !'
            exit;;
    esac
    echo -e "\033[47;36m set SOC=$SOC...... \033[0m"
fi

if [ -z "${TARGET:-}" ]; then
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

install_packages() {
    case $SOC in
        rk3399|rk3399pro)
        MALI=midgard-t86x-r18p0
        ISP=rkisp
        ;;
        rk3328|rk3528)
        MALI=utgard-450
        ISP=rkisp
        ;;
        rk3128|rk3036)
        MALI=utgard-400
        ISP=rkisp
        ;;
        rk3562)
        MALI=bifrost-g52-g13p0
        ISP=rkaiq_rk3562
        ;;
        rk356x|rk3566|rk3568)
        MALI=bifrost-g52-g13p0
        ISP=rkaiq_rk3568
        ;;
        rk3588|rk3588s)
        ISP=rkaiq_rk3588
        MALI=valhall-g610-g13p0
        ;;
    esac
}

case "${ARCH:-${1:-}}" in
    arm|arm32|armhf)
        ARCH=armhf
        ;;
    *)
        ARCH=arm64
        ;;
esac

echo -e "\033[47;36m Building for $ARCH \033[0m"

if [ -z "${VERSION:-}" ]; then
    VERSION="release"
fi

echo -e "\033[47;36m Building for $VERSION \033[0m"

shopt -s nullglob
BASE_ROOTFS_FILES=(ubuntu-base-"$TARGET"-$ARCH-*.tar.gz)
shopt -u nullglob

if [ "${#BASE_ROOTFS_FILES[@]}" -eq 0 ]; then
    echo "\033[41;36m Run mk-base-ubuntu.sh first \033[0m"
    exit -1
fi

mapfile -t BASE_ROOTFS_FILES < <(printf '%s\n' "${BASE_ROOTFS_FILES[@]}" | sort -V)
BASE_ROOTFS="${BASE_ROOTFS_FILES[-1]}"
echo -e "\033[47;36m Using base rootfs: $BASE_ROOTFS \033[0m"

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

echo -e "\033[47;36m Extract image \033[0m"
EXTRACT_ROOT="${TARGET_ROOTFS_DIR}.extract.$$"
sudo rm -rf "$EXTRACT_ROOT"
sudo mkdir -p "$EXTRACT_ROOT"
sudo tar -xpf "$BASE_ROOTFS" -C "$EXTRACT_ROOT"
if [ ! -d "$EXTRACT_ROOT/$TARGET_ROOTFS_DIR" ]; then
    echo "ERROR: $BASE_ROOTFS does not contain $TARGET_ROOTFS_DIR/"
    sudo rm -rf "$EXTRACT_ROOT"
    exit 1
fi
sudo rm -rf "$TARGET_ROOTFS_DIR"
sudo mv "$EXTRACT_ROOT/$TARGET_ROOTFS_DIR" "$TARGET_ROOTFS_DIR"
sudo rm -rf "$EXTRACT_ROOT"

# packages folder
sudo mkdir -p $TARGET_ROOTFS_DIR/packages
sudo cp -rpf packages/$ARCH/* $TARGET_ROOTFS_DIR/packages
if [ -d "packages/soc/$SOC" ]; then
    sudo cp -rpfv packages/soc/$SOC/* "$TARGET_ROOTFS_DIR/packages"
fi

#GPU/CAMERA packages folder
install_packages
sudo mkdir -p $TARGET_ROOTFS_DIR/packages/install_packages
sudo cp -rpf packages/$ARCH/libmali/libmali-*$MALI*-x11*.deb $TARGET_ROOTFS_DIR/packages/install_packages
sudo cp -rpf packages/$ARCH/${ISP:0:5}/camera_engine_$ISP*.deb $TARGET_ROOTFS_DIR/packages/install_packages

# linux kernel debs
KERNEL_INSTALL_DEBS=()
shopt -s nullglob
for pkg in ../linux-image-*.deb ../linux-headers-*.deb; do
    case "$pkg" in
        *-dbg_*.deb) continue ;;
    esac
    KERNEL_INSTALL_DEBS+=("$pkg")
done
if [ -d "$KERNEL_DEB_DIR" ]; then
    for pkg in "$KERNEL_DEB_DIR"/linux-image-*.deb "$KERNEL_DEB_DIR"/linux-headers-*.deb; do
        case "$pkg" in
            *-dbg_*.deb) continue ;;
        esac
        KERNEL_INSTALL_DEBS+=("$pkg")
    done
fi
shopt -u nullglob

if [ "${#KERNEL_INSTALL_DEBS[@]}" -gt 0 ]; then
    sudo mkdir -p "$TARGET_ROOTFS_DIR/boot/kerneldeb"
    sudo touch "$TARGET_ROOTFS_DIR/boot/build-host"
    sudo cp -av "${KERNEL_INSTALL_DEBS[@]}" "$TARGET_ROOTFS_DIR/boot/kerneldeb/"
fi

if [ -d "$KERNEL_DEB_DIR" ]; then
    shopt -s nullglob
    KERNEL_BSP_DEBS=("$KERNEL_DEB_DIR"/linux-*.deb)
    shopt -u nullglob
    if [ "${#KERNEL_BSP_DEBS[@]}" -gt 0 ]; then
        sudo mkdir -p "$TARGET_ROOTFS_DIR/home/linaro/bsp-debs"
        sudo cp -av "${KERNEL_BSP_DEBS[@]}" "$TARGET_ROOTFS_DIR/home/linaro/bsp-debs/"
    fi
fi

# overlay folder
sudo cp -rpf overlay/* $TARGET_ROOTFS_DIR/

# overlay-firmware folder
sudo cp -rpf overlay-firmware/* $TARGET_ROOTFS_DIR/

# overlay-debug folder
# adb, video, camera  test file
if [ "$VERSION" == "debug" ]; then
    sudo cp -rpf overlay-debug/* $TARGET_ROOTFS_DIR/
fi

## hack the serial
sudo cp -f overlay/usr/lib/systemd/system/serial-getty@.service $TARGET_ROOTFS_DIR/lib/systemd/system/serial-getty@.service

echo -e "\033[47;36m Change root.....................\033[0m"
if [ "$ARCH" == "armhf" ]; then
    sudo cp /usr/bin/qemu-arm-static $TARGET_ROOTFS_DIR/usr/bin/
elif [ "$ARCH" == "arm64"  ]; then
    sudo cp /usr/bin/qemu-aarch64-static $TARGET_ROOTFS_DIR/usr/bin/
fi

./ch-mount.sh -u "$TARGET_ROOTFS_DIR" >/dev/null 2>&1 || true
sudo rm -f "$TARGET_ROOTFS_DIR/etc/resolv.conf"
sudo cp -Lf /etc/resolv.conf "$TARGET_ROOTFS_DIR/etc/resolv.conf"
./ch-mount.sh -m "$TARGET_ROOTFS_DIR"

ID=$(stat --format %u $TARGET_ROOTFS_DIR)

cat > "$TARGET_ROOTFS_DIR/tmp/mk-ubuntu-rootfs-chroot.sh" <<EOF

# Fixup owners
if [ "$ID" -ne 0 ]; then
    find / -user $ID -exec chown -h 0:0 {} \;
fi
for u in \$(ls /home/); do
    chown -h -R \$u:\$u /home/\$u
done

export LC_ALL=C.UTF-8

# Ensure DNS works inside chroot
mkdir -p /etc
echo "nameserver 8.8.8.8" > /etc/resolv.conf
echo "nameserver 1.1.1.1" >> /etc/resolv.conf
cat > /etc/hosts <<'HOSTS_EOF'
127.0.0.1 localhost
127.0.1.1 Rockchip

::1 localhost ip6-localhost ip6-loopback
ff02::1 ip6-allnodes
ff02::2 ip6-allrouters
HOSTS_EOF

# Make sure the APT directory exists.
mkdir -p /var/cache/apt/archives/partial
mkdir -p /var/lib/apt/lists/partial

apt-get update
apt-get upgrade -y

# Headless ToB images do not need doc-base; removing it also avoids
# non-fatal trigger errors from packages that ship broken doc registrations.
dpkg -l | grep -q "^ii  doc-base " && apt purge -y doc-base || true

chmod o+x /usr/lib/dbus-1.0/dbus-daemon-launch-helper
[ -e /etc/rc.local ] && chmod +x /etc/rc.local || true

export DEBIAN_FRONTEND=noninteractive
export APT_INSTALL="apt-get install -fy --allow-downgrades -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold"

# Install systemd tools and basic system utilities
\${APT_INSTALL} systemd systemd-sysv util-linux sysvinit-utils
\${APT_INSTALL} android-tools-adbd

# Enable Rockchip specific services
systemctl enable usbdevice
systemctl enable automount
systemctl enable resize-all
systemctl enable ssh
systemctl enable rockchip
systemctl enable async

# Ensure systemd is properly configured
systemctl set-default multi-user.target
systemctl enable systemd-networkd
systemctl enable systemd-resolved
systemctl enable quectel

mkdir -p /etc/init.d
echo usb_adb_en > /etc/init.d/.usb_config

# Safely remove initramfs-tools (if it exists)
dpkg -l | grep -q initramfs-tools && apt purge initramfs-tools -y || echo "initramfs-tools not installed, skipping removal"

\${APT_INSTALL} u-boot-tools edid-decode logrotate
if [[ "$TARGET" == "gnome" || "$TARGET" == "gnome-full" ]]; then
    \${APT_INSTALL} gdisk
elif [[ "$TARGET" == "xfce" || "$TARGET" == "xfce-full" ]]; then
    apt-get remove -y gnome-bluetooth
    \${APT_INSTALL} bluez bluez-tools
elif [ "$TARGET" == "lite" ]; then
    \${APT_INSTALL} bluez bluez-tools
fi
\${APT_INSTALL} /packages/install_packages/*.deb

\${APT_INSTALL} /boot/kerneldeb/* || true
\${APT_INSTALL} dkms build-essential kmod pkg-config python3 python-is-python3 python3-dev python3-venv \
    python3-setuptools python3-wheel libncurses5 libtinfo5 libatomic1
\${APT_INSTALL} lsb-release
\${APT_INSTALL} lsb-core || true

echo -e "\033[47;36m ----- power management ----- \033[0m"
\${APT_INSTALL} pm-utils triggerhappy bsdmainutils
cp /etc/Powermanager/triggerhappy.service  /lib/systemd/system/triggerhappy.service
sed -i "s/#HandlePowerKey=.*/HandlePowerKey=ignore/" /etc/systemd/logind.conf

echo -e "\033[47;36m ----------- RGA  ----------- \033[0m"
\${APT_INSTALL} /packages/rga2/*.deb

if [[ "$TARGET" == "gnome" ||  "$TARGET" == "xfce" || "$TARGET" == "gnome-full" || "$TARGET" == "xfce-full" ]]; then
    echo -e "\033[47;36m ------ Setup Video---------- \033[0m"
    \${APT_INSTALL} gstreamer1.0-plugins-bad gstreamer1.0-plugins-base gstreamer1.0-tools gstreamer1.0-alsa \
    gstreamer1.0-plugins-base-apps qtmultimedia5-examples

    \${APT_INSTALL} /packages/mpp/*
    \${APT_INSTALL} /packages/gst-rkmpp/*.deb
    \${APT_INSTALL} /packages/gstreamer/*.deb
elif [ "$TARGET" == "lite" ]; then
    echo -e "\033[47;36m ------ Setup Video---------- \033[0m"
    \${APT_INSTALL} /packages/mpp/*
    \${APT_INSTALL} /packages/gst-rkmpp/*.deb
fi

if [[ "$TARGET" == "gnome" ||  "$TARGET" == "xfce" || "$TARGET" == "gnome-full" || "$TARGET" == "xfce-full" ]]; then
    echo -e "\033[47;36m ----- Install Camera ----- - \033[0m"
    \${APT_INSTALL} cheese v4l-utils
    \${APT_INSTALL} /packages/libv4l/*.deb
elif [ "$TARGET" == "lite" ]; then
    echo -e "\033[47;36m ----- Install Camera ----- - \033[0m"
    \${APT_INSTALL} v4l-utils
fi

if [[ "$TARGET" == "gnome" || "$TARGET" == "gnome-full" ]]; then
    echo -e "\033[47;36m ----- Install Xserver------- \033[0m"
    \${APT_INSTALL} /packages/xserver/xserver-xorg-*.deb
    apt-mark hold xserver-xorg-core xserver-xorg-legacy
    echo -e "\033[47;36m ----- Install Display Manager and Session Manager ----- \033[0m"
    \${APT_INSTALL} gdm3 gnome-session
elif [[ "$TARGET" == "xfce" || "$TARGET" == "xfce-full" ]]; then
    echo -e "\033[47;36m ----- Install Xserver------- \033[0m"
    \${APT_INSTALL} /packages/xserver/*.deb
    apt-mark hold xserver-common xserver-xorg-core xserver-xorg-legacy
fi

if [[ "$TARGET" == "gnome" || "$TARGET" == "gnome-full" ]]; then
    # Enable GNOME Display Manager
    systemctl enable gdm3
    
    # Enable additional desktop services
    systemctl enable accounts-daemon || echo "accounts-daemon not available"
    systemctl enable bluetooth || echo "bluetooth not available"
    systemctl enable cups || echo "cups not available"
    
    # Enable graphical target as default
    systemctl set-default graphical.target
fi

if [[ "$TARGET" == "xfce" || "$TARGET" == "xfce-full" ]]; then
    # Enable LightDM for XFCE desktop
    systemctl enable lightdm || echo "lightdm not available"
    systemctl set-default graphical.target
fi

if [[ "$TARGET" == "gnome" ||  "$TARGET" == "xfce" || "$TARGET" == "gnome-full" || "$TARGET" == "xfce-full" ]]; then
    echo -e "\033[47;36m ------ update chromium ----- \033[0m"
    \${APT_INSTALL} /packages/chromium/*.deb
fi

if [[ "$TARGET" == "gnome" || "$TARGET" == "gnome-full" || "$TARGET" == "xfce" || "$TARGET" == "xfce-full" ]]; then
    echo -e "\033[47;36m ----- Install USB Host Support ----- \033[0m"
    \${APT_INSTALL} udisks2 gvfs gvfs-fuse gvfs-backends
fi

echo -e "\033[47;36m ------- Install libdrm ------ \033[0m"
\${APT_INSTALL} /packages/libdrm/*.deb

if [[ "$TARGET" == "gnome" ||  "$TARGET" == "xfce" || "$TARGET" == "gnome-full" || "$TARGET" == "xfce-full" ]]; then
    echo -e "\033[47;36m ------ libdrm-cursor -------- \033[0m"
    \${APT_INSTALL} /packages/libdrm-cursor/*.deb
fi

if [[ "$TARGET" == "gnome" ||  "$TARGET" == "xfce" || "$TARGET" == "gnome-full" || "$TARGET" == "xfce-full" ]]; then
    if [ "$VERSION" == "debug" ]; then
        echo -e "\033[47;36m ------ Install glmark2 ------ \033[0m"
        \${APT_INSTALL} glmark2-es2
    fi
fi

if [ -e "/usr/lib/aarch64-linux-gnu" ] ; then
echo -e "\033[47;36m ------- move rknpu2 --------- \033[0m"
mv /packages/rknpu2/*.tar  /
fi

echo -e "\033[47;36m ----- Install rktoolkit ----- \033[0m"
\${APT_INSTALL} /packages/rktoolkit/*.deb

if [[ "$TARGET" == "gnome" ||  "$TARGET" == "xfce" || "$TARGET" == "gnome-full" || "$TARGET" == "xfce-full" ]]; then
    echo -e "\033[47;36m ------ Install ffmpeg ------- \033[0m"
    \${APT_INSTALL} ffmpeg
fi

if [[ "$TARGET" == "gnome" ||  "$TARGET" == "xfce" || "$TARGET" == "gnome-full" || "$TARGET" == "xfce-full" ]]; then
    echo -e "\033[47;36m ------- Install mpv --------- \033[0m"
    apt-get -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" install -y /packages/mpv/*.deb
fi

apt autoremove -y
ldconfig || true

# mark package to hold
apt list --upgradable | cut -d/ -f1 | xargs apt-mark hold

echo -e "\033[47;36m ------- Custom Script ------- \033[0m"
systemctl mask systemd-networkd-wait-online.service
systemctl mask NetworkManager-wait-online.service
systemctl disable hostapd 2>/dev/null || true
rm -f /lib/systemd/system/wpa_supplicant@.service

echo -e "\033[47;36m  ---------- Clean ----------- \033[0m"
# Ensure that the necessary directories exist
mkdir -p /var/cache/apt/archives/partial
mkdir -p /var/lib/apt/lists/partial

# A safer cleaning method
if [ -d /var/lib/apt/lists ]; then
    find /var/lib/apt/lists/* -mindepth 1 -not -name "lock" -not -name "partial" -delete 2>/dev/null || true
fi

if [ -d /var/cache ]; then
    find /var/cache/* -mindepth 1 -not -name "ldconfig" -not -name "ldconfig/*" -not -name "apt" -not -name "apt/*" -delete 2>/dev/null || true
fi

# Clean up the "packages" and "boot" directories
rm -rf /packages/
find /boot/* -mindepth 1 -not -name "build-host" -delete 2>/dev/null || true

if [ -e "/usr/lib/arm-linux-gnueabihf/dri" ] ; then
        # Only preload libdrm-cursor for X
        sed -i "1aexport LD_PRELOAD=/usr/lib/arm-linux-gnueabihf/libdrm-cursor.so.1" /usr/bin/X
        cd /usr/lib/arm-linux-gnueabihf/dri/
        cp kms_swrast_dri.so swrast_dri.so rockchip_dri.so /
        rm /usr/lib/arm-linux-gnueabihf/dri/*.so
        mv /*.so /usr/lib/arm-linux-gnueabihf/dri/
elif [ -e "/usr/lib/aarch64-linux-gnu/dri" ]; then
        # Only preload libdrm-cursor for X
        sed -i "1aexport LD_PRELOAD=/usr/lib/aarch64-linux-gnu/libdrm-cursor.so.1" /usr/bin/X
        cd /usr/lib/aarch64-linux-gnu/dri/
        cp kms_swrast_dri.so swrast_dri.so rockchip_dri.so /
        rm /usr/lib/aarch64-linux-gnu/dri/*.so
        mv /*.so /usr/lib/aarch64-linux-gnu/dri/
fi

EOF

sudo chmod +x "$TARGET_ROOTFS_DIR/tmp/mk-ubuntu-rootfs-chroot.sh"
sudo chroot "$TARGET_ROOTFS_DIR" /bin/bash /tmp/mk-ubuntu-rootfs-chroot.sh
sudo rm -f "$TARGET_ROOTFS_DIR/tmp/mk-ubuntu-rootfs-chroot.sh"
./ch-mount.sh -u "$TARGET_ROOTFS_DIR"
trap - INT TERM EXIT ERR

source ./mk-image.sh
