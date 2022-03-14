#!/usr/bin/env bash

clear

micro=''
keyboard=''
device=''
crname=''
lvmuuid=''
boot_size=512M
root_size=10G
swap_size=2G
timezone="Europe/Warsaw"
locale="pl_PL.UTF-8"
efi_boot(){
	($(ls /sys/firmware/efi/efivars &>/dev/null) && return 0) || return 1
}
set_kb(){
	
	# setting up keyboard layout
	read -r -p "Insert your preferred keyboard layout(like us,uk,de-latin1,pl2 or smth ): " keyboard
	loadkeys $keyboard
}
no_net(){

	clear
	echo "no network connection check your wifi or cable"
	exit 1

}
microcode(){
	cpu=$(grep vendor_id /proc/cpuinfo)
	if [[ $cpu == *"GenuineIntel"* ]];then
		micro="intel-ucode"
	else
		micro="amd-ucode"
	fi

}
check_connection(){

	clear
	echo " checking connection"
	if $(ping -c 3 archlinux.org &>/dev/null);then 
		echo "yup there is an internet connection"
	else
		no_net
	fi
}
time_set(){
	
	timedatectl set-ntp true
	"setting up time service"
	timedatectl status
}
select_disk(){
	clear
	echo "here are listed aviable devices, choose where it should be installed"
	lsblk | grep disk
	read device
	if $(efi_boot);
	then
		echo "going with EFI/GPT"
		part_disk "$device"
	else
		echo "turn on EFI in your BIOS"
		exit 0
	fi
}
part_disk(){

	device=$1;sel_dev="/dev/$device"
	echo "wiping any existing partitions on selected disk and etc."
	dd if=/dev/zero of=/dev/"$device" bs=512 count=1
	sgdisk -n 1::+"$boot_size" -t 1:ef00 -c 1:EFI "$sel_dev"
	sgdisk -n 2 -t 2:8e00 -c 2:LVM "$sel_dev"
	bootpart="/dev/$(lsblk -o NAME -r "$sel_dev" | grep -E ""$device"p?1")"
	pvpart="/dev/$(lsblk -o NAME -r "$sel_dev" | grep -E ""$device"p?2")"
	echo "encrypting lvm partition"
	cryptsetup -y -v --use-random luksFormat "$pvpart"
	echo "provide name of this partition"
	read crname
	echo "opening encrypted partition"
	cryptsetup luksOpen "$pvpart" "$crname"
	pvcreate /dev/mapper/"$crname"
	vgcreate vg0 /dev/mapper/"$crname"
	lvcreate -L "$swap_size" vg0 -n swap
	lvcreate -L "$root_size" vg0 -n root
	lvcreate -l 100%FREE vg0 -n home
	mkfs.fat -F32 "$bootpart"
	mkswap /dev/vg0/swap
	swapon /dev/vg0/swap
	mkfs.ext4 /dev/vg0/root
	mkfs.ext4 /dev/vg0/home

	mount /dev/vg0/root /mnt
	mkdir /mnt/boot
	mount "$bootpart" /mnt/boot
	mkdir /mnt/home
	mount /dev/vg0/home /mnt/home
}
bare_minimum(){
	pacstrap /mnt base base-devel linux $micro linux-headers linux-firmware vim networkmanager man-db lvm2 xdg-utils xdg-user-dirs efitools sbctl
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
	echo "KEYMAP=$keyboard" > /mnt/etc/vconsole.conf
	echo "FONT=lat2-16" >> /mnt/etc/vconsole.conf
	echo "FONT_MAP=8859-2" >> /mnt/etc/vconsole.conf
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
	arch-chroot /mnt bootctl --path=/boot install
	lvmuuid="$(blkid -s UUID -o value "$pvpart")"
	touch /mnt/boot/loader/entries/arch.conf
	cat > /mnt/boot/loader/entries/arch.conf <<EOF
	title	Arch Linux
	linux	/vmlinuz-linux
	initrd	/$micro.img
	initrd	/initramfs-linux.img
	options	rd.luks.name=$lvmuuid=$crname root=/dev/vg0/root rw
EOF
	touch /mnt/boot/loader/loader.conf
	cat > /mnt/boot/loader/loader.conf <<EOF
	default arch
	timeout 5
	console-mode max
	editor no
EOF
	arch-chroot /mnt bootctl --path=/boot update
}
start_services(){
	arch-chroot /mnt systemctl enable NetworkManager.service
}

echo "installing arch yay"
echo "Please confirm that you know what this script do (y/n)"
read prompt
if [ "$prompt" != "${prompt#[Yy]}" ]; then
	check_connection
	set_kb
	time_set
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
	install_bootloader
	start_services
else
	exit 0
fi
