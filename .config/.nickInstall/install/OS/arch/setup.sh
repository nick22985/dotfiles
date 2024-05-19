# fs.inotify.max_user_watches=524288
# For Arch Linux add this line to /etc/sysctl.d/99-sysctl.conf: 

# lsblk
# Find the disk you want to use.
# Select drive get user to select this / show all drives and info
# gdisk /dev/sdb (the drive)
# x (expert mode)
# z (zap the drive)
# y
# Y 
# cgdisk /dev/sdb
# n
# enter
# enter (first sector)
# 1024MiB (boot drive)
# EF00 (EFI System)
# boot
# go to bottom (new partition)
# enter
# enter
# 2GB (swap) (if wanna hiberate do the RAM size)
# enter
# 8200 (Linux swap)
# enter
# swap
# enter
# down
# enter
# enter
# 100Gib (root)
# enter
# enter
# root
# down
# enter
# enter
# enter
# enter
# home
# write
# enter
# yes
# enter
# mkfs.fat -F32 /dev/sdb1
# enter
# mkswap /dev/sdb2
# enter
# swapon /dev/sdb2
# enter
# mkfs.ext4 /dev/sdb3
# enter
# mkfs.ext4 /dev/sdb4
# enter
# mount /dev/sdb3 /mhooknt
# enter
# mkdir /mnt/boot
# enter
# mkdir /mnt/home
# enter
# mount /dev/sdb1 /mnt/boot
# enter
# mount /dev/sdb4 /mnt/home
# enter
# cp /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.backup
# enter
# pacman -Sy
# pacman -S pacman-contrib
# enter
# y
# enter
# rankmirrors -n 6 /etc/pacman.d/mirrorlist.backup > /etc/pacman.d/mirrorlist
# enter
# pacstrap /mnt base base-devel linux linux-firmware
# enter
# enter
# enter
# Y
# enter
# genfstab -U -p /mnt >> /mnt/etc/fstab
# enter
# arch-chroot /mnt
# enter
# sudo pacman -S neovim bash-completion
# y
# enter
# nvim /etc/locale.gen (en_AU.UTF-8 UTF-8)
# enter (save)
# locale-gen
# enter
# echo LANG=en_AU.UTF-8 > /etc/locale.conf
# enter
# export LANG=en_AU.UTF-8
# enter
# ln -s /usr/share/zoneinfo/Australia/Brisbane /etc/localtime
# enter
# hwclock --systohc --utc
# enter
# echo overlord > /etc/hostname (configure hostname at start)
# nvim /etc/pacman.conf
# uncomment [multilib] both lines to the multilib and the line below it with includes
# enter (save)
# systemctl enable fstrim.timer
# enable
# pacman -Sy
# passwd 
# enter
# password here (enter at the start)
# Pass again
# useradd -m -g users -G wheel,storage,power -s /bin/bash nick (username configured at start)
# enter
# passwd nick 
# Password configured at start different from the root one
# enter
# confirm password
# enter
# EDITOR=nvim visudo
# uncomment wheel ALL=(ALL:ALL) ALL
# goto bottom of file and add
# Defaults rootpw
# save and exit
# mount -t efivarfs efivarfs /sys/firmware/efivars (sould already be mounted and fail)
# bootctl install
# nvim /boot/loader/entries/default.conf
# enter this in the file 
# title Nick Arch linux
# linux /vmlinuz-linux
# initrd /intel-ucode.img
# initrd /initramfs-linux.img
# (save and exit)
# sudo pacman -S intel-ucode (amd-ucode for amd)
# enter
# y
# enter
# echo "options root=PARTUUID=$(blkid -s PARTUUID -o value /dev/sdb3) rw" >> /boot/loader/entries/default.conf  (same drive at start use) 
# sudo pacman -S dhcpcd
# systemctl enable dhcpcd@eno2.service (use actual network driver from ip addr)
# sudo pacman -S networkmanager
# systemctl enable NetworkManager.service
# sudo pacman -S linux-headers
# sudo pacman -S nvidia-dkms nlibglvnd lvidia-utils opencl-nvidia ib32-libglvnd lib32-nvidia-utils lib32-opencl-nvidia nvidia-settings # nvidia gpu
# nvim /etc/mkinitcpio.conf
# where it says MODULES=() make it MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)
# save and exit
# nvim /boot/loader/entries/default.conf
# options line after rw (should be last line) add nvidia-drm.modeset=1
# mkdir /etc/pacman.d/hooks
# nvim /etc/pacman.d/hooks/nvidia
# add the following to this file
# [Trigger]
# Operation=Install
# Operation=Upgrade
# Operation=Remove
# Type=Package
# Target=nvidia
#
# [Action]
# Depends=mkinitcpio
# When=PostTransaction
#	Exec=/usr/bin/mkinitcpio -P
#	(save and exit)
#
# sudo pacman -S mesa xorg-server xorg-apps xorg-xinit xorg-twn xorg-xclock xterm (xorg)
# sudo pacman -S plasma sddn
# sudo systemctl enable sddm.service
# sudo pacman -S konsole firefox discord steam


