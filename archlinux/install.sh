#!/bin/bash

# Usage
# --------
# curl -O https://georg9741.github.io/archlinux/install.sh
# chmod +x install.sh
# ./install.sh

clear

# Temporary
echo
echo "current criterias for this script to be functional: uefi mode, harddrive name: sda, cpu: intel, graphics: intel"
echo
read -p "Press enter to continue"
clear

# Exit on error
set -euo pipefail

# Variabled
DISK="/dev/sda"
EFI_PART="${DISK}1"
BOOT_PART="${DISK}2"
LUKS_PART="${DISK}3"
LUKS_NAME="luks_lvm"
VG_NAME="arch"

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Functions
info() {
  echo -e "${GREEN}[INFO] $1${NC}"
}

# Menu
#function showMenu () {
#        echo "1) Set crypt password"
#        echo "2) Set root password"
#        echo "3) Set user password"
#        echo "4) Quit"
#}
#while [ 1 ]
#  do
#    showMenu
#    read CHOICE
#    case "$CHOICE" in
#      "1") ...
#      "2") ...
#      "3") ...
#      "4") exit 1
#      ;;
#    esac
#done

# Inputs
echo
while true; do
  read -s -p "Enter crypt password: " CRYPT_PASSWD
  echo; echo
  read -s -p "Enter crypt password (again): " CRYPT_PASSWD2
  [ "$CRYPT_PASSWD" = "$CRYPT_PASSWD2" ] && break
  echo; echo
  echo "Passwords do not match. Try again."
done
clear
while true; do
  read -s -p "Enter root password: " ROOT_PASSWD
  echo; echo
  read -s -p "Enter root password (again): " ROOT_PASSWD2
  [ "$ROOT_PASSWD" = "$ROOT_PASSWD2" ] && break
  echo; echo
  echo "Passwords do not match. Try again."
done
clear
while true; do
  read -s -p "Enter user password: " USER_PASSWD
  echo; echo
  read -s -p "Enter user password (again): " USER_PASSWD2
  [ "$USER_PASSWD" = "$USER_PASSWD2" ] && break
  echo; echo
  echo "Passwords do not match. Try again."
done

# Partitioning
echo
info "Partitioning"
wipefs -a $DISK*
gdisk $DISK <<EOF
o
Y
n


+256M
ef00
n


+512M
ef02
n



8309
w
Y
EOF
info "Partitioning finished"

# Format partitions
echo
info "Format partitions"
mkfs.fat -F32 $EFI_PART
mkfs.ext4 $BOOT_PART
echo -n "$CRYPT_PASSWD" | cryptsetup -q luksFormat $LUKS_PART
echo -n "$CRYPT_PASSWD" | cryptsetup open $LUKS_PART $LUKS_NAME
info "Partitions formatted"

# LVM Setup
echo
RAM_SIZE=$(grep MemTotal /proc/meminfo | awk '{print $2}') # in KB
SWAP_SIZE=$(( RAM_SIZE / 1024 / 1024 )) # Convert to GB

if [ $SWAP_SIZE -lt 8 ]; then
  SWAP_SIZE=8  # Set a minimum swap of 8GB
elif [ $SWAP_SIZE -gt 32 ]; then
  SWAP_SIZE=32 # Cap swap at 32GB
fi

info "LVM Setup"
pvcreate /dev/mapper/$LUKS_NAME
vgcreate $VG_NAME /dev/mapper/$LUKS_NAME
lvcreate $VG_NAME -n swap -L "${SWAP_SIZE}G" -C y
lvcreate $VG_NAME -n root -L 64GB
lvcreate $VG_NAME -n home -l +100%FREE
info "LVM Setup finished"

# Format LVM partitions
echo
info "Format LVM partitions"
mkswap /dev/mapper/${VG_NAME}-swap
mkfs.ext4 /dev/mapper/${VG_NAME}-root -L root
mkfs.ext4 /dev/mapper/${VG_NAME}-home -L home
info "LVM partitions formatted"

# Mount filesystems
echo
info "Mount filesystems"
mount /dev/mapper/${VG_NAME}-root /mnt
mount /dev/mapper/${VG_NAME}-home /mnt/home --mkdir
mount $BOOT_PART /mnt/boot --mkdir
mount $EFI_PART /mnt/boot/efi --mkdir
swapon /dev/mapper/${VG_NAME}-swap
info "Filesystems mounted"

