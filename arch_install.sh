#!/bin/bash
set -e  # Exit immediately if a command exits with a non-zero status

# Enable system clock update
timedatectl set-ntp true

# Prompt for username and passwords
echo -n "Enter new username: "
read NEW_USER
echo -n "Enter root password: "
stty -echo
read ROOT_PASS
stty echo
echo

echo -n "Enter password for user $NEW_USER: "
stty -echo
read USER_PASS
stty echo
echo

# Create partition table and partitions
parted -s /dev/sda mklabel gpt
parted -s /dev/sda mkpart primary ext4 1MiB 90%
parted -s /dev/sda mkpart primary ext4 90% 91%
parted -s /dev/sda mkpart ESP fat32 91% 92%
parted -s /dev/sda mkpart primary linux-swap 92% 100%
parted -s /dev/sda set 3 esp on

# Format partitions
mkfs.ext4 /dev/sda1
mkfs.ext4 /dev/sda2
mkfs.fat -F32 /dev/sda3
mkswap /dev/sda4
swapon /dev/sda4

# Mount partitions
mount /dev/sda1 /mnt
mkdir -p /mnt/boot
mount /dev/sda2 /mnt/boot
mkdir -p /mnt/boot/efi
mount /dev/sda3 /mnt/boot/efi

# Install base system with essential packages
pacstrap /mnt base linux linux-firmware dhcpcd vim sudo

echo "Generating fstab..."
genfstab -U /mnt >> /mnt/etc/fstab

# Enter chroot environment to configure the system
arch-chroot /mnt /bin/bash <<EOF
set -e

# Set timezone
ln -sf /usr/share/zoneinfo/UTC /etc/localtime
hwclock --systohc

# Generate locale
sed -i 's/^#en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

# Set hostname
echo "archlinux" > /etc/hostname

# Enable networking service
systemctl enable dhcpcd

# Set root password
echo "root:$ROOT_PASS" | chpasswd

# Install and configure GRUB
pacman --noconfirm -S grub efibootmgr
mkdir -p /boot/efi
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB || grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB --force
grub-mkconfig -o /boot/grub/grub.cfg

# Add a new user with sudo privileges
useradd -m -G wheel -s /bin/bash $NEW_USER
echo "$NEW_USER:$USER_PASS" | chpasswd
sed -i 's/^# %wheel ALL=(ALL) ALL/%wheel ALL=(ALL) ALL/' /etc/sudoers

exit
EOF

# Unmount partitions
umount -R /mnt

# Installation complete
echo "Installation complete! You can now reboot."
