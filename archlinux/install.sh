#!/bin/bash

# Usage
# --------
# curl -O https://georg9741.github.io/archlinux/install.sh
# chmod +x install.sh
# ./install.sh

# Exit on error
set -euo pipefail

# Colors
GREEN="\033[0;32m"
RED="\033[0;31m"
NC="\033[0m" # No Color

# Functions
info() {
  echo; echo -e "${GREEN}[INFO] ${NC}$1"
}

# Info
clear
echo; echo -e "${GREEN}Requirments: ${NC}UEFI Mode"
echo; echo "Continuing in 3 seconds..."; sleep 3

# Inputs
## DISK NAME
clear
echo; echo "[SET DRIVE]"; echo
lsblk; echo
read -p "Enter drive name here: " DISK_NAME
## USERNAME
clear
echo; echo "[SET USERNAME]"; echo
read -p "Enter username here: " USERNAME

# Variables
DISK="/dev/${DISK_NAME}"
EFI_PART="${DISK}1"
EFI_SIZE="256M"
BOOT_PART="${DISK}2"
BOOT_SIZE="512M"
LUKS_PART="${DISK}3"
LUKS_NAME="luks_lvm"
VG_NAME="arch"
SWAP_LV="swap"
ROOT_LV="root"
ROOT_LV_SIZE="64G"
HOME_LV="home"

# Password Inputs
password_input() {
  local mismatch=0 title=$1 read_msg1=$2 read_msg2=$3 varname=$4 pass1 pass2
  while true; do
    clear; echo; echo "[$title]"; echo
    if (( mismatch )); then echo "Passwords do not match. Try again."; echo; fi
    read -s -p "Enter $read_msg1: " pass1
    clear; echo; echo "[$title]"; echo
    read -s -p "Verify $read_msg2: " pass2
    [[ "$pass1" == "$pass2" ]] && eval "$varname='$pass1'" && break
    mismatch=1
  done
}
password_input "USER PASSWORD" "user password for $USERNAME" "user password" USER_PASSWD
password_input "ROOT PASSWORD" "root password" "root password" ROOT_PASSWD
password_input "CRYPTSETUP" "passphrase for $LUKS_PART" "passphrase" CRYPT_PASSWD

# Partitioning
clear
info "Partitioning"
echo -e "o\ny\nn\n\n\n+$EFI_SIZE\nef00\nn\n\n\n+$BOOT_SIZE\nef02\nn\n\n\n\n8309\nw\ny" | gdisk $DISK
info "Partitioning finished"

# Format partitions
info "Format partitions"
mkfs.fat -F32 $EFI_PART
mkfs.ext4 $BOOT_PART
echo -n "$CRYPT_PASSWD" | cryptsetup -q luksFormat $LUKS_PART
echo -n "$CRYPT_PASSWD" | cryptsetup open $LUKS_PART $LUKS_NAME
info "Partitions formatted"

# LVM Setup
info "LVM Setup"
RAM_SIZE=$(grep MemTotal /proc/meminfo | awk '{print $2}') # in KB
SWAP_SIZE=$((RAM_SIZE/1024/1024)) # Convert to GB
if [ $SWAP_SIZE -lt 8 ]; then
  SWAP_SIZE=8  # Set a minimum swap of 8GB
elif [ $SWAP_SIZE -gt 32 ]; then
  SWAP_SIZE=32 # Cap swap at 32GB
fi
pvcreate /dev/mapper/$LUKS_NAME
vgcreate $VG_NAME /dev/mapper/$LUKS_NAME
lvcreate $VG_NAME -n $SWAP_LV -L ${SWAP_SIZE}G -C y
lvcreate $VG_NAME -n $ROOT_LV -L $ROOT_LV_SIZE
lvcreate $VG_NAME -n $HOME_LV -l +100%FREE
info "LVM Setup finished"

# Format LVM partitions
info "Format LVM partitions"
mkswap /dev/mapper/${VG_NAME}-$SWAP_LV
mkfs.ext4 /dev/mapper/${VG_NAME}-$ROOT_LV -L root
mkfs.ext4 /dev/mapper/${VG_NAME}-$HOME_LV -L home
info "LVM partitions formatted"