# Generate mirror list
echo
info "Generate mirror list"
reflector -l 10 -p https -c DE --sort rate --save /etc/pacman.d/mirrorlist
info "Mirror list generated"

# Install base system
echo
info "Install packages"
PACKAGES='base linux linux-headers linux-firmware base-devel efibootmgr git grub lvm2 nano networkmanager os-prober linux-zen linux-zen-headers intel-ucode plasma openssh kitty fastfetch mesa intel-media-driver'
pacstrap -K /mnt $PACKAGES
# Selection extra kernels: pacstrap -K /mnt linux-zen linux-zen-headers | pacstrap -K /mnt linux-lts linux-lts-headers
# Selection microcode: pacstrap -K /mnt amd-ucode | pacstrap -K /mnt intel-ucode (lscpu, automatic with vendor id)
info "Packages installed"

# Generate fstab
echo
info "Generate fstab"
genfstab -U /mnt >> /mnt/etc/fstab
info "fstab generated"

# Enter chroot
echo
info "Enter chroot"
arch-chroot /mnt /bin/bash -c 'ln -sf /usr/share/zoneinfo/Europe/Berlin /etc/localtime
sed -i "s/#de_DE.UTF-8 UTF-8/de_DE.UTF-8 UTF-8/;s/#en_GB.UTF-8 UTF-8/en_GB.UTF-8 UTF-8/;s/#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/" /etc/locale.gen
locale-gen
echo "LANG=en_GB.UTF-8" > /etc/locale.conf
echo "KEYMAP=de" > /etc/vconsole.conf
localectl set-x11-keymap de
echo "i-use-arch-btw" > /etc/hostname
useradd -m -G wheel georg
echo "root:'$ROOT_PASSWD'" | chpasswd
echo "georg:'$USER_PASSWD'" | chpasswd
sed -i "s|^# Cmnd_Alias\tREBOOT =.*|Cmnd_Alias\tREBOOT = /sbin/halt, /sbin/reboot, /sbin/poweroff, /sbin/shutdown|;s|# %wheel ALL=(ALL:ALL) ALL|%wheel ALL=(ALL:ALL) ALL, NOPASSWD: REBOOT|" /etc/sudoers
sed -i "s|^HOOKS=.*|HOOKS=(base udev autodetect microcode modconf kms keyboard keymap consolefont block encrypt lvm2 filesystems fsck)|" /etc/mkinitcpio.conf
mkinitcpio -P
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB
sed -i "s|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT=\"loglevel=3 root=/dev/mapper/'$VG_NAME'-root cryptdevice='$LUKS_PART':'$LUKS_NAME' quiet\"|" /etc/default/grub
grub-mkconfig -o /boot/grub/grub.cfg
systemctl enable NetworkManager
systemctl enable sddm
systemctl enable sshd'
info "Exit chroot"
echo "Continuing in 10 seconds..."
sleep 10
clear

# Result screen
echo
echo "[Partitioning]"
sda1size=$(($(blockdev --getsize64 $EFI_PART)/1048576))
sda2size=$(($(blockdev --getsize64 $BOOT_PART)/1048576))
sda3size=$(($(blockdev --getsize64 $LUKS_PART)/1073741824))
echo "sda1: EFI system partition (${sda1size}MB)"
echo "sda2: BIOS boot partition (${sda2size}MB)"
echo "sda3: Linux LUKS (${sda3size}GB)"
echo
echo "[Partitions formatted]"
echo "sda1: fat"
echo "sda2: ext4"
echo "sda3: luks"
echo
echo "[LVM Setup]"
sdahomesize=$(($(blockdev --getsize64 $DISK)/1073741824-100663296))
echo "swap: 32GB"
echo "root: 64GB"
echo "home: ${sdahomesize}GB"
echo
echo "[Chroot]"
echo "root password set"
echo "user georg created"
echo "user added to group wheel"
echo "installed stuff"
echo "configured stuff"
echo "Continuing in 10 seconds..."
sleep 10
clear

# Unmount and reboot
umount -R /mnt
swapoff -a
read -p "Press enter to reboot"
reboot
