#!/bin/bash

# Usage
# --------
# curl -O https://Georg9741.github.io/archinstall/install.sh
# chmod +x install.sh
# ./install.sh

# current criterias for this script to be functional: uefi mode, harddrive name: sda, cpu: intel, graphics: intel

# Exit on error
set -e

# Partitioning
echo ""
echo "Partitioning..."
echo ""
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
echo ""
echo "...finished"
echo ""

clear
echo "Partitioning... finished"
sda1size=$(($(blockdev --getsize64 /dev/sda1)/1048576))
sda2size=$(($(blockdev --getsize64 /dev/sda2)/1048576))
sda3size=$(($(blockdev --getsize64 /dev/sda3)/1073741824))
echo "EFI system partition ($sda1size MB)"
echo "BIOS boot partition ($sda1size MB)"
echo "Linux LUKS ($sda3size GB)"
read -p "Press enter to continue"

# Format partitions
echo ""
echo "Format partitions..."
echo ""
mkfs.fat -F32 /dev/sda1
mkfs.ext4 /dev/sda2
cryptsetup luksFormat /dev/sda3 # todo: loop, if re-enter password wrong; move input earlier in script and insert here
cryptsetup open /dev/sda3 luks_lvm # todo: automatically insert password
echo ""
echo "...finished"
echo ""

clear
echo "Format partitions... finished"
echo "sda1: fat"
echo "sda2: ext4"
echo "sda3: luks"
read -p "Press enter to continue"

# LVM Setup
echo ""
echo "LVM Setup..."
echo ""
pvcreate /dev/mapper/luks_lvm
vgcreate arch /dev/mapper/luks_lvm
lvcreate arch -n swap -L 32GB -C y
lvcreate arch -n root -L 64GB
lvcreate arch -n home -l +100%FREE
echo ""
echo "...finished"
echo ""

clear
echo "LVM Setup... finished"
echo "swap: 32 GB"
echo "root: 64 GB"
echo "home: 'todo: calculate +100%FREE' GB"
read -p "Press enter to continue"

# Format LVM partitions
echo ""
echo "Format LVM partitions..."
echo ""
mkswap /dev/mapper/arch-swap
mkfs.ext4 /dev/mapper/arch-root -L root
mkfs.ext4 /dev/mapper/arch-home -L home
echo ""
echo "...finished"
echo ""

clear
echo "Format LVM partitions... finished"
read -p "Press enter to continue"

# Mount filesystems
echo ""
echo "Mount filesystems..."
echo ""
mount /dev/mapper/arch-root /mnt
mount /dev/mapper/arch-home /mnt/home --mkdir
mount /dev/sda2 /mnt/boot --mkdir
mount /dev/sda1 /mnt/boot/efi --mkdir
swapon /dev/mapper/arch-swap
echo ""
echo "...finished"
echo ""

clear
echo "Mount filesystems... finished"
read -p "Press enter to continue"

# Generate mirror list
echo ""
echo "Generate mirror list..."
echo ""
reflector -l 10 -p https -c DE --sort rate --save /etc/pacman.d/mirrorlist
echo ""
echo "...finished"
echo ""

clear
echo "Generate mirror list... finished"
read -p "Press enter to continue"

# Install base system
echo ""
echo "Install packages..."
echo ""
PACKAGES='base linux linux-headers linux-firmware base-devel efibootmgr git grub lvm2 nano networkmanager os-prober linux-zen linux-zen-headers intel-ucode plasma openssh kitty fastfetch mesa intel-media-driver'
pacstrap -K /mnt $PACKAGES
# Selection extra kernels: pacstrap -K /mnt linux-zen linux-zen-headers | pacstrap -K /mnt linux-lts linux-lts-headers
# Selection microcode: pacstrap -K /mnt amd-ucode | pacstrap -K /mnt intel-ucode (lscpu, automatic with vendor id)
echo ""
echo "...finished"
echo ""

clear
echo "Install packages... finished"
read -p "Press enter to continue"

# Generate fstab
echo ""
echo "Generate fstab..."
echo ""
genfstab -U /mnt >> /mnt/etc/fstab
echo ""
echo "...finished"
echo ""

clear
echo "Generate fstab... finished"
read -p "Press enter to continue"

# Enter chroot
echo ""
echo "Enter chroot..."
echo ""
echo "Enter root password:"
read -s PASSWD # todo: move earlier; maybe loop a re-enter
echo "Enter user password:"
read -s USERPASSWD # todo: move earlier; maybe loop a re-enter
arch-chroot /mnt <<EOF
ln -sf /usr/share/zoneinfo/Europe/Berlin /etc/localtime
sed -i 's/#de_DE.UTF-8 UTF-8/de_DE.UTF-8 UTF-8/;s/#en_GB.UTF-8 UTF-8/en_GB.UTF-8 UTF-8/;s/#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
locale-gen
echo "LANG=en_GB.UTF-8" > /etc/locale.conf
echo "KEYMAP=de" > /etc/vconsole.conf
echo "i-use-arch-btw" > /etc/hostname
passwd
$PASSWD
$PASSWD
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
echo ""
echo "...finished"
echo ""

clear
echo "Enter chroot... finished"
echo "root password set"
echo "user georg created"
echo "user added to group wheel"
echo "installed stuff"
echo "configured stuff"
read -p "Press enter to continue"

# Unmount and reboot
umount -R /mnt
swapoff -a
clear
read -p "Press enter to reboot"
reboot
