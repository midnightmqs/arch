# loadkeys us
# setfont ter-132
#
#
# iwctl --passphrase [passphrase] station [name] connect [SSID]
#
#
# iwctl
# device list
# device [name] set-property Powered on
# station [name] scan
# station [name] get-networks
# station [name] connect [SSID]


###############################################
# INSTALL CONFIG                              #
############################################### 
hostname=magnesium
username=midnight
user_password=password
root_password=password

disk=/dev/nvme0n1
use_btrfs=true
use_encryption=true
encryption_password=password
cryptroot="${hostname}_root"

timezone=Europe/Budapest
locale="en_US.UTF-8 UTF-8"
language="en_US.UTF-8"
keymap=us

bootloader_id="Arch Linux"

ucode=intel

install_display=true
display_drivers="mesa vulkan-intel intel-media-driver"

configure_battery=true


###############################################
# UEFI CHECK                                  #
############################################### 
if [ ! -d /sys/firmware/efi ]; then
    echo "Error: This platform is not UEFI." >&2
    exit 1
else
    echo "UEFI detected. Continuing..."
fi


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


###############################################
# SETUP DISK                                  #
###############################################
echo "Setting up ${disk}..."

cat <<EOGDISK | gdisk $disk
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
mkfs.fat -F32 $(get_partition 1)

if [ "$use_encryption" = true ]; then
    echo -e "\tEnabling encryption..."

    cat <<EOCRYPT | cryptsetup luksFormat $(get_partition 2)
YES
$encryption_password
$encryption_password
EOCRYPT

    echo -e "\tOpening cryptroot... (${cryptroot})"

    echo "$encryption_password" | cryptsetup luksOpen $(get_partition 2) "$cryptroot"
    root_partition="/dev/mapper/$cryptroot"
else
    echo -e "\tEncryption disabled."
    root_partition="$(get_partition 2)"
fi

if [ "$use_btrfs" = true ]; then
    echo -e "\tEnabling BTRFS..."
    echo -e "\tFormatting BTRFS partition..."

    mkfs.btrfs "$root_partition"

    echo -e "\tMounting BTRFS partiton..."

    mount "$root_partition" /mnt
    cd /mnt
    
    echo -e "\tCreating subvolumes..."
    btrfs subvolume create @
    btrfs subvolume create @home
    
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

    mkfs.ext4 "$root_partition"

    echo -e "\tMounting ext4 partition..."

    mount "$root_partition" /mnt
    mkdir /mnt/home
fi

echo "Mounting ESP..."
mkdir /mnt/boot
mount $(get_partition 1) /mnt/boot

echo "Setting up ${disk} DONE"


###############################################
# START THE INSTALLATION                      #
############################################### 
echo "Running pacstrap..."
pacstrap /mnt base linux linux-firmware linux-headers vim "${ucode}-ucode" $([ "$use_btrfs" = true ] && echo btrfs-progs) --quiet
echo "Running pacstrap DONE"

echo "Generating fstab..."
genfstab -U /mnt >> /mnt/etc/fstab
echo "Generating fstab DONE"


