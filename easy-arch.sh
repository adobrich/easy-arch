#!/usr/bin/env -S bash -e
# Fork of: https://github.com/classy-giraffe/easy-arch
# Updated based on: https://www.ordinatechnic.com/distribution-specific-guides/arch-linux/an-arch-linux-installation-on-a-btrfs-filesystem-with-snapper-for-system-snapshots-and-rollbacks

# Cleaning the TTY.
clear

# Pretty print (function).
print () {
	case $1 in
		info ) echo -e "\e[1;37m[ \e[1;35mi\e[1;37m ] \e[2m$2\e[0m"
            ;;
		pass ) echo -e "\e[1;37m[ \e[1;32m√\e[1;37m ] \e[2m$2\e[0m"
            ;;
		fail ) echo -e "\e[1;37m[ \e[1;31mX\e[1;37m ] \e[2m$2\e[0m"
            ;;
        warn ) echo -en "\e[1;37m[ \e[1;33m!\e[1;37m ] \e[1:31m$2\e[0m"
            ;;
        input ) echo -en "\e[1;37m[ \e[1;34m?\e[1;37m ] \e[2m$2\e[0m"
            ;;
		blue ) echo -e "\e[1;34m$2\e[0m"
            ;;
		* ) echo -e "\e[1;37m$1\e[0m"
            ;;
	esac
}

# Executor with pretty print pass/fail (function).
execute () {
    if eval "$1" &>/dev/null; then
        print "pass" "$2"
    else
        print "fail" "Failed to $2"
    fi
}

# Virtualization check (function).
virt_check () {
    case $(systemd-detect-virt) in
        kvm )   print "info" "KVM has been detected."
                execute "pacstrap /mnt qemu-guest-agent" "install qemu-guest-agent"
                execute "systemctl enable qemu-guest-agent --root=/mnt" "enable qemu-guest-agent service"
                ;;
        vmware  )   print "info" "VMWare Workstation/ESXi has been detected."
                    execute "pacstrap /mnt open-vm-tools" "install open-vm-tools"
                    execute "systemctl enable vmtoolsd --root=/mnt" "enable vmtoolsd service"
                    execute "systemctl enable vmware-vmblock-fuse --root=/mnt" "enable vmware-vmblock-fuse service"
                    ;;
        oracle )    print "info" "VirtualBox has been detected."
                    execute "pacstrap /mnt virtualbox-guest-utils" "install virtualbox-guest-utils"
                    execute "systemctl enable vboxservice --root=/mnt" "enable vboxservice service"
                    ;;
        microsoft ) print "info" "Hyper-V has been detected."
                    execute "pacstrap /mnt hyperv" "install hyperv"
                    execute "systemctl enable hv_fcopy_daemon --root=/mnt" "enable hv_fcopy_daemon service"
                    execute "systemctl enable hv_kvp_daemon --root=/mnt" "enable hv_kvp_daemon service"
                    execute "systemctl enable hv_vss_daemon --root=/mnt" "enable hv_vss_daemon"
                    ;;
        * ) print "info" "No VM detected."
            ;;
    esac
}
virt_check
# Selecting a kernel to install (function).
kernel_selector () {
    print "info" "List of kernels:"
    print "  1) Stable: Vanilla Linux kernel with a few specific Arch Linux patches applied"
    print "  2) Hardened: A security-focused Linux kernel"
    print "  3) LTS: Long-term support (LTS) Linux kernel"
    print "  4) Zen: A Linux kernel optimized for desktop usage"
    print "input" "Insert the number of the corresponding kernel: "
    read -r choice
    case $choice in
        1 ) kernel="linux"
            ;;
        2 ) kernel="linux-hardened"
            ;;
        3 ) kernel="linux-lts"
            ;;
        4 ) kernel="linux-zen"
            ;;
        * ) print "fail" "You did not enter a valid selection."
            kernel_selector
    esac
}

