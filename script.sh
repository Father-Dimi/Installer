#!/bin/bash

# Detect the firmware type of the system
if [[ -d /sys/firmware/efi ]]; then
    firmware_type='UEFI'
else
    firmware_type='Legacy BIOS'
fi

echo "Tell us the partition (ie; /dev/sda)"
read part

echo "Tell us the boot partitions, you can ignore this if you use legacy bios (ie; /dev/sda1)"
read boot_part

echo "Tell us the root partition (ie; /dev/sda2)"
read root_part

echo "Tell us the swap partition (ie; /dev/sda3)"
read swap_part

# Prompt the user for the desired partition sizes
if [[ $firmware_type == 'UEFI' ]]; then
    echo "Enter the size of the boot partition (in MB):"
    read boot_size
fi

echo "Enter the size of the root partition (in GB):"
read root_size
echo "Enter the amount of RAM in your machine (in GB):"
read ram_size

# Calculate swap partition size as twice the RAM size
swap_size=$((${ram_size}*2))

# Partition the disk according to the firmware type
if [[ $firmware_type == 'UEFI' ]]; then
    parted $part mklabel gpt
    parted $part mkpart primary fat32 1MiB ${boot_size}MiB
    parted $part set 1 esp on
    parted $part mkpart primary ext4 ${boot_size+1}MiB ${boot_size+1+root_size}GiB
    parted $part mkpart primary linux-swap ${boot_size+1+root_size}GiB ${boot_size+1+root_size+swap_size}GiB
else
    parted $part mklabel msdos
    parted $part mkpart primary ext4 1MiB ${root_size}GiB
    parted $part set 1 boot on
    parted $part mkpart primary linux-swap ${root_size}GiB ${root_size+swap_size}GiB
fi

# Format the partitions
if [[ $firmware_type == 'UEFI' ]]; then
    mkfs.fat -F32 $boot_part
    mkfs.ext4 $root_part
    mkswap $swap_part
else
    mkfs.ext4 $root_part
    mkswap $swap_part
fi

# Mount the root partition
if [[ $firmware_type == 'UEFI' ]]; then
    mount $root_part /mnt && swapon $swap_part
else
    mount $root_part /mnt && swapon $swap_part


if [[ $firmware_type == 'UEFI' ]]; then
    # Create the boot directory and mount the boot partition
    mount --mkdir $boot_part /mnt/boot
fi

# Install base system packages
pacstrap /mnt base linux linux-firmware grub efibootmgr

# Generate a fstab file for mounting partitions
genfstab -U /mnt >> /mnt/etc/fstab

# Change root into the new system and configure system settings
chroot /mnt /bin/bash -c "locale-gen && echo LANG=en_US.UTF-8 > /etc/locale.conf && "

# Prompt the user for additional packages to install
echo "Enter a space-separated list of additional packages to install (or press enter to skip):"
read additional_packages

# Install additional packages with pacman
if [[ -n $additional_packages ]]; then
    chroot /mnt /bin/bash -c "pacman -S --noconfirm ${additional_packages}"
fi

# Prompt the user for their desired hostname
echo "Enter your desired hostname:"
read hostname

# Change the hostname in the new system
chroot /mnt /bin/bash -c "echo '${hostname}' > /etc/hostname && echo '127.0.0.1     localhost' > /etc/hosts && echo '::1           localhost' >> /etc/hosts"

# Install grub
if [[ $firmware_type == 'UEFI']]; then
    


# Prompt the user if they want to add a new user with root privileges
echo "Do you want to add a new user with root privileges? (y/n)"
read add_user

if [[ $add_user == 'y' ]]; then
    # Prompt the user for the new user's username and password
    echo "Enter the username for the new user:"
    read username

    # Prompt the user if the new user should have root privileges or not
    echo "Should the new user have root privileges? (y/n)"
    read root_privileges

    chroot /mnt /bin/bash -c "useradd -m -G wheel -s /bin/bash ${username}"
    echo "Enter the password for the new user:"
    chroot /mnt /bin/bash -c "passwd ${username}"

    if [[ $root_privileges == 'y' ]]; then
        chroot /mnt /bin/bash -c "sed -i -e 's/# %wheel ALL=(ALL) NOPASSWD: ALL/%wheel ALL=(ALL) NOPASSWD: ALL/g' /etc/sudoers"
    fi
fi

