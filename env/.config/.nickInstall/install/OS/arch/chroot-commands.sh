#!/bin/bash

DISK=$1
HOSTNAME=$2
ROOT_PASS=$3
USERNAME=$4
USER_PASS=$5
DISPLAY_SERVER=$6

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
    pacman -S sddm --noconfirm
    systemctl enable sddm.service
    # Configure SDDM
    echo -e "[Theme]\n# current theme name\nCurrent=breeze" | sudo tee /usr/lib/sddm/sddm.conf.d/default.conf
fi

# Install additional packages
pacman -S konsole firefox discord steam yay --noconfirm

echo "Arch Linux chroot configuration is complete."

