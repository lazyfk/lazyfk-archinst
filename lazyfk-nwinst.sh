#!/usr/bin/env bash

micro=''
keyboard=''
device=''
encname=''
lvmuuid=''
boot_size=512M
root_size=10G
swap_size=2G
timezone="Europe/Warsaw"
locale="pl_PL.UTF-8"

efi_boot(){
    ($(ls /sys/firmware/efi/efivars &>/dev/null) && return 0) || return 1
}
check_net(){
    clear
    echo "checking network connection"
    if $(ping -c 3 archlinux.org &>/dev/null);then
        echo "yay there is connection to the internet"
    else
        echo "please check your network connection"
        exit 1
    fi
}
microcode(){
    cpu=$(grep vendor_id /proc/cpuinfo)
    if [[ $cpu == *"GenuineIntel"* ]];then
        micro="intel-ucode"
    else
        micro="amd-ucode"
    fi
}
set_keymap(){
    loadkeys pl2
}
select_disk(){
    clear
    echo "listing aviable devices"
    lsblk | grep disk
    read device
    if $(efi_boot);
    then
        part_disk "$device"
    else
        echo "this script does not work without UEFI"
        exit 0
    fi
}
part_disk(){
    device=$1;sel_dev="/dev/$device"
    echo "btrfs or ext4?"
    select fssel in ext4 btrfs;do
        case $fssel in
            ext4)
                fs=ext4
                echo "selected $fs"
                break
                ;;
            btrfs)
                fs=btrfs
                echo "selected $fs"
                break
                ;;
            *)
                echo "select filesystem"
                ;;
        esac
    done
    echo "do you want to encrypt $dev (y/n) ?"
    read prompt
    if [ "$prompt" != "${prompt#[Yy]}" ]; then
      if [ "$fs" == "ext4" ]; then
          echo "wiping any existing partitions on selected disk and etc."
          dd if=/dev/zero of=/dev/"$device" bs=512 count=1
          sgdisk -n 1::+"$boot_size" -t 1:ef00 -c 1:EFI "$sel_dev"
          sgdisk -n 2 -t 2:8e00 -c 2:LVM "$sel_dev"
          bootpart="/dev/$(lsblk -o NAME -r "$sel_dev" | grep -E ""$device"p?1")"
          pvpart="/dev/$(lsblk -o NAME -r "$sel_dev" | grep -E ""$device"p?2")"
          echo "encrypting lvm partition"
          cryptsetup -y -v --use-random luksFormat "$pvpart"
          echo "provide name of this partition"
          read encname
          echo "opening encrypted partition"
          cryptsetup luksOpen "$pvpart" "$encname"
          pvcreate /dev/mapper/"$encname"
          vgcreate vg0 /dev/mapper/"$encname"
          lvcreate -L "$swap_size" vg0 -n swap
          lvcreate -L "$root_size" vg0 -n root
          lvcreate -l 100%FREE vg0 -n home
          mkfs.fat -F32 "$bootpart"
          mkswap /dev/vg0/swap
          swapon /dev/vg0/swap
          mkfs.ext4 /dev/vg0/root
          mkfs.ext4 /dev/vg0/home
          mount /dev/vg0/root /mnt
          mkdir /mnt/efi
          mount "$bootpart" /mnt/efi
          mkdir /mnt/home
          mount /dev/vg0/home /mnt/home
      else
          echo "wiping any existing partitions on selected disk and etc."
          dd if=/dev/zero of=/dev/"$device" bs=512 count=1
          sgdisk -n 1::+"$boot_size" -t 1:ef00 -c 1:EFI "$sel_dev"
          sgdisk -n 2 -t 2:8300 -c 2:BTRFS "$sel_dev"
          bootpart="/dev/$(lsblk -o NAME -r "$sel_dev" | grep -E ""$device"p?1")"
          pvpart="/dev/$(lsblk -o NAME -r "$sel_dev" | grep -E ""$device"p?2")"
          echo "encrypting BTRFS partition"
          cryptsetup -y -v --use-random luksFormat "$pvpart"
          echo "provide name of this partition"
          read encname
          echo "opening encrypted partition"
          cryptsetup luksOpen "$pvpart" "$encname"
          mkfs.btrfs /dev/mapper/"$encname"
          mount /dev/mapper/"$encname" /mnt
          btrfs sub create /mnt/@
          btrfs sub create /mnt/@home
          btrfs sub create /mnt/@swap
          btrfs sub create /mnt/@var/cache
          btrfs sub create /mnt/@var/log
          btrfs filesystem mkswapfile -s "$swap_size" /mnt/swap
          umount /mnt
          mount -o defaults,noatime,autodefrag,compress=zstd 0 0 subvol=@ /dev/mapper/"$encname" /mnt
          mkdir -p /mnt/{home,var/cache,var/log}
          mount -o defaults,noatime,autodefrag,compress=zstd 0 0 subvol=@home /dev/mapper/"$encname" /mnt/home
          mount -o defaults,noatime,autodefrag,compress=zstd 0 0 subvol=@cache /dev/mapper/"$encname" /mnt/var/cache
          mount -o defaults,noatime,autodefrag,compress=zstd 0 0 subvol=@log /dev/mapper/"$encname" /mnt/var/log
          mount -o defaults,noatime 0 0 subvol=@swap /dev/mapper/"$encname" /mnt/swap
          swapon /mnt/swap
          mkfs.fat -F32 "$bootpart"
          mkdir /mnt/efi
          mount "$bootpart" /mnt/efi
         fi
     else
         if [ "$fs" == "ext4" ]; then
             sel_dev="/dev/$device"
             echo "wiping any existing partitions on selected disk and etc."
             dd if=/dev/zero of=/dev/"$device" bs=512 count=1
             sgdisk -n 1::+"$boot_size" -t 1:ef00 -c 1:EFI "$sel_dev"
             sgdisk -n 2::+"$swap_size" -t 2:8200 -c 2:SWAP "$sel_dev"
             sgdisk -n 3::+"$root_size" -t 3:8300 -c 3:ROOT "$sel_dev"
             sgdisk -n 4 -c 4:HOME "$sel_dev"
             # swap below to include ssd,use lsblk -o NAME -r "$sel_dev" | grep -E ""$device"p?1" to catch partition names
             bootpart="/dev/$(lsblk -o NAME -r "$sel_dev" | grep -E ""$device"p?1")"
             swappart="/dev/$(lsblk -o NAME -r "$sel_dev" | grep -E ""$device"p?2")"
             rootpart="/dev/$(lsblk -o NAME -r "$sel_dev" | grep -E ""$device"p?3")"
             homepart="/dev/$(lsblk -o NAME -r "$sel_dev" | grep -E ""$device"p?4")"
             mkfs.fat -F32 "$bootpart"
             mkswap "$swappart"
             swapon "$swappart"
             mkfs.ext4 "$rootpart"
             mkfs.ext4 "$homepart"
             mount "$rootpart" /mnt
             mkdir -p /mnt/efi
             mount "$bootpart" /mnt/efi
             mkdir /mnt/home
             mount "$homepart" /mnt/home
         else
             echo "wiping any existing partitions on selected disk and etc."
             dd if=/dev/zero of=/dev/"$device" bs=512 count=1
             sgdisk -n 1::+"$boot_size" -t 1:ef00 -c 1:EFI "$sel_dev"
             sgdisk -n 2 -t 2:8300 -c 2:BTRFS "$sel_dev"
             bootpart="/dev/$(lsblk -o NAME -r "$sel_dev" | grep -E ""$device"p?1")"
             pvpart="/dev/$(lsblk -o NAME -r "$sel_dev" | grep -E ""$device"p?2")"
             mkfs.btrfs "$pvpart"
             mount "$pvpart" /mnt
             btrfs sub create /mnt/@
             btrfs sub create /mnt/@/home
             btrfs sub create /mnt/@/swap
             btrfs sub create /mnt/@/var/cache
             btrfs sub create /mnt/@/var/log
             btrfs filesystem mkswapfile -s "$swap_size" /mnt/swap
             umount /mnt
             mount -o defaults,noatime,autodefrag,compress=zstd 0 0 subvol=@ "$pvpart" /mnt
             mkdir -p /mnt/{home,var/cache,var/log}
             mount -o defaults,noatime,autodefrag,compress=zstd 0 0 subvol=@home "$pvpart" /mnt/home
             mount -o defaults,noatime,autodefrag,compress=zstd 0 0 subvol=@cache "$pvpart" /mnt/var/cache
             mount -o defaults,noatime,autodefrag,compress=zstd 0 0 subvol=@log "$pvpart" /mnt/var/log
             mount -o defaults,noatime 0 0 subvol=@swap "$pvpart" /mnt/swap
             swapon /mnt/swap
             mkfs.fat -F32 "$bootpart"
             mkdir /mnt/efi
             mount "$bootpart" /mnt/efi
         fi
    fi
}
bare_minimum(){
	pacstrap /mnt base base-devel linux $micro linux-headers linux-firmware vim networkmanager man-db lvm2 efitools sbctl
}
create_fstab(){
	genfstab -U /mnt >> /mnt/etc/fstab
}
set_timezone(){
	clear
	echo "setting up specifed timezone"
	arch-chroot /mnt ln -sf /usr/share/zoneinfo/"$timezone" /etc/localtime
	arch-chroot /mnt hwclock --systohc
}
set_hooks(){
	arch-chroot /mnt sed -i "s/HOOKS=(base udev autodetect modconf block filesystems keyboard fsck)/HOOKS=(base systemd autodetect keyboard sd-vconsole modconf block sd-encrypt lvm2 filesystems fsck)/g" /etc/mkinitcpio.conf
	cat > /mnt/etc/mkinitcpio.d/linux.preset <<EOF
    # mkinitcpio preset file for the 'linux' package

    ALL_config="/etc/mkinitcpio.conf"
    ALL_kver="/boot/vmlinuz-linux"
    ALL_microcode=(/boot/*-ucode.img)

    PRESETS=('default' 'fallback')

    #default_image="/boot/initramfs-linux.img"
    default_uki="esp/EFI/Linux/archlinux-linux.efi"
    default_options="--splash=/usr/share/systemd/bootctl/splash-arch.bmp"

    #fallback_image="/boot/initramfs-linux-fallback.img"
    fallback_uki="esp/EFI/Linux/archlinux-linux-fallback.efi"
    fallback_options="-S autodetect"
EOF
    install_bootloader
arch-chroot /mnt mkinitcpio -p linux
}
set_locale(){
	clear
	echo "setting up locale"
	arch-chroot /mnt sed -i "s/#$locale/$locale/g" /etc/locale.gen
	arch-chroot /mnt sed -i "s/#en_US.UTF-8/en_US.UTF-8/g" /etc/locale.gen
	arch-chroot /mnt locale-gen
	echo "LANG=$locale" > /mnt/etc/locale.conf
	export LANG="$locale"

}
set_hostname(){
	echo "please provide an hostname: "; read namevar
	echo "$namevar" > /mnt/etc/hostname

	cat > /mnt/etc/hosts <<EOF
	127.0.0.1	localhost
	::1		localhost
	127.0.1.1	$namevar.localdomain	$namevar
EOF
}
set_pass(){
	clear
	echo "provide root password: "
	arch-chroot /mnt passwd
}
create_user(){
	clear
	echo "provide username: "; read user
	arch-chroot /mnt useradd -mG wheel "$user"
	arch-chroot /mnt sed -i 's/# %wheel/%wheel/g' /etc/sudoers
	arch-chroot /mnt sed -i 's/# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/g' /etc/sudoers
	arch-chroot /mnt sed -i 's/%wheel ALL=(ALL:ALL) NOPASSWD: ALL/# %wheel ALL=(ALL:ALL) NOPASSWD: ALL/g' /etc/sudoers
	echo "provide password for $user"
	arch-chroot /mnt passwd "$user"
}
install_bootloader(){
	clear
	echo "installing bootloader"
	arch-chroot /mnt pacman -S os-prober efibootmgr --noconfirm
	arch-chroot /mnt bootctl install
}
start_services(){
	arch-chroot /mnt systemctl enable NetworkManager.service
}

echo "installing arch yay"
echo "Please confirm that you know what this script do (y/n)"
read prompt
if [ "$prompt" != "${prompt#[Yy]}" ]; then
	check_connection
	set_keymap
	select_disk
	microcode
	bare_minimum
	create_fstab
	set_timezone
	set_locale
	set_hostname
	set_pass
	create_user
	set_hooks
	start_services
else
	exit 0
fi
