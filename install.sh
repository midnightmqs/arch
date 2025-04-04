source ./config.sh

###############################################
# UEFI CHECK                                  #
############################################### 
if [ ! -d /sys/firmware/efi ]; then
    echo "Error: This platform is not UEFI." >&2
    exit 1
else
    echo "UEFI detected. Continuing..."
fi

sleep 5


###############################################
# UTILITY FUNCTIONS                           #
############################################### 
get_partition() {
    local part_num=$1
    if [[ $disk =~ [0-9]$ ]]; then
        echo "${disk}p${part_num}"
    else
        echo "${disk}${part_num}"
    fi
}


###############################################
# SET INSTALLER TIMEZONE                      #
############################################### 
echo "Setting system time..."

timedatectl set-timezone $timezone
hwclock --systohc

echo "Setting system time DONE"
sleep 5


###############################################
# SETUP DISK                                  #
###############################################
echo "Setting up ${disk}..."

cat <<EOGDISK | gdisk $disk > /dev/null
o
Y
n
1

+1G
ef00
n
2


8300
w
Y
EOGDISK

echo -e "\tFormatting ESP..."
mkfs.fat -F32 $(get_partition 1) > /dev/null

if [ "$use_encryption" = true ]; then
    echo -e "\tEnabling encryption..."
    echo -n "$encryption_password" | cryptsetup luksFormat --type luks2 $(get_partition 2) > /dev/null

    echo -e "\tOpening cryptroot... ($cryptroot)"
    echo -n "$encryption_password" | cryptsetup luksOpen $(get_partition 2) $cryptroot > /dev/null

    root_partition="/dev/mapper/$cryptroot"
else
    echo -e "\tEncryption disabled."
    root_partition="$(get_partition 2)"
fi

if [ "$use_btrfs" = true ]; then
    echo -e "\tEnabling BTRFS..."
    echo -e "\tFormatting BTRFS partition..."

    mkfs.btrfs "$root_partition" > /dev/null

    echo -e "\tMounting BTRFS partiton..."

    mount "$root_partition" /mnt
    cd /mnt
    
    echo -e "\tCreating subvolumes..."
    btrfs subvolume create @ > /dev/null
    btrfs subvolume create @home > /dev/null
    
    cd /

    echo -e "\tUnmounting BTRFS partiton..."
    umount /mnt
    
    echo -e "\tMounting subvolumes..."
    mount -o noatime,compress=zstd,space_cache=v2,discard=async,subvol=@ "$root_partition" /mnt
    mkdir /mnt/home
    mount -o noatime,compress=zstd,space_cache=v2,discard=async,subvol=@home "$root_partition" /mnt/home
else
    echo -e "\tBTRFS disabled."
    echo -e "\tFormatting ext4 partition..."

    mkfs.ext4 "$root_partition" > /dev/null

    echo -e "\tMounting ext4 partition..."

    mount "$root_partition" /mnt
    mkdir /mnt/home
fi

echo "Mounting ESP..."
mkdir /mnt/boot
mount $(get_partition 1) /mnt/boot

echo "Setting up ${disk} DONE"
sleep 5


###############################################
# START THE INSTALLATION                      #
############################################### 
echo "Running pacstrap..."

pacstrap /mnt base linux linux-firmware linux-headers vim "${ucode}-ucode" $([ "$use_btrfs" = true ] && echo btrfs-progs)

echo "Running pacstrap DONE"

echo "Generating fstab..."

genfstab -U /mnt >> /mnt/etc/fstab

echo "Generating fstab DONE"
sleep 5


###############################################
# START CHROOT                                #
############################################### 
clear
echo "Entering arch-chroot..."
sleep 5

cp ./config.sh /mnt/root/config.sh 
cp ./chroot.sh /mnt/root/chroot.sh 
chmod +x /mnt/root/chroot.sh

arch-chroot /mnt /bin/bash /root/chroot.sh
