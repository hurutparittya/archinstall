#!/bin/bash
# Arch Linux auto installer script

# ask for user input
read -p "Target block device [ example: /dev/sda ]: " TARGET
read -p "SWAP size in relation to RAM [ example: 120 = 120% of RAM ]: " SWAPPERCENT
read -p "hostname: " HNAME
read -p "Name for your user account: " UNAME
echo -n "Password for the user account: "
read -s UPASSWORD
echo
echo -n "Password for the root account: "
read -s RPASSWORD
echo

# manually set language and time zone
LOCALES=("hu_HU.UTF-8 UTF-8" "en_US.UTF-8 UTF-8")
LOCALELANG="en_US.UTF-8"
KEYMAPLANG="hu"
TIMEZONE="/usr/share/zoneinfo/Europe/Budapest"

# set default values for fields not supplied by the user
[ -z "$TARGET" ] || [ ! -b "$TARGET" ] && exit
[ -z "$SWAPPERCENT" ] && SWAPPERCENT=0
[ -z "$HNAME" ] && HNAME="hostname"
[ -z "$UNAME" ] && UNAME="user"
[ -z "$UPASSWORD" ] && UPASSWORD="user"
[ -z "$RPASSWORD" ] && RPASSWORD="root"

# calculate swap partition size based on available RAM
SWAPSIZE=+$(free -m | awk -v swappercent="$SWAPPERCENT" 'NR==2 {print int($2*(swappercent/100))}')M

# enable ntp
timedatectl set-ntp true

# prepare the disk using fdisk
(
echo o  # clear the in memory partition table
echo n  # new partition
echo p  # primary partition
echo 1  # partition number 1
echo    # default - start at beginning of disk
echo +500M # 500 MB boot partition
if [ $SWAPPERCENT -ne 0 ]; then # if the swap size supplied by the user is not 0
    echo n  # new partition
    echo p  # primary partition
    echo 2  # partition number 2
    echo    # default - start at the end of previous partition
    echo $SWAPSIZE # end depending on the size supplied by the user
    echo n  # new partition
    echo p  # primary partition
    echo 3  # partition number 3
    echo    # start at the end of the swap partition
    echo    # end at the end of disk
else # if swap size is zero
    echo n  # new partition
    echo p  # primary partition
    echo 2  # partition number 2
    echo    # start at the end of the boot partition
    echo    # end at the end of disk
fi
echo a # make a partition bootable
echo 1 # bootable partition is partition 1
echo p # print the in-memory partition table
echo w # write the changes
echo q # quit
) | fdisk -w always $TARGET

# make the filesystem and swap if applicable
mkfs.ext4 -F ${TARGET}p1
if [ $SWAPPERCENT -ne 0 ]; then
    mkswap ${TARGET}p2
    swapon ${TARGET}p2
    mkfs.ext4 -F ${TARGET}p3
else
    mkfs.ext4 -F ${TARGET}p2
fi

# make sure nothing is mounted on /mnt
umount -R /mnt

# mount the boot and root partitions
if [ $SWAPPERCENT -ne 0 ]; then
    mount ${TARGET}p3 /mnt
else
    mount ${TARGET}p2 /mnt
fi
mkdir /mnt/boot
mount ${TARGET}p1 /mnt/boot

# install the Arch base and some useful packages
pacstrap /mnt base base-devel linux linux-firmware

# generate fstab based on current mount points
genfstab -U /mnt >> /mnt/etc/fstab

# write some configs to the mounted filesystem (keymap, locale, hostname, timezone)
for ((i = 0; i < ${#LOCALES[@]}; i++))
do
    echo "${LOCALES[$i]}" >> /mnt/etc/locale.gen
done
echo KEYMAP=${KEYMAPLANG} >> /mnt/etc/vconsole.conf
echo LANG=${LOCALELANG} >> /mnt/etc/locale.conf
echo $HNAME >> /mnt/etc/hostname

# enter chroot environment
(
    echo locale-gen                                # generate locales
    echo ln -sf ${TIMEZONE} /etc/localtime         # link the timezone to the config directory 
    echo hwclock --systohc                         # copy system to hardware clock     
    echo pacman -S --noconfirm networkmanager grub git # install the networkmanager, git and grub packages
    echo systemctl enable NetworkManager           # enable the NetworkManager service
    echo grub-install --target=i386-pc $TARGET     # install the grub bootloader
    echo grub-mkconfig -o /boot/grub/grub.cfg      # make grub config
    echo passwd root                               # change the root password to one specified by the user
    echo $RPASSWORD
    echo $RPASSWORD
    echo "echo '%wheel ALL=(ALL) NOPASSWD: ALL' | sudo EDITOR='tee -a' visudo" # allow users in the wheel group to run any command without password
    echo useradd -G wheel,audio,video -m $UNAME    # create the user
    echo passwd $UNAME                             # set a password for the user
    echo $UPASSWORD
    echo $UPASSWORD

) | arch-chroot /mnt