# Selecting a way to handle internet connection (function).
network_selector () {
    print "info" "Network utilities:"
    print "  1) IWD: iNet wireless daemon (WiFi-only)"
    print "  2) NetworkManager: Universal network utility (both WiFi and Ethernet)"
    print "  3) wpa_supplicant: Cross-platform supplicant WEP, WPA and WPA2 (WiFi-only)"
    print "  4) dhcpcd: Basic DHCP client (Ethernet only or VMs)"
    print "  5) I will do this on my own (only advanced users)"
    print "input" "Insert the number of the corresponding networking utility: "
    read -r choice
    print "info" "Installing network utilities (it may take a while)"
    case $choice in
        1 ) execute "pacstrap /mnt iwd" "install iwd"
            execute "systemctl enable iwd --root=/mnt" "enable iwd"
            ;;
        2 ) execute "pacstrap /mnt networkmanager" "install networkmanager"
            execute "systemctl enable NetworkManager --root=/mnt" "enable NetworkManager service"
            ;;
        3 ) execute "pacstrap /mnt wpa_supplicant dhcpcd" "install wpa_supplicant"
            execute "pacstrap /mnt dhcpcd" "install dhcpcd"
            execute "systemctl enable wpa_supplicant --root=/mnt" "enable wpa_supplicant"
            execute "systemctl enable dhcpcd --root=/mnt" "enable dhcpcd"
            ;;
        4 ) execute "pacstrap /mnt dhcpcd" "install dhcpcd"
            execute "systemctl enable dhcpcd --root=/mnt" "enable dhcpcd"
            ;;
        5 ) print "info" "You will be required to set up your connection manually"
            ;;
        * ) print "fail" "You did not enter a valid selection."
            network_selector
    esac
}

# Microcode detector (function).
microcode_detector () {
    CPU=$(grep vendor_id /proc/cpuinfo)
    if [[ $CPU == *"AuthenticAMD"* ]]; then
        print "info" "An AMD CPU has been detected, the AMD microcode will be installed."
        microcode="amd-ucode"
    elif [[ $CPU == *"GenuineIntel"* ]]; then
        print "info" "An Intel CPU has been detected, the Intel microcode will be installed."
        microcode="intel-ucode"
    else
        print "info" "Non AMD/Intel CPU detected. Skipping microcode install."
        microcode="\b"
    fi
}

# Setting up the hostname (function).
hostname_selector () {
    print "input" "Please enter the hostname: "
    read -r hostname
    if [ -n "$hostname" ]; then
        execute "echo $hostname > /mnt/etc/hostname" "write hostname to /mnt/etc/hostname"
    else
        print "fail" "You need to enter a hostname in order to continue."
        hostname_selector
    fi
}

# Setting up the locale (function).
locale_selector () {
    print "input" "Please insert the locale(s) you use (format: xx_XX xx_XX or leave blank to use en_US): "
    read -r locale
    if [ -z "$locale" ]; then
        print "info" "en_US will be used as default locale."
        locale="en_US"
    fi
    print "input" "Please insert the language and fallback languages to use (format: xx_XX:xx_XX or leave blank to use US English): "
    read -r language
    if [ -z "$language" ]; then
        print "info" "US English will be used as default language."
        language="en"
    fi
    # Clear contents of /mnt/etc/locale.gen
    execute "truncate -s 0 /mnt/etc/locale.gen" "clear contents of existing /mnt/etc/locale.gen"
    for entry in $locale
    do
        execute "echo $entry.UTF-8 UTF-8 >> /mnt/etc/locale.gen" "write locale ($entry) to /mnt/etc/locale.gen"
    done
    # Set primary locale in (first in list) /mnt/etc/locale.conf
    IFS=' ' read -ra lang_array <<< $locale
    execute "echo LANG=${lang_array[0]}.UTF-8 >> /mnt/etc/locale.conf" "write locale to /mnt/etc/locale.conf"
    execute "echo "LANGUAGE=$language" >> /mnt/etc/locale.conf" "write language to /mnt/etc/locale.conf"
}

# Setting up the keyboard layout (function).
keyboard_selector () {
    print "input" "Please insert the keyboard layout you use or leave blank to use default US keyboard layout: "
    read -r kblayout
    if [ -z "$kblayout" ]; then
        print "info" "US keyboard layout will be used by default."
        kblayout="us"
    fi
    execute "echo KEYMAP=$kblayout > /mnt/etc/vconsole.conf" "write keymap ($kblayout) to /mnt/etc/vconsole.conf"
}

