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