#!/bin/bash

# Function to prompt for password and confirmation
prompt_password() {
    local prompt=$1
    local password
    local password_confirm
    while true; do
        read -s -p "$prompt: " password
        echo
        read -s -p "Confirm $prompt: " password_confirm
        echo
        [ "$password" = "$password_confirm" ] && break
        echo "Passwords do not match. Please try again."
    done
    echo "$password"
}

# Prompt for variables
read -p "Enter the disk to use (e.g., /dev/sda): " DISK
read -p "Enter the size of the boot partition (e.g., 1024MiB): " BOOT_SIZE
read -p "Enter the size of the swap partition (e.g., 2GB): " SWAP_SIZE
read -p "Enter the size of the root partition (e.g., 100GiB): " ROOT_SIZE
read -p "Enter your hostname: " HOSTNAME
ROOT_PASS=$(prompt_password "Enter the root password")
USERNAME=$(prompt_password "Enter your username")
USER_PASS=$(prompt_password "Enter the user password for $USERNAME")
echo "Choose the display server to install:"
echo "1) Xorg"
echo "2) Wayland"
read -p "Enter the number of your choice: " DISPLAY_SERVER

# Set system configuration
echo "fs.inotify.max_user_watches=524288" | sudo tee -a /etc/sysctl.d/99-sysctl.conf

# Partition the disk
sgdisk -Z ${DISK}
sgdisk -n 1:0:+${BOOT_SIZE} -t 1:ef00 -c 1:boot ${DISK}
sgdisk -n 2:0:+${SWAP_SIZE} -t 2:8200 -c 2:swap ${DISK}
sgdisk -n 3:0:+${ROOT_SIZE} -c 3:root ${DISK}
sgdisk -n 4:0:0 -c 4:home ${DISK}

# Format the partitions
mkfs.fat -F32 ${DISK}1
mkswap ${DISK}2
swapon ${DISK}2
mkfs.ext4 ${DISK}3
mkfs.ext4 ${DISK}4

# Mount the partitions
mount ${DISK}3 /mnt
mkdir /mnt/boot
mkdir /mnt/home
mount ${DISK}1 /mnt/boot
mount ${DISK}4 /mnt/home

# Backup and rank mirrors
cp /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.backup
pacman -Sy
pacman -S pacman-contrib --noconfirm
rankmirrors -n 6 /etc/pacman.d/mirrorlist.backup > /etc/pacman.d/mirrorlist

# Install base system
pacstrap /mnt base base-devel linux linux-firmware

# Generate fstab
genfstab -U -p /mnt >> /mnt/etc/fstab

# Chroot into the new system
arch-chroot /mnt <<EOF

# Set up locale
pacman -S neovim bash-completion --noconfirm
sed -i 's/#en_AU.UTF-8/en_AU.UTF-8/' /etc/locale.gen
locale-gen
echo LANG=en_AU.UTF-8 > /etc/locale.conf
export LANG=en_AU.UTF-8

