#!/usr/bin/env bash
# Step 1: Ask for the path to install.wim
# Then, use WimInfo and ask the user for which option to install

print_usage() {
    echo "Windows2Go Drive Creator"
    echo "This script helps create a bootable Windows drive using a .wim file"
    echo "Please ensure you have your USB drive and Windows install ready."
    echo "https://www.microsoft.com/en-ca/software-download/windows11"
}

# Verify running with root
if [ "$EUID" -ne 0 ]; then 
    echo "This script requires root privileges to run."
    exit 1
fi

# Display usage
print_usage

# Get .wim file path
read -p "Please enter the path to install.wim: " wim_path

# Validate file exists
# First, strip any leading and trailing '
wim_path="${wim_path//\'/}"
# wim_path="\"${wim_path}\""
if [ ! -f "$wim_path" ]; then
    echo "Error: File '$wim_path' not found!"
    exit 1
fi

# Get Windows editions
echo "Available Windows editions:"
wiminfo "$wim_path" | grep "Index:" -A 1

# Get user selection
read -p "Enter the index number of the Windows edition to install: " edition_index

# Step 2: Ask the user for the target USB Drive, and make sure to verify they've selected the correct one.
# We're going to make sure it's at least 32GB, then make a 128MB UEFI partition
# Then the rest of it is going to be NTFS
# Then we're going to wimapply to the NTFS partition

echo "Available drives:"
lsblk -d

read -p "Enter the drive path (e.g. /dev/sdb): " drive_path

echo "WARNING: This will erase ALL data on $drive_path"
read -p "Are you sure you want to continue? (y/n) " confirm

if [[ ! $confirm =~ ^[Yy]$ ]]; then
    echo "Operation cancelled"
    exit 1
fi

# Check drive size (minimum 32GB)
size_bytes=$(blockdev --getsize64 "$drive_path")
min_size=$((32 * 1024 * 1024 * 1024)) # 32GB in bytes

if [ "$size_bytes" -lt "$min_size" ]; then
    echo "Error: Drive must be at least 32GB"
    exit 1
fi

# Make Drive GPT
echo "Creating GPT partition table..."
parted -s "$drive_path" mklabel gpt

# Create 128MB EFI Partition
echo "Creating EFI partition..."
parted -s "$drive_path" mkpart EFI fat32 1MiB 129MiB
parted -s "$drive_path" set 1 esp on

# And then fill the rest of the disk with an NTFS partition 
echo "Creating Windows partition..."
parted -s "$drive_path" mkpart Windows ntfs 129MiB 100%

# Now lets get Windows done up
# WimApply the selected version of Windows to the Partition

echo "Applying Windows Image... (This may take a while)"
wimapply "$wim_path" "$edition_index" ${drive_path}2
echo "Setting up Bootloader..."
mkdir -p /tmp/mnt/windows
mkdir -p /tmp/mnt/efi
mount "$drive_path"1 /tmp/mnt/efi
mount "$drive_path"2 /tmp/mnt/windows

# Lets start by making the directory structure on the EFI partition
mkdir -p /tmp/mnt/efi/EFI/Microsoft/Boot
mkdir -p /tmp/mnt/efi/EFI/Boot

# Copy over the Bootloader
cp -rv /tmp/mnt/windows/Windows/Boot/EFI/ /tmp/mnt/efi/EFI/Microsoft/Boot
cp /tmp/mnt/windows/Windows/Boot/EFI/bootmgr.efi /tmp/mnt/efi/EFI/Boot/bootx64.efi

cp ./BCD /tmp/mnt/efi/EFI/Microsoft/Boot/BCD

#Continue after https://github.com/garloff/Fix_BCD/issues/1 hopefully.