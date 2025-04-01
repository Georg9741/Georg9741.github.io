#!/bin/bash

# Usage
# --------
# curl -O https://georg9741.github.io/archlinux/install.sh
# chmod +x install.sh
# ./install.sh

function clearscreen () {
  echo
  echo
  read -p "Press enter to continue"
  clear
}

clear
echo
echo "current criterias for this script to be functional: uefi mode, harddrive name: sda, cpu: intel, graphics: intel"
clearscreen

# Exit on error
set -e

# Inputs
while true; do
  read -s -p "Enter crypt password: " CRYPTPASSWD
  echo
  read -s -p "Enter crypt password (again): " CRYPTPASSWD2
  echo
  [ "$CRYPTPASSWD" = "$CRYPTPASSWD2" ] && break
  echo "Please try again"
done
while true; do
  read -s -p "Enter root password:" ROOTPASSWD
  echo
  read -s -p "Enter root password (again): " ROOTPASSWD2
  echo
  [ "$ROOTPASSWD" = "$ROOTPASSWD2" ] && break
  echo "Please try again"
done
while true; do
  read -s -p "Enter user password:" USERPASSWD
  echo
  read -s -p "Enter user password (again): " USERPASSWD2
  echo
  [ "$USERPASSWD" = "$USERPASSWD2" ] && break
  echo "Please try again"
done
# passwordhash=`openssl passwd -1 $password`
clearscreen

# Partitioning
echo
echo "Partitioning..."
echo
wipefs -a /dev/sda*
gdisk /dev/sda <<EOF
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
echo
echo "...finished"
echo
clearscreen

echo "Partitioning... finished"
echo
sda1size=$(($(blockdev --getsize64 /dev/sda1)/1048576))
sda2size=$(($(blockdev --getsize64 /dev/sda2)/1048576))
sda3size=$(($(blockdev --getsize64 /dev/sda3)/1073741824))
echo "sda1: EFI system partition ($sda1size MB)"
echo "sda2: BIOS boot partition ($sda2size MB)"
echo "sda3: Linux LUKS ($sda3size GB)"
clearscreen

# Format partitions
echo
echo "Format partitions..."
echo
mkfs.fat -F32 /dev/sda1
mkfs.ext4 /dev/sda2
cryptsetup -q luksFormat /dev/sda3 <<EOF
$CRYPTPASSWD
EOF
cryptsetup open /dev/sda3 luks_lvm <<EOF
$CRYPTPASSWD
EOF
echo
echo "...finished"
echo
clearscreen

echo "Format partitions... finished"
echo
echo "sda1: fat"
echo "sda2: ext4"
echo "sda3: luks"
clearscreen

# LVM Setup
echo
echo "LVM Setup..."
echo
pvcreate /dev/mapper/luks_lvm
vgcreate arch /dev/mapper/luks_lvm
lvcreate arch -n swap -L 32GB -C y
lvcreate arch -n root -L 64GB
lvcreate arch -n home -l +100%FREE
echo
echo "...finished"
echo
clearscreen

echo "LVM Setup... finished"
echo
echo "swap: 32 GB"
echo "root: 64 GB"
echo "home: 'todo: calculate +100%FREE' GB"
clearscreen

# Format LVM partitions
echo
echo "Format LVM partitions..."
echo
mkswap /dev/mapper/arch-swap
mkfs.ext4 /dev/mapper/arch-root -L root
mkfs.ext4 /dev/mapper/arch-home -L home
echo
echo "...finished"
echo
clearscreen

# Mount filesystems
echo
echo "Mount filesystems..."
echo
mount /dev/mapper/arch-root /mnt
mount /dev/mapper/arch-home /mnt/home --mkdir
mount /dev/sda2 /mnt/boot --mkdir
mount /dev/sda1 /mnt/boot/efi --mkdir
swapon /dev/mapper/arch-swap
echo
echo "...finished"
echo
clearscreen

# Generate mirror list
echo
echo "Generate mirror list..."
echo
reflector -l 10 -p https -c DE --sort rate --save /etc/pacman.d/mirrorlist
echo
echo "...finished"
echo
clearscreen

# Install base system
echo
echo "Install packages..."
echo
PACKAGES='base linux linux-headers linux-firmware base-devel efibootmgr git grub lvm2 nano networkmanager os-prober linux-zen linux-zen-headers intel-ucode plasma openssh kitty fastfetch mesa intel-media-driver'
pacstrap -K /mnt $PACKAGES
# Selection extra kernels: pacstrap -K /mnt linux-zen linux-zen-headers | pacstrap -K /mnt linux-lts linux-lts-headers
# Selection microcode: pacstrap -K /mnt amd-ucode | pacstrap -K /mnt intel-ucode (lscpu, automatic with vendor id)
echo
echo "...finished"
echo
clearscreen

# Generate fstab
echo
echo "Generate fstab..."
echo
genfstab -U /mnt >> /mnt/etc/fstab
echo
echo "...finished"
echo
clearscreen

# Enter chroot
echo
echo "Enter chroot..."
echo
arch-chroot /mnt <<EOF
ln -sf /usr/share/zoneinfo/Europe/Berlin /etc/localtime
sed -i 's/#de_DE.UTF-8 UTF-8/de_DE.UTF-8 UTF-8/;s/#en_GB.UTF-8 UTF-8/en_GB.UTF-8 UTF-8/;s/#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
locale-gen
echo "LANG=en_GB.UTF-8" > /etc/locale.conf
echo "KEYMAP=de" > /etc/vconsole.conf
echo "i-use-arch-btw" > /etc/hostname
passwd
$ROOTPASSWD
$ROOTPASSWD
useradd -m -G wheel georg
passwd georg
$USERPASSWD
$USERPASSWD
sed -i 's/^# Cmnd_Alias\tREBOOT =.*/Cmnd_Alias\tREBOOT = \/sbin\/halt, \/sbin\/reboot, \/sbin\/poweroff, \/sbin\/shutdown/;s/# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL, NOPASSWD: REBOOT/' /etc/sudoers
sed -i 's/^HOOKS=.*/HOOKS=(base udev autodetect microcode modconf kms keyboard keymap consolefont block encrypt lvm2 filesystems fsck)/' /etc/mkinitcpio.conf
mkinitcpio -P
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB
sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT=.*/GRUB_CMDLINE_LINUX_DEFAULT="loglevel=3 root=\/dev\/mapper\/arch-root cryptdevice=\/dev\/sda3:luks_lvm quiet"/' /etc/default/grub
grub-mkconfig -o /boot/grub/grub.cfg
systemctl enable NetworkManager
systemctl enable sddm
systemctl enable sshd
localectl set-x11-keymap de
EOF
echo
echo "...finished"
echo
clearscreen

echo "Enter chroot... finished"
echo "root password set"
echo "user georg created"
echo "user added to group wheel"
echo "installed stuff"
echo "configured stuff"
clearscreen

# Unmount and reboot
umount -R /mnt
swapoff -a
clear
read -p "Press enter to reboot"
reboot
