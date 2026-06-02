#!/bin/bash

set -euo pipefail

create_dev_nodes() {
    local root="$1"

    sudo mkdir -p "$root/dev/pts" "$root/dev/shm"

    [ -e "$root/dev/null" ] || sudo mknod -m 666 "$root/dev/null" c 1 3
    [ -e "$root/dev/zero" ] || sudo mknod -m 666 "$root/dev/zero" c 1 5
    [ -e "$root/dev/full" ] || sudo mknod -m 666 "$root/dev/full" c 1 7
    [ -e "$root/dev/random" ] || sudo mknod -m 666 "$root/dev/random" c 1 8
    [ -e "$root/dev/urandom" ] || sudo mknod -m 666 "$root/dev/urandom" c 1 9
    [ -e "$root/dev/tty" ] || sudo mknod -m 666 "$root/dev/tty" c 5 0
    [ -e "$root/dev/console" ] || sudo mknod -m 600 "$root/dev/console" c 5 1
    [ -e "$root/dev/ptmx" ] || sudo mknod -m 666 "$root/dev/ptmx" c 5 2
}
 
function mnt() {
    echo "MOUNTING"
    sudo mkdir -p "${2}/proc" "${2}/sys" "${2}/dev" "${2}/run"
    
    # Check if /proc is already mounted
    if ! mountpoint -q ${2}/proc; then
        sudo mount -t proc /proc ${2}/proc
    else
        echo "/proc already mounted"
    fi
    
    # Check if /sys is already mounted
    if ! mountpoint -q ${2}/sys; then
        sudo mount -t sysfs /sys ${2}/sys
    else
        echo "/sys already mounted"
    fi
    
    # Create an isolated /dev for chroot so host /dev cannot be modified
    if ! mountpoint -q ${2}/dev; then
        sudo mount -t tmpfs -o mode=755,nosuid tmpfs ${2}/dev
        create_dev_nodes "${2}"
    else
        echo "/dev already mounted"
    fi
    
    # Check if /dev/pts is already mounted
    if ! mountpoint -q ${2}/dev/pts; then
        sudo mount -t devpts devpts ${2}/dev/pts
    else
        echo "/dev/pts already mounted"
    fi
    
    # Check if /run is already mounted
    if ! mountpoint -q ${2}/run; then
        sudo mount -o bind /run ${2}/run
    else
        echo "/run already mounted"
    fi
}

function umnt() {
    echo "UNMOUNTING"
    
    # Check if /run is mounted before unmounting (unmount first as it's mounted last)
    if mountpoint -q ${2}/run; then
        sudo umount -lf ${2}/run 2>/dev/null || sudo umount ${2}/run
    else
        echo "/run not mounted"
    fi
    
    # Check if /dev/pts is mounted before unmounting
    if mountpoint -q ${2}/dev/pts; then
        sudo umount -lf ${2}/dev/pts 2>/dev/null || sudo umount ${2}/dev/pts
    else
        echo "/dev/pts not mounted"
    fi
    
    # Check if /dev is mounted before unmounting
    if mountpoint -q ${2}/dev; then
        sudo umount -lf ${2}/dev 2>/dev/null || sudo umount ${2}/dev
    else
        echo "/dev not mounted"
    fi
    
    # Check if /sys is mounted before unmounting
    if mountpoint -q ${2}/sys; then
        sudo umount -lf ${2}/sys 2>/dev/null || sudo umount ${2}/sys
    else
        echo "/sys not mounted"
    fi
    
    # Check if /proc is mounted before unmounting (unmount last as it's mounted first)
    if mountpoint -q ${2}/proc; then
        sudo umount -lf ${2}/proc 2>/dev/null || sudo umount ${2}/proc
    else
        echo "/proc not mounted"
    fi
}

if [ "${1:-}" == "-m" ] && [ -n "${2:-}" ] ;
then
    mnt $1 $2
elif [ "${1:-}" == "-u" ] && [ -n "${2:-}" ];
then
    umnt $1 $2
else
    echo ""
    echo "Either 1'st, 2'nd or both parameters were missing"
    echo ""
    echo "1'st parameter can be one of these: -m(mount) OR -u(umount)"
    echo "2'nd parameter is the full path of rootfs directory"
    echo ""
    echo "For example: ch-mount.sh -m /media/sdcard"
    echo ""
    echo 1st parameter : ${1:-}
    echo 2nd parameter : ${2:-}
fi