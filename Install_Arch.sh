#!/bin/bash
# WARNING: this script will destroy data on the selected disk.
# This script can be run by executing the following:
#   curl -sL https://git.io/vAoV8 | bash
# https://goo.su/lwsz
set -uo pipefail
trap 's=$?; echo "$0: Error on line "$LINENO": $BASH_COMMAND"; exit $s' ERR

REPO_URL="https://s3.eu-west-2.amazonaws.com/mdaffin-arch/repo/x86_64"
MIRRORLIST_URL="https://archlinux.org/mirrorlist/?country=GB&protocol=https&use_mirror_status=on"

pacman -Sy --noconfirm pacman-contrib dialog

echo "Updating mirror list"
curl -s "$MIRRORLIST_URL" | \
    sed -e 's/^#Server/Server/' -e '/^#/d' | \
    rankmirrors -n 5 - > /etc/pacman.d/mirrorlist

### Get infomation from user ###
hostname=$(dialog --stdout --inputbox "Enter hostname" 0 0) || exit 1
clear
: ${hostname:?"hostname cannot be empty"}

user=$(dialog --stdout --inputbox "Enter admin username" 0 0) || exit 1
clear
: ${user:?"user cannot be empty"}

password=$(dialog --stdout --passwordbox "Enter admin password" 0 0) || exit 1
clear
: ${password:?"password cannot be empty"}
password2=$(dialog --stdout --passwordbox "Enter admin password again" 0 0) || exit 1
clear
[[ "$password" == "$password2" ]] || ( echo "Passwords did not match"; exit 1; )

devicelist=$(lsblk -dplnx size -o name,size | grep -Ev "boot|rpmb|loop" | tac)
device=$(dialog --stdout --menu "Select installtion disk" 0 0 0 ${devicelist}) || exit 1
clear

### Set up logging ###
exec 1> >(tee "stdout.log")
exec 2> >(tee "stderr.log")

timedatectl set-ntp true

### Setup the disk and partitions ### 

parted --script "${device}" -- mklabel gpt \
  mkpart ESP fat32 1Mib 512MiB \
  set 1 boot on \
  mkpart primary btrfs 100%

# Simple globbing was not enough as on one device I needed to match /dev/mmcblk0p1 
# but not /dev/mmcblk0boot1 while being able to match /dev/sda1 on other devices.
part_boot="$(ls ${device}* | grep -E "^${device}p?1$")"
part_root="$(ls ${device}* | grep -E "^${device}p?2$")"

wipefs "${part_boot}"
wipefs "${part_root}"

mkfs.vfat -F32 "${part_boot}"
mkfs.btrfs -f "${part_root}"

mkfs.vfat -F32 "${part_boot}"
mkfs.btrfs -f "${part_root}"

mount "${part_root}" /mnt
btrfs su cr /mnt/@
btrfs su cr /mnt/@home
btrfs su cr /mnt/@var
btrfs su cr /mnt/@tmp
btrfs su cr /mnt/@snapshots
umount /mnt

mount -o noatime,compress=zstd:2,space_cache=v2,discard=async,subvol=@ "${part_root}" /mnt
mount -o noatime,compress=zstd:2,space_cache=v2,discard=async,subvol=@home "${part_root}" /mnt/home
mount -o noatime,compress=zstd:2,space_cache=v2,discard=async,subvol=@var "${part_root}" /mnt/var
mount -o noatime,compress=zstd:2,space_cache=v2,discard=async,subvol=@tmp "${part_root}" /mnt/tmp
mount -o noatime,compress=zstd:2,space_cache=v2,discard=async,subvol=@snapshots "${part_root}" /mnt/.snapshots

mount "${part_boot}" /mnt/boot/efi

pacstrap /mnt base base-devel linux \
linux-firmware vim btrfs-progs \
networkmanager network-manager-applet \
grub grub-btrfs efibootmgr linux-headers \
reflector rsync mtools net-tools os-prober dosfstools \
git snapper xdg-user-dirs
