#https://goo.su/9C9F36g
set -uo pipefail
trap 's=$?; echo "$0: Error on line "$LINENO": $BASH_COMMAND"; exit $s' ERR

MIRRORLIST_URL="https://archlinux.org/mirrorlist/?country=RU&protocol=http&protocol=https&ip_version=4"

pacman -Sy --noconfirm pacman-contrib dialog

#echo "Обновление зеркал"
#curl -s "$MIRRORLIST_URL" | \
#    sed -e 's/^#Server/Server/' -e '/^#/d' | \
#    rankmirrors -n 5 - > /etc/pacman.d/mirrorlist

echo "Разбивка диска"
devicelist=$(lsblk -dplnx size -o name,size | grep -Ev "boot|rpmb|loop" | tac)
device=$(dialog --stdout --menu "Select installtion disk" 0 0 0 ${devicelist}) || exit 1
clear

parted --script "${device}" -- mklabel gpt \
  mkpart ESP fat32 1Mib 512MiB \
  set 1 boot on \
  mkpart primary btrfs 512 100%

part_boot="$(ls ${device}* | grep -E "^${device}p?1$")"
part_root="$(ls ${device}* | grep -E "^${device}p?2$")"

wipefs "${part_boot}"
wipefs "${part_root}"

echo "Форматирование"
mkfs.vfat -F32 "${part_boot}"
mkfs.btrfs -f "${part_root}"

echo "Создание подразделов"
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

echo "Установка"

pacstrap /mnt base base-devel linux-zen linux-firmware nano btrfs-progs networkmanager network-manager-applet grub grub-btrfs efibootmgr linux-headers reflector rsync mtools net-tools os-prober dosfstools git snapper xdg-user-dirs

echo "генерация fstab"
genfstab -t PARTUUID /mnt >> /mnt/etc/fstab

echo "chroot"
arch-chroot /mnt

echo "Установка часовой зоны и синхронизация часов"
ln -sf /usr/share/zoneinfo/Russia/Moscow /etc/localtime
hwclock --systohc UTC
timedatectl set-ntp true

echo "Локализация"
echo "LANG=ru_RU.UTF-8" > /mnt/etc/locale.conf

touch /etc/vconsole.conf
echo "KEYMAP=ru" > /etc/vconsole.conf
echo "FONT=cyr-sun16" > /etc/vconsole.conf
locale-gen

hostname=$(dialog --stdout --inputbox "Enter hostname" 0 0) || exit 1
clear
: ${hostname:?"hostname cannot be empty"}
echo "${hostname}" > /mnt/etc/hostname
echo 127.0.0.1  > /mnt/etc/hosts
echo 127.0.1.1  "${hostname}" > /mnt/etc/hosts

user=$(dialog --stdout --inputbox "Enter admin username" 0 0) || exit 1
clear
: ${user:?"user cannot be empty"}

password=$(dialog --stdout --passwordbox "Enter admin password" 0 0) || exit 1
clear
: ${password:?"password cannot be empty"}
password2=$(dialog --stdout --passwordbox "Enter admin password again" 0 0) || exit 1
clear
[[ "$password" == "$password2" ]] || ( echo "Passwords did not match"; exit 1; )



grub-install --target=x86_64-efi \
--efi-directory=/boot/efi \
--bootloader-id=GRUB

grub-mkconfig -o \
/boot/grub/grub.cfg

pacman -S xorg sddm plasma kde-applications firefox
systemctl enable sddm
systemctl enable NetworkManager

echo "FINISH ... and REBOOT"
