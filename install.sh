#!/bin/bash
#
# Install script for deploying dd images
#
# This script is designed to run in a rescue environment (like Alpine Linux)
# to deploy a pre-built image to a target disk.
#
# curl https://raw.githubusercontent.com/tcurdt/dd-install/refs/heads/main/install.sh > install.sh
#
# Usage:
#   ./install.sh <image-file> [target-device]
#   ./install.sh <https-url> [target-device]
#
# Examples:
#   ./install.sh /mnt/host/dd-debian/output/debian-trixie-bios-x86.img.zst
#   ./install.sh /mnt/host/dd-debian/output/debian-trixie-bios-x86.img.zst /dev/vdb
#   ./install.sh https://releases.example.com/debian-trixie-bios-x86.img.zst /dev/sda
#   ./install.sh https://github.com/tcurdt/dd-install/actions/runs/21195076587/artifacts/5198693838 /dev/sda
#
#
# The script will:
#   1. Download the image if it's a URL
#   2. Decompress and write to target device
#   3. Optionally mount and customize (SSH keys, etc.)
#   4. Regenerate SSH host keys
#   5. Sync and reboot
#

set -euo pipefail

IMAGE="${1:-}"
TARGET_DISK="${2:-}"

if [ -z "$IMAGE" ]; then
    echo "Error: Image file or URL required"
    echo ""
    echo "Usage:"
    echo "  $0 <image-file> [target-device]"
    echo "  $0 <https-url> [target-device]"
    echo ""
    echo "Examples:"
    echo "  $0 /mnt/host/dd-debian/output/debian-trixie-bios-x86.img.zst /dev/vdb"
    echo "  $0 https://releases.example.com/debian-trixie-bios-x86.img.zst /dev/sda"
    exit 1
fi

# Auto-detect target disk if not specified
if [ -z "$TARGET_DISK" ]; then
    # Prefer /dev/vdb in QEMU (rescue system is on vda)
    if [ -b /dev/vdb ]; then
        TARGET_DISK="/dev/vdb"
    elif [ -b /dev/sda ]; then
        TARGET_DISK="/dev/sda"
    elif [ -b /dev/vda ]; then
        TARGET_DISK="/dev/vda"
    else
        echo "Error: No suitable target disk found"
        echo "Please specify target device explicitly:"
        echo "  $0 $IMAGE /dev/sdX"
        exit 1
    fi
    echo "Auto-detected target disk: $TARGET_DISK"
fi

# Verify target disk exists
if [ ! -b "$TARGET_DISK" ]; then
    echo "Error: Target disk not found: $TARGET_DISK"
    echo "Available block devices:"
    ls -l /dev/sd* /dev/vd* 2>/dev/null || echo "  None found"
    exit 1
fi

echo "WARNING: This will DESTROY all data on $TARGET_DISK!"
echo ""
echo "Image:  $IMAGE"
echo "Target: $TARGET_DISK"
echo ""
echo "Press Ctrl-C within 5 seconds to cancel..."
sleep 5
echo ""

echo "[1/4] Deploying image to disk..."

# Check if image is a URL or local file
if echo "$IMAGE" | grep -qE '^https?://'; then
    echo "downloading and decompressing zip from URL..."

    # if ! command -v curl >/dev/null 2>&1; then
    #     echo "Error: curl not found. Install it first: apk add curl"
    #     exit 1
    # fi
    # if ! command -v zstd >/dev/null 2>&1; then
    #     echo "Error: zstd not found. Install it first: apk add zstd"
    #     exit 1
    # fi

    curl -fL "$IMAGE" | bsdtar -xOf - | dd of="$TARGET_DISK" bs=4M
    # curl -fL "$IMAGE" | zstd -d | dd of="$TARGET_DISK" bs=4M
else
    # Local file
    if [ ! -f "$IMAGE" ]; then
        echo "Error: Image file not found: $IMAGE"
        exit 1
    fi

    # echo "Decompressing local file..."
    # if ! command -v zstd >/dev/null 2>&1; then
    #     echo "Error: zstd not found. Install it first: apk add zstd"
    #     exit 1
    # fi

    if echo "$IMAGE" | grep -qE '\.img$'; then
        dd if="$IMAGE" of="$TARGET_DISK" bs=4M
    elif echo "$IMAGE" | grep -qE '\.zst$'; then
        zstd -d -c "$IMAGE" | dd of="$TARGET_DISK" bs=4M
    elif echo "$IMAGE" | grep -qE '\.zip$'; then
        bsdtar -xOf "$IMAGE" | dd of="$TARGET_DISK" bs=4M
    else
        echo "Error: Unknown image format (expected .img.zst, .img or .zip)"
        exit 1
    fi
fi

echo ""
echo "[2/4] Syncing disk..."
sync

echo ""
echo "[3/4] Setting up deployed system..."

partprobe "$TARGET_DISK" || true

sleep 2

# Try to mount the root partition
# For Debian (btrfs subvolume) this is typically partition 2
# For NixOS (ext4) this is also partition 2
MOUNTED=0
for part in "${TARGET_DISK}2" "${TARGET_DISK}p2"; do
  if [ -b "$part" ]; then
    echo "Attempting to mount root partition: $part"
    mkdir -p /mnt/target

    # Try mounting with btrfs subvolume first (Debian)
    if mount -t btrfs -o subvol=@rootfs "$part" /mnt/target 2>/dev/null; then
      echo "Mounted btrfs with @rootfs subvolume"
      MOUNTED=1
      ROOT_PART="$part"
      break
    # Try mounting as ext4 (NixOS)
    elif mount -t ext4 "$part" /mnt/target 2>/dev/null; then
      echo "Mounted ext4"
      MOUNTED=1
      ROOT_PART="$part"
      break
    fi
  fi
done

if [ "$MOUNTED" = "1" ]; then
    echo "Root partition mounted at /mnt/target"

    if [ -d /mnt/target/etc/ssh ]; then
        echo "Regenerating SSH host keys..."
        rm -f /mnt/target/etc/ssh/ssh_host_*

        # Mount proc/sys/dev for chroot
        mount -t proc proc /mnt/target/proc 2>/dev/null || true
        mount -t sysfs sysfs /mnt/target/sys 2>/dev/null || true
        mount -o bind /dev /mnt/target/dev 2>/dev/null || true

        if command -v chroot >/dev/null 2>&1; then
            chroot /mnt/target /bin/sh -c "ssh-keygen -A" 2>/dev/null || echo "Note: Could not regenerate SSH keys (will be done on first boot)"
        fi

        umount /mnt/target/dev 2>/dev/null || true
        umount /mnt/target/sys 2>/dev/null || true
        umount /mnt/target/proc 2>/dev/null || true
    fi

    umount /mnt/target
    echo "Unmounted root partition"
else
    echo "Note: Could not mount root partition for customization"
    echo "System will regenerate SSH keys on first boot"
fi

echo ""
echo "[4/4] Installation complete!"
echo "======================================"
echo ""
echo "After reboot, you can SSH in (if SSH keys were injected during build):"
echo "  ssh -p 2222 root@localhost"
echo ""

# poweroff