###############################################
# START CHROOT                                #
############################################### 
{
###############################################
# SETUP TIME                                  #
############################################### 
echo "Setting system time..."
ln -sf /usr/share/zoneinfo/$timezone /etc/localtime
hwclock --systohc
timedatectl set-ntp true
echo "Setting system time DONE"


###############################################
# LANGUAGE CONFIGURATION                      #
############################################### 
echo "Setting language and locales..."
echo "$locale" >> /etc/locale.gen
locale-gen

echo "LANG=$language" > /etc/locale.conf
echo "KEYMAP=$keymap" > /etc/vconsole.conf
echo "Setting language and locales DONE"


###############################################
# CREATE HOSTNAME AND HOSTS FILE              #
############################################### 
echo "Setting hostname and hosts file..."
echo "$hostname" > /etc/hostname

echo "127.0.0.1 localhost" >> /etc/hosts
echo "::1 localhost" >> /etc/hosts
echo "127.0.1.1 ${hostname}.localdomain $hostname" >> /etc/hosts
echo "Setting hostname and hosts file DONE"


###############################################
# CONFIGURE PACMAN                            #
############################################### 
echo "Configuring pacman..."
sed -i '/ParallelDownloads = 5/s/^#//g' /etc/pacman.conf
echo "Configuring pacman DONE"


###############################################
# CREATE AND CONFIGURE THE USER               #
############################################### 
echo "Setting up the user..."

echo -e "\tRunning pacman..."
pacman -S base-devel go sed git xdg-utils xdg-user-dirs sudo --no-confirm --quiet

echo -e "\tCreating user... (${username})"
useradd -m -g users -G wheel $username

cat <<EOUSERPASS | passwd $username
$user_password
$user_password
EOUSERPASS

echo -e "\tAdding ${username} to sudoers..."
sed -i '/%wheel ALL=(ALL:ALL) ALL/s/^# //g' /etc/sudoers

echo -e "\tSetting up user xdg directories and installing yay..."
su $username <<EOSU
git config --global init.defautBranch main

cd ~
xdg-user-dirs-update

mkdir apps
cd apps

git clone https://aur.archlinux.org/yay.git

cd yay

echo "$user_password" | makepkg -si --noconfirm --quiet

exit
EOSU

echo "Setting up the user DONE"


###############################################
# INSTALL GRUB                                #
############################################### 
echo "Installing GRUB..."

echo -e "\tRunning pacman..."
pacman -S grub efibootmgr dosfstools mtools $([ "$use_btrfs" = true ] && echo grub-btrfs) --no-confirm --quiet

echo -e "\tRunning GRUB install..."
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id="$bootloader_id" 

echo -e "\tConfiguring GRUB..."
grub-mkconfig -o /boot/grub/grub.cfg

echo "Installing GRUB DONE"


###############################################
# CONFIGURE INITCPIO                          #
############################################### 
echo "Setting up initial RAM disk..."

echo -e "\tConfiguring mkinitcpio..."
[ "$use_btrfs" = true ] && sed -i "s/MODULES=(/MODULES=(btrfs /" /etc/mkinitcpio.conf
[ "$use_encryption" = true ] && sed -i "s/filesystems/encrypt filesystems/" /etc/mkinitcpio.conf

echo -e "\tRunning mkinitcpio..."
mkinitcpio -p linux

echo "Setting up initial RAM disk DONE"


###############################################
# CONFIGURE GRUB                              #
###############################################
echo "Reconfiguring GRUB..."
if [ "$use_encryption" = true ]; then
    cryptdevice_uuid=$(blkid -s UUID -o value $(get_partition 2))
    sed -i "s|^GRUB_CMDLINE_LINUX=.*|GRUB_CMDLINE_LINUX=\"cryptdevice=UUID=$cryptdevice_uuid:$cryptroot root=/dev/mapper/$cryptroot\"|" /etc/default/grub
fi

grub-mkconfig -o /boot/grub/grub.cfg

echo "Reconfiguring GRUB DONE"


###############################################
# CONFIGURE BATTERY                           #
############################################### 
if [ "$configure_battery" = true ]; then
    echo "Configuring battery..."
    pacman -S tlp --no-confirm --quiet

    echo "START_CHARGE_THRESH_BAT1=85" >> /etc/tlp.conf
    echo "STOP_CHARGE_THRESH_BAT1=90" >> /etc/tlp.conf

    systemctl enable tlp > /dev/null

    echo "Configuring battery DONE"
fi


###############################################
# CONFIGURE NETWORKING                        #
############################################### 
echo "Setting up networking..."

echo -e "\tRunning pacman..."
pacman -S networkmanager dialog bluez bluez-utils openssh iptables-nft firewalld iwd --no-confirm --quiet

echo -e "\tConfiguring NetworkManager with iwd as the wifi backend..."
echo "[device]" >> /etc/NetworkManager/conf.d/wifi_backend.conf
echo "wifi.backend=iwd" >> /etc/NetworkManager/conf.d/wifi_backend.conf

echo -e "\tSetting nameservers..."
echo "nameserver 1.1.1.1" >> /etc/resolv.conf
echo "nameserver 1.0.0.1" >> /etc/resolv.conf
echo "nameserver 2606:4700:4700:1111" >> /etc/resolv.conf
echo "nameserver 2606:4700:4700:1001" >> /etc/resolv.conf

echo -e "\tEnabling services..."
systemctl enable NetworkManager > /dev/null
systemctl enable bluetooth > /dev/null
systemctl enable firewalld > /dev/null

echo "Setting up networking DONE"


###############################################
# INSTALL BASIC UTILITIES                     #
############################################### 
echo "Installing basic utilities..."
pacman -S curl wget zip unzip tmux tar less diff grep screen pacseek htop fastfetch imagemagick jq man-db man-pages plocate rsync --no-confirm --quiet
echo "Installing basic utilities DONE"


###############################################
# SETUP DISPLAY                               #
############################################### 
echo "Setting up display and audio..."

if [ "$install_display" = true ]; then
    # Setup X and drivers
    pacman -S xorg xorg-server $display_drivers --no-confirm --quiet

    # Setup audio
    pacman -S alsa-utils pipewire wireplumber pipewire-alsa pipewire-pulse pipewire-jack pavucontrol --no-confirm --quiet
fi

echo "Setting up display and audio DONE"


###############################################
# EXIT CHROOT                                 #
############################################### 
exit


} | arch-chroot /mnt


##########################################
# FINISH THE INSTALLATION                #
########################################## 
echo "INSTALLATION FINISHED | Rebooting..."
sleep 5

reboot