# Selecting the target for the installation.
print "blue" "Welcome to easy-arch, a script made in order to simplify the process of installing Arch Linux."
#PS3="Please select the disk where Arch Linux is going to be installed:\n"
PS3="$(tput bold)[ $(tput setaf 4 bold)?$(tput sgr0 bold) ] Please enter the number of the device where Arch Linux is going to be installed: "
select ENTRY in $(lsblk -dpnoNAME|grep -P "/dev/sd|nvme|vd");
do
    DISK=$ENTRY
    if [ -e "$DISK" ]; then
        print "info" "Installing Arch Linux on $DISK"
        break
    else
        print "fail" "You need to select a valid device."
    fi
done

# Deleting old partition scheme.
print "warn" "This will delete the current partition table on $DISK do you agree [y/N]? "
read -r response
response=${response,,}
if [[ "$response" =~ ^(yes|y|Y|YES)$ ]]; then
    execute "wipefs -af $DISK" "wipe $DISK"
    execute "sgdisk -Zo $DISK" "clear MBR and partition table on $DISK"
else
    print "info" "Quitting."
    exit
fi

# Creating a new partition scheme.
execute "parted -s $DISK \
mklabel gpt \
mkpart ESP fat32 1MiB 513MiB \
set 1 esp on \
mkpart root 513MiB 100% \
" "Creating the partitions on $DISK"

# Informing the Kernel of the changes.
execute "partprobe $DISK" "inform Kernel about the disk changes."

# Give the Kernel a few seconds to see the changes.
sleep 5

# Formatting the ESP as FAT32.
execute "mkfs.fat -F 32 -n ESP /dev/disk/by-partlabel/ESP" "format EFI partition as FAT32."

# Formatting root as BTRFS.
execute "mkfs.btrfs -f -L root -n 32k /dev/disk/by-partlabel/root" "format root as BTRFS"

# Use UUID to identify partitions
ESP="/dev/disk/by-uuid/$(blkid -s UUID -o value $(blkid -L ESP))"
BTRFS="/dev/disk/by-uuid/$(blkid -s UUID -o value $(blkid -L root))"

execute "mount $BTRFS /mnt" "mount root ($BTRFS) on /mnt"

# Creating BTRFS subvolumes.
print "info" "Creating BTRFS subvolumes."
execute "btrfs su cr /mnt/@" "create BTRFS subvolume /mnt/@"
execute "btrfs su cr /mnt/@/.snapshots" "create BTRFS subvolume /mnt/@/.snapshots"
execute "mkdir -p /mnt/@/.snapshots/1" "create mount point /mnt/@/.snapshots/1"
execute "btrfs su cr /mnt/@/.snapshots/1/snapshot" "create BTRFS subvolume /mnt/@/.snapshots/1/snapshot"
execute "mkdir /mnt/@/boot" "create mount point /mnt/@/boot"
execute "btrfs su cr /mnt/@/boot/grub" "create BTRFS subvolume /mnt/@/boot/grub"
execute "btrfs su cr /mnt/@/home" "create BTRFS subvolume /mnt/@/home"
execute "btrfs su cr /mnt/@/root" "create BTRFS subvolume /mnt/@/root"
execute "btrfs su cr /mnt/@/opt" "create BTRFS subvolume /mnt/@/opt"
execute "btrfs su cr /mnt/@/srv" "create BTRFS subvolume /mnt/@/srv"
execute "btrfs su cr /mnt/@/tmp" "create BTRFS subvolume /mnt/@/tmp"
execute "mkdir /mnt/@/usr" "create mount point /mnt/@/usr"
execute "btrfs su cr /mnt/@/usr/local" "create BTRFS subvolume /mnt/@/usr/local"
execute "mkdir /mnt/@/var" "create mount point /mnt/@/var"
execute "btrfs su cr /mnt/@/var/cache" "create BTRFS subvolume /mnt/@/var/cache"
execute "btrfs su cr /mnt/@/var/log" "create BTRFS subvolume /mnt/@/var/log"
execute "btrfs su cr /mnt/@/var/spool" "create BTRFS subvolume /mnt/@/var/spool"
execute "btrfs su cr /mnt/@/var/tmp" "create BTRFS subvolume /mnt/@/var/tmp"