# Set up timezone and clock
ln -sf /usr/share/zoneinfo/Australia/Brisbane /etc/localtime
hwclock --systohc --utc

# Set hostname
echo ${HOSTNAME} > /etc/hostname

# Enable multilib
sed -i '/#\[multilib\]/,/#Include/s/^#//' /etc/pacman.conf
systemctl enable fstrim.timer
pacman -Sy

# Set root password
echo "root:${ROOT_PASS}" | chpasswd

# Create user and set password
useradd -m -g users -G wheel,storage,power -s /bin/bash ${USERNAME}
echo "${USERNAME}:${USER_PASS}" | chpasswd

# Configure sudoers
EDITOR=nvim visudo <<EOT
%s/# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/g
/%wheel ALL=(ALL:ALL) ALL/a Defaults rootpw
:wq
EOT

# Configure boot loader
mount -t efivarfs efivarfs /sys/firmware/efivars
bootctl install
cat > /boot/loader/entries/default.conf <<EOT
title ${USERNAME} Arch Linux
linux /vmlinuz-linux
initrd /intel-ucode.img
initrd /initramfs-linux.img
options root=PARTUUID=$(blkid -s PARTUUID -o value ${DISK}3) rw
EOT

# Install Intel microcode (replace with amd-ucode for AMD)
pacman -S intel-ucode --noconfirm
echo "options root=PARTUUID=$(blkid -s PARTUUID -o value ${DISK}3) rw" >> /boot/loader/entries/default.conf

# Network setup
pacman -S dhcpcd --noconfirm
systemctl enable dhcpcd@$(ip link | grep -oP '(?<=: ).*?(?=:)' | grep -v lo | head -n 1).service
pacman -S networkmanager --noconfirm
systemctl enable NetworkManager.service

# Install necessary packages
pacman -S linux-headers nvidia-dkms libglvnd nvidia-utils opencl-nvidia lib32-libglvnd lib32-nvidia-utils lib32-opencl-nvidia nvidia-settings --noconfirm

# Configure mkinitcpio
sed -i 's/^MODULES=()/MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)/' /etc/mkinitcpio.conf
mkinitcpio -P

# Update boot loader
sed -i '/options root/s/$/ nvidia-drm.modeset=1/' /boot/loader/entries/default.conf

# Configure nvidia hook
mkdir /etc/pacman.d/hooks
cat > /etc/pacman.d/hooks/nvidia.hook <<EOT
[Trigger]
Operation=Install
Operation=Upgrade
Operation=Remove
Type=Package
Target=nvidia

[Action]
Depends=mkinitcpio
When=PostTransaction
Exec=/usr/bin/mkinitcpio -P
EOT

# Install yay
cd /tmp
git clone https://aur.archlinux.org/yay.git
cd yay
makepkg -si --noconfirm

# Install display server and Plasma
if [ "$DISPLAY_SERVER" -eq 1 ]; then
    pacman -S mesa xorg-server xorg-apps xorg-xinit xorg-twm xorg-xclock xterm --noconfirm
    pacman -S plasma kde-applications --noconfirm
    pacman -S sddm --noconfirm
    systemctl enable sddm.service
elif [ "$DISPLAY_SERVER" -eq 2 ]; then
    pacman -S wayland wayland-protocols weston xorg-server-xwayland --noconfirm
    pacman -S --needed xorg-xwayland xorg-xlsclients qt5-wayland glfw-wayland --noconfirm
    pacman -S --needed plasma kde-applications plasma-wayland-session egl-wayland --noconfirm
    yay -S sddm-git --noconfirm
    systemctl enable sddm.service
  	# Configure SDDM
		echo -e "[Theme]\n# current theme name\nCurrent=breeze" | sudo tee /usr/lib/sddm/sddm.conf.d/default.conf
fi


# Install additional packages
pacman -S konsole firefox discord steam --noconfirm

EOF

echo "Arch Linux installation is complete. Please reboot."

