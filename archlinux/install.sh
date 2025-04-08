#!/bin/bash

# Usage
# --------
# curl -O https://georg9741.github.io/archlinux/install.sh
# chmod +x install.sh
# ./install.sh

# Exit on error
set -euo pipefail

# Colors
NC="\033[0m" # No Color
RED="\033[0;31m"
GREEN="\033[0;32m"

# Variables
USERNAME=""
DISK_NAME=""

DISK="/dev/$DISK_NAME"

EFI_PART="${DISK}1"
BOOT_PART="${DISK}2"
LUKS_PART="${DISK}3"
EFI_SIZE="256M"
BOOT_SIZE="512M"
LUKS_NAME="luks_lvm"

VG_NAME="arch"
SWAP_LV="swap"
ROOT_LV="root"
HOME_LV="home"

ROOT_LV_SIZE="64G"

# Functions
info() {
  echo; echo -e "${GREEN}[INFO] ${NC}$1"
}
warning() {
  echo; echo -e "${RED}[WARNING] ${NC}$1"
}
input_username() {
  local username
  clear; echo; echo "[USERNAME]"; echo
  read -p "Set your username: " username
  eval "USERNAME='$username'"
}
input_diskname() {
  local disk_name
  echo; echo "[DRIVE SELECTION]"; echo
  lsblk
  while true; do
    echo; read -p "Enter drive name: " disk_name
    if lsblk | grep -q "^$disk_name"; then
      eval "DISK_NAME='$disk_name'" && break
    else
      echo; echo "Invalid drive name. Please enter a valid drive."
    fi
  done
}
input_password() {
  local mismatch=0 title=$1 msg=$2 varname=$3 pass1 pass2
  while true; do
    clear; echo; echo "[$title]"; echo
    if (( mismatch )); then echo "Passwords do not match. Try again."; echo; fi
    read -s -p "Enter $msg: " pass1; echo; echo
    read -s -p "Verify $msg: " pass2
    [[ "$pass1" == "$pass2" ]] && eval "$varname='$pass1'" && break
    mismatch=1
  done
}
create_partitions() {
  info "Partitioning"
  echo -e "o\ny\nn\n\n\n+$EFI_SIZE\nef00\nn\n\n\n+$BOOT_SIZE\nef02\nn\n\n\n\n8309\nw\ny" | gdisk $DISK
  info "Partitioning finished"
}
format_partitions() {
  info "Format partitions"
  mkfs.fat -F32 $EFI_PART
  mkfs.ext4 $BOOT_PART
  echo -n "$CRYPT_PASSWD" | cryptsetup -q luksFormat $LUKS_PART
  echo -n "$CRYPT_PASSWD" | cryptsetup open $LUKS_PART $LUKS_NAME
  info "Partitions formatted"
}
setup_lvm() {
  info "LVM Setup"
  local ram_size=$(grep MemTotal /proc/meminfo | awk '{print $2}') # in KB
  local swap_size=$((ram_size/1024/1024)) # Convert to GB
  if [ $swap_size -lt 8 ]; then
    swap_size=8 # Set a minimum swap of 8GB
  elif [ $swap_size -gt 32 ]; then
    swap_size=32 # Cap swap at 32GB
  fi
  pvcreate /dev/mapper/$LUKS_NAME
  vgcreate $VG_NAME /dev/mapper/$LUKS_NAME
  lvcreate $VG_NAME -n $SWAP_LV -L ${SWAP_SIZE}G -C y
  lvcreate $VG_NAME -n $ROOT_LV -L $ROOT_LV_SIZE
  lvcreate $VG_NAME -n $HOME_LV -l +100%FREE
  info "LVM Setup finished"
}
format_lvm_partitions() {
  info "Format LVM partitions"
  mkswap /dev/mapper/${VG_NAME}-$SWAP_LV
  mkfs.ext4 /dev/mapper/${VG_NAME}-$ROOT_LV -L $ROOT_LV
  mkfs.ext4 /dev/mapper/${VG_NAME}-$HOME_LV -L $HOME_LV
  info "LVM partitions formatted"
}
mount_filesystems() {
  info "Mount filesystems"
  mount /dev/mapper/${VG_NAME}-$ROOT_LV /mnt
  mount /dev/mapper/${VG_NAME}-$HOME_LV /mnt/home --mkdir
  mount $BOOT_PART /mnt/boot --mkdir
  mount $EFI_PART /mnt/boot/efi --mkdir
  swapon /dev/mapper/${VG_NAME}-$SWAP_LV
  info "Filesystems mounted"
}
generate_mirrorlist() {
  info "Generate mirror list"
  reflector -l 10 -p https -c DE --sort rate --save /etc/pacman.d/mirrorlist
  info "Mirror list generated"
}
install_base_system() {
  info "Install packages"
  if grep -qi "amd" /proc/cpuinfo; then
    MICROCODE="amd-ucode"
  elif grep -qi "intel" /proc/cpuinfo; then
    MICROCODE="intel-ucode"
  fi
  if lspci | grep -E "VGA|3D" | grep -qi "amd"; then
    GPU_DRIVERS="mesa libva-mesa-driver"
  elif lspci | grep -E "VGA|3D" | grep -qi "nvidia"; then
    GPU_DRIVERS="nvidia nvidia-utils nvidia-lts"
  elif lspci | grep -E "VGA|3D" | grep -qi "intel"; then
    GPU_DRIVERS="mesa intel-media-driver"
  else
    warning "Could not detect a supported GPU vendor."
  fi
  PACKAGES="base linux linux-headers linux-firmware base-devel efibootmgr git grub lvm2 nano networkmanager os-prober plasma openssh kitty fastfetch"
  pacstrap -K /mnt $PACKAGES $MICROCODE $GPU_DRIVERS
  # todo: Selection, extra kernels: linux-zen linux-zen-headers, linux-lts linux-lts-headers
  info "Packages installed"
}
generate_fstab() {
  info "Generate fstab"
  genfstab -U /mnt >> /mnt/etc/fstab
  info "fstab generated"
}
enter_chroot() {
  info "Enter chroot"
  arch-chroot /mnt /bin/bash -c "ln -sf /usr/share/zoneinfo/Europe/Berlin /etc/localtime
  sed -i 's/#de_DE.UTF-8 UTF-8/de_DE.UTF-8 UTF-8/;s/#en_GB.UTF-8 UTF-8/en_GB.UTF-8 UTF-8/;s/#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
  locale-gen
  echo 'LANG=en_GB.UTF-8' > /etc/locale.conf
  echo 'KEYMAP=de' > /etc/vconsole.conf
  echo -e 'Section \"InputClass\"\n    Identifier \"system-keyboard\"\n    MatchIsKeyboard \"on\"\n    Option \"XkbLayout\" \"de\"\nEndSection' > /etc/X11/xorg.conf.d/00-keyboard.conf
  echo 'i-use-arch-btw' > /etc/hostname
  sddm --example-config > /etc/sddm.conf
  sed -i 's/Current=/Current=breeze/' /etc/sddm.conf
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
}
result_output() {
  info "Installation complete!"
  #sda1size=$(($(blockdev --getsize64 $EFI_PART)/1024/1024))
  #sda2size=$(($(blockdev --getsize64 $BOOT_PART)/1024/1024))
  #sda3size=$(($(blockdev --getsize64 $LUKS_PART)/1024/1024/1024))
  #echo "sda1: EFI system partition (${sda1size}MB)"
  #echo "sda2: BIOS boot partition (${sda2size}MB)"
  #echo "sda3: Linux LUKS (${sda3size}GB)"
  echo; echo "System Summary:"
  lsblk -o NAME,FSTYPE,SIZE,MOUNTPOINT
  echo; read -p "Press enter to continue (Reboot)"
}
reboot() {
  umount -R /mnt || warning "Some partitions failed to unmount."
  swapoff -a
  sleep 2; reboot
}

input_username
input_diskname
input_password "USER PASSWORD" "user password" USER_PASSWD
input_password "ROOT PASSWORD" "root password" ROOT_PASSWD
input_password "DISK ENCRYPTION PASSWORD" "passphrase" CRYPT_PASSWD

clear
create_partitions
format_partitions
setup_lvm
format_lvm_partitions
mount_filesystems
generate_mirrorlist
install_base_system
generate_fstab
enter_chroot

result_output

reboot