# Creating initial snapper snapshot info
date_now=$(date +"%Y-%m-%d %T")
print "info" "Creating initial snapper snapshot info.xml"
cat << EOF >> /mnt/@/.snapshots/1/info.xml
<?xml version="1.0"?>
<snapshot>
	<type>single</type>
	<num>1</num>
	<date>$date_now</date>
	<description>First Root Filesystem Created at Installation</description>
</snapshot>
EOF

execute "chmod 600 /mnt/@/.snapshots/1/info.xml" "set permissions (600) on /mnt/@/.snapshots/1/info.xml"

# Set inital snapshot as default subvolume
execute "btrfs subvolume set-default $(btrfs subvolume list /mnt | grep "@/.snapshots/1/snapshot" | grep -oP '(?<=ID )[0-9]+') /mnt" "set inital snapshot as default subvolume."

# Enable BTRFS quotas for Snappers cleanup algorithms
execute "btrfs quota enable /mnt" "enable BTRFS quotas on /mnt"

execute "chattr +C /mnt/@/var/cache" "disable cow for /mnt/@/var/cache"
execute "chattr +C /mnt/@/var/log" "disable cow for /mnt/@/var/log"
execute "chattr +C /mnt/@/var/spool" "disable cow for /mnt/@/var/spool"
execute "chattr +C /mnt/@/var/tmp" "disable cow for /mnt/@/var/tmp"

# Mounting the newly created subvolumes.
execute "umount /mnt" "unmount /mnt"
print "info" "Mounting the newly created subvolumes."
execute "mount -o noatime,compress=zstd:8 $BTRFS /mnt" "mount BTRFS partition ($BTRFS) to /mnt"
execute "mkdir -p /mnt/{boot/grub,efi,root,home,.snapshots,srv,tmp,opt,usr/local,var/log,var/cache,var/tmp,var/spool}" "create required mount points."
execute "mount -o noatime,compress=zstd:8,subvol=@/.snapshots $BTRFS /mnt/.snapshots" "mount @/snapshots subvolume to /mnt/.snapshots"
execute "mount -o noatime,compress=zstd:8,subvol=@/boot/grub $BTRFS /mnt/boot/grub" "mount @/boot/grub subvolume to /mnt/boot/grub"
execute "mount -o noatime,compress=zstd:8,subvol=@/opt $BTRFS /mnt/opt" "mount @/opt subvolume to /mnt/opt"
execute "mount -o noatime,compress=zstd:8,subvol=@/root $BTRFS /mnt/root" "mount @/root subvolume to /mnt/root"
execute "mount -o noatime,compress=zstd:8,subvol=@/home $BTRFS /mnt/home" "mount @/home subvolume to /mnt/home"
execute "mount -o noatime,compress=zstd:8,subvol=@/srv $BTRFS /mnt/srv" "mount @/srv subvolume to /mnt/srv"
execute "mount -o noatime,compress=zstd:8,subvol=@/tmp $BTRFS /mnt/tmp" "mount @/tmp subvolume to /mnt/tmp"
execute "mount -o noatime,compress=zstd:8,subvol=@/usr/local $BTRFS /mnt/usr/local" "mount @/usr/local subvolume to /mnt/usr/local"
execute "mount -o noatime,compress=zstd:8,nodatacow,subvol=@/var/cache $BTRFS /mnt/var/cache" "mount @/var/cache subvolume to /mnt/var/cache"
execute "mount -o noatime,compress=zstd:8,nodatacow,subvol=@/var/log $BTRFS /mnt/var/log" "mount @/var/log subvolume to /mnt/var/log"
execute "mount -o noatime,compress=zstd:8,nodatacow,subvol=@/var/spool $BTRFS /mnt/var/spool" "mount @/var/spool subvolume to /mnt/var/spool"
execute "mount -o noatime,compress=zstd:8,nodatacow,subvol=@/var/tmp $BTRFS /mnt/var/tmp" "mount @/var/tmp subvolume to /mnt/var/tmp"
execute "mount $ESP /mnt/efi" "mount ESP ($ESP) to /mnt/efi"

# Select a fast pacman mirror.
execute "reflector -c $(curl -s http://ip-api.com/line?fields=countryCode) --age 12 --latest 3 --sort rate --save /etc/pacman.d/mirrorlist" "Select a fast mirror based on IP address."

# Setting up the kernel.
kernel_selector

# Checking the microcode to install.
microcode_detector

# Setting up the network.
network_selector

# Pacstrap (setting up a base sytem onto the new root).
print "info" "Installing the base system (it may take a while)."
execute "pacstrap /mnt base base-devel $kernel $microcode linux-firmware $kernel-headers btrfs-progs grub grub-btrfs rsync efibootmgr snapper reflector snap-pac zram-generator sudo efibootmgr bluez bluez-utils" "install base system to new root /mnt"

# Virtualization check.
virt_check

# Setting up the hostname.
hostname_selector

# Generating /etc/fstab.
execute "genfstab -U /mnt >> /mnt/etc/fstab" "generate fstab"

# Strip subvolume id for root to allow booting of alternate shapshots
execute "sed -i 's#,subvolid=258\,subvol=\/@\/\.snapshots\/1\/snapshot##g' /mnt/etc/fstab" "strip subvolume id for root from fstab to allow booting of BTRFS default subvolume"

# Update grub to look for the kernel in the snapshots subvolume
execute "sed -i 's#rootflags=subvol=${rootsubvol}##g' /mnt/etc/grub.d/10_linux" "update /mnt/etc/grub.d/10_linux to look for the Kernel in the snapshots subvolume"
execute "sed -i 's#rootflags=subvol=${rootsubvol}##g' /mnt/etc/grub.d/20_linux_xen" "update /mnt/etc/grub.d/20_linux_xen to look for the Kernel in the snapshots subvolume"

# Setting username.
print "input" "Please enter username for user account: "
read -r username

# Setting up the locale.
locale_selector

# Setting up keyboard layout.
keyboard_selector

# Setting hosts file.
execute "cat > /mnt/etc/hosts <<EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   $hostname.localdomain   $hostname
EOF" "set hosts file."

# Configuring /etc/mkinitcpio.conf.
execute "cat > /mnt/etc/mkinitcpio.conf <<EOF
HOOKS=(base systemd autodetect keyboard sd-vconsole modconf block filesystems)
COMPRESSION=(zstd)
EOF" "configure /etc/mkinitcpio.conf"