# Mount filesystems
info "Mount filesystems"
mount /dev/mapper/${VG_NAME}-$ROOT_LV /mnt
mount /dev/mapper/${VG_NAME}-$HOME_LV /mnt/home --mkdir
mount $BOOT_PART /mnt/boot --mkdir
mount $EFI_PART /mnt/boot/efi --mkdir
swapon /dev/mapper/${VG_NAME}-$SWAP_LV
info "Filesystems mounted"

# Generate mirror list
info "Generate mirror list"
reflector -l 10 -p https -c DE --sort rate --save /etc/pacman.d/mirrorlist
info "Mirror list generated"

# Install base system
info "Install packages"
PACKAGES="base linux linux-headers linux-firmware base-devel efibootmgr git grub lvm2 nano networkmanager os-prober plasma openssh kitty fastfetch"
pacstrap -K /mnt $PACKAGES linux-zen linux-zen-headers intel-ucode mesa intel-media-driver
# todo: Selection, extra kernels: linux-zen linux-zen-headers, linux-lts linux-lts-headers
# todo: Selection, graphic drivers: mesa libva-mesa-driver, nvidia nvidia-utils nvidia-lts, mesa intel-media-driver
# todo: Selection, microcode: amd-ucode, intel-ucode; (lscpu, automatic with vendor id)
info "Packages installed"

# Generate fstab
info "Generate fstab"
genfstab -U /mnt >> /mnt/etc/fstab
info "fstab generated"

# Enter chroot
info "Enter chroot"
arch-chroot /mnt /bin/bash -c "ln -sf /usr/share/zoneinfo/Europe/Berlin /etc/localtime
sed -i 's/#de_DE.UTF-8 UTF-8/de_DE.UTF-8 UTF-8/;s/#en_GB.UTF-8 UTF-8/en_GB.UTF-8 UTF-8/;s/#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
locale-gen
echo 'LANG=en_GB.UTF-8' > /etc/locale.conf
echo 'KEYMAP=de' > /etc/vconsole.conf
echo -e 'Section "InputClass"\n    Identifier "system-keyboard"\n    MatchIsKeyboard "on"\n    Option "XkbLayout" "de"\nEndSection' > /etc/X11/xorg.conf.d/00-keyboard.conf
echo 'i-use-arch-btw' > /etc/hostname
useradd -m -G wheel $USERNAME
echo -e 'root:"$ROOT_PASSWD"\n"$USERNAME":"$USER_PASSWD"' | chpasswd
sed -i 's|^# Cmnd_Alias\tREBOOT =.*|Cmnd_Alias\tREBOOT = /sbin/halt, /sbin/reboot, /sbin/poweroff, /sbin/shutdown|;s|# %wheel ALL=(ALL:ALL) ALL|%wheel ALL=(ALL:ALL) ALL, NOPASSWD: REBOOT|' /etc/sudoers
sed -i 's|^HOOKS=.*|HOOKS=(base udev autodetect microcode modconf kms keyboard keymap consolefont block encrypt lvm2 filesystems fsck)|' /etc/mkinitcpio.conf
mkinitcpio -P
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB
sed -i 's|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT=\"loglevel=3 root=/dev/mapper/$VG_NAME-$ROOT_LV cryptdevice=$LUKS_PART:$LUKS_NAME quiet\"|' /etc/default/grub
grub-mkconfig -o /boot/grub/grub.cfg
systemctl enable NetworkManager
systemctl enable sddm
systemctl enable sshd"
info "Exit chroot"

# Result screen
info "Installation complete!"
#sda1size=$(($(blockdev --getsize64 $EFI_PART)/1024/1024))
#sda2size=$(($(blockdev --getsize64 $BOOT_PART)/1024/1024))
#sda3size=$(($(blockdev --getsize64 $LUKS_PART)/1024/1024/1024))
#echo "sda1: EFI system partition (${sda1size}MB)"
#echo "sda2: BIOS boot partition (${sda2size}MB)"
#echo "sda3: Linux LUKS (${sda3size}GB)"
echo; echo "System Summary:"
lsblk -o NAME,FSTYPE,SIZE,MOUNTPOINT
echo; read -p "Press enter to continue"

# Unmount and reboot
echo; echo "Rebooting in 10 seconds..."; sleep 10
umount -R /mnt; swapoff -a; reboot
