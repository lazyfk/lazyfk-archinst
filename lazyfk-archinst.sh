#!/usr/bin/env bash

clear

micro=''
keyboard=''
device=''
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
		echo "yup there is an internet connection" && sleep 5
	else
		no_net
	fi
}
time_set(){
	
	timedatectl set-ntp true
	"setting up time service"
	timedatectl status
	sleep 4
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
		echo "MBR will be done at later date"
		exit 0
	fi
}
part_disk(){

	device=$1;sel_dev="/dev/$device"
	echo "wiping any existing partitions on selected disk and etc."
	wipefs -af "$sel_dev"
	sgdisk -Z "$sel_dev"
	sgdisk -n 1::+"$boot_size" -t 1:ef00 -c 1:EFI "$sel_dev"
	sgdisk -n 2::+"$swap_size" -t 2:8200 -c 2:SWAP "$sel_dev"
	sgdisk -n 3::+"$root_size" -t 3:8300 -c 3:ROOT "$sel_dev"
	sgdisk -n 4 -c 4:HOME "$sel_dev"

	# swap below to include ssd,use lsblk -o NAME -r "$sel_dev" | grep -E ""$device"p?1" to catch partition names
	bootpart="/dev/$(lsblk -o NAME -r "sel_dev" | grep -E ""$device"p?1")"
	swappart="/dev/$(lsblk -o NAME -r "sel_dev" | grep -E ""$device"p?2")"
	rootpart="/dev/$(lsblk -o NAME -r "sel_dev" | grep -E ""$device"p?3")"
	homepart="/dev/$(lsblk -o NAME -r "sel_dev" | grep -E ""$device"p?4")"
	mkfs.fat -F32 "$bootpart"
	mkswap "$swappart"
	swapon "$swappart"
	mkfs.ext4 "$rootpart"
	mkfs.ext4 "$homepart"

	mount "$rootpart" /mnt
	mkdir -p /mnt/boot/efi
	mount "$bootpart" /mnt/boot/efi
	mkdir /mnt/home
	mount "$homepart" /mnt/home
}
bare_minimum(){
	pacstrap /mnt base base-devel linux $micro linux-headers linux-firmware vim networkmanager man-db 
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
install_grub(){
	clear
	echo "installing grub"
	arch-chroot /mnt pacman -S grub os-prober efibootmgr --noconfirm
	arch-chroot /mnt grub-install /dev/"$device" --target=x86_64-efi --bootloader-id=GRUB --efi-directory=/boot/efi
	arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg
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
	install_grub
	start_services
else
	exit 0
fi