# Configuring the system.
print "info" "Entering chroot environment."
arch-chroot /mnt /bin/bash -e <<EOF
    # Setting up timezone.
    echo "Setting up the timezone."
    ln -sf /usr/share/zoneinfo/$(curl -s http://ip-api.com/line?fields=timezone) /etc/localtime

    # Setting up clock.
    echo "Setting up the system clock."
    hwclock --systohc

    # Generating locales.
    locale-gen
    unset LANG
    source /etc/profile.d/locale.sh

    # Generating a new initramfs.
    echo "Creating a new initramfs."
    mkinitcpio -P

    # Snapper configuration
    echo "Configuring Snapper."
    umount /.snapshots
    rm -r /.snapshots
    snapper --no-dbus -c root create-config /
    btrfs subvolume delete /.snapshots
    mkdir /.snapshots
    mount -a
    chmod 750 /.snapshots

    # Installing GRUB.
    echo "Installing GRUB on /boot."
    grub-install --target=x86_64-efi --efi-directory=/efi --bootloader-id=GRUB --modules="normal test efi_gop efi_uga search echo linux all_video gfxmenu gfxterm_background gfxterm_menu gfxterm loadenv configfile gzio part_gpt btrfs"

    # Creating grub config file.
    echo "Creating GRUB config file."
    grub-mkconfig -o /boot/grub/grub.cfg
EOF

# Update Snapper config
sed -i 's/QGROUP=""/QGROUP="1\/0"/' /mnt/etc/snapper/configs/root
sed -i 's/NUMBER_LIMIT="50"/NUMBER_LIMIT="10-35"/' /mnt/etc/snapper/configs/root
sed -i 's/NUMBER_LIMIT_IMPORTANT="10"/NUMBER_LIMIT_IMPORTANT="15-25"/' /mnt/etc/snapper/configs/root
sed -i 's/TIMELINE_LIMIT_HOURLY="10"/TIMELINE_LIMIT_HOURLY="5"/' /mnt/etc/snapper/configs/root
sed -i 's/TIMELINE_LIMIT_DAILY="10"/TIMELINE_LIMIT_DAILY="5"/' /mnt/etc/snapper/configs/root
sed -i 's/TIMELINE_LIMIT_WEEKLY="0"/TIMELINE_LIMIT_WEEKLY="2"/' /mnt/etc/snapper/configs/root
sed -i 's/TIMELINE_LIMIT_MONTHLY="10"/TIMELINE_LIMIT_MONTHLY="3"/' /mnt/etc/snapper/configs/root
sed -i 's/TIMELINE_LIMIT_YEARLY="10"/TIMELINE_LIMIT_YEARLY="0"/' /mnt/etc/snapper/configs/root

# Setting root password.
print "info" "Setting root password."
arch-chroot /mnt /bin/passwd

# Setting user password.
if [ -n "$username" ]; then
    print "info" "add user to wheel group."
    arch-chroot /mnt useradd -m -G wheel -s /bin/bash $username
    print "info" "grant sudo permission to wheel group."
    sed -i 's/# %wheel ALL=(ALL) ALL/%wheel ALL=(ALL) ALL/' /mnt/etc/sudoers
    print "info" "set user password"
    arch-chroot /mnt /bin/passwd $username
fi

# Install snap-pac-grub from the AUR
arch-chroot -u $username /mnt /bin/bash -e <<EOF
    mkdir -p /home/$username/snap-pac-grub
    cd /home/$username/snap-pac-grub
    # Install maximbaz PGP key
    sudo -u $username gpg --recv-keys EB4F9E5A60D32232BB52150C12C87A28FEAC6B20
    sudo -u $username curl -s "https://aur.archlinux.org/cgit/aur.git/plain/PKGBUILD?h=snap-pac-grub" -o ./PKGBUILD
    sudo -u $username makepkg -fsc
EOF

# Install snap-pac-grub to enable snapshots in the grub menu.
execute "pacstrap -U -G /mnt /mnt/home/$username/snap-pac-grub/*.tar.zst" "install snap-pac-grub."

# Tidy up
execute "rm -fr /mnt/home/$username/snap-pac-grub" "Remove temporary build files for snap-pac-grub."

# ZRAM configuration.
execute "cat > /mnt/etc/systemd/zram-generator.conf <<EOF
[zram0]
zram-fraction = 1
max-zram-size = 8192
EOF" "configure ZRAM."

# Enabling various services.
BTRFS_SCRUB="$(systemd-escape --template btrfs-scrub@.timer --path $BTRFS)"
execute "systemctl enable NetworkManager.service --root=/mnt" "enable NetworkManager service."
execute "systemctl enable bluetooth.service --root=/mnt" "enable bluetooth service."
execute "systemctl enable fstrim.timer --root=/mnt" "enable fstrim timer."
execute "systemctl enable $BTRFS_SCRUB --root=/mnt" "enable BTRFS scrub timer."
execute "systemctl enable snapper-timeline.timer --root=/mnt" "enable snapper-timeline timer."
execute "systemctl enable snapper-cleanup.timer --root=/mnt" "enable snapper-cleanup timer."

# Finishing up.
print "blue" "Arch Linux install complete!"
print "blue" "To continue tinkering: arch-chroot /mnt"
print "blue" "Otherwise reboot to srtart using the newly installed system."

# TODO: supplementary scripts?
# kde / gnome / sway etc.
# neovim + config
# rust / lsp
for script in "./post_install_scripts/"*.sh
do
	sh "$script" &
done
exit
