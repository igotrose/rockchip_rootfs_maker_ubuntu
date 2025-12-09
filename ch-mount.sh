#!/bin/bash

function mnt() {
    echo "MOUNTING"
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
    
    # Check if /dev is already mounted
    if ! mountpoint -q ${2}/dev; then
        sudo mount -o bind /dev ${2}/dev
    else
        echo "/dev already mounted"
    fi
    
    # Check if /dev/pts is already mounted
    if ! mountpoint -q ${2}/dev/pts; then
        sudo mount -t devpts devpts ${2}/dev/pts
    else
        echo "/dev/pts already mounted"
    fi
}

function umnt() {
    echo "UNMOUNTING"
    # Check if /dev/pts is mounted before unmounting
    if mountpoint -q ${2}/dev/pts; then
        sudo umount ${2}/dev/pts
    else
        echo "/dev/pts not mounted"
    fi
    
    # Check if /proc is mounted before unmounting
    if mountpoint -q ${2}/proc; then
        sudo umount ${2}/proc
    else
        echo "/proc not mounted"
    fi
    
    # Check if /sys is mounted before unmounting
    if mountpoint -q ${2}/sys; then
        sudo umount ${2}/sys
    else
        echo "/sys not mounted"
    fi
    
    # Check if /dev is mounted before unmounting
    if mountpoint -q ${2}/dev; then
        sudo umount ${2}/dev
    else
        echo "/dev not mounted"
    fi
}

if [ "$1" == "-m" ] && [ -n "$2" ] ;
then
    mnt $1 $2
elif [ "$1" == "-u" ] && [ -n "$2" ];
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
    echo 1st parameter : ${1}
    echo 2nd parameter : ${2}
fi