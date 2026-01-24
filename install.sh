#!/bin/bash
#
# the script will:
#   1. download the image if it's a URL
#   2. decompress and write to target device
#   3. optionally mount and customize (SSH keys, etc.)
#   4. regenerate SSH host keys
#   5. sync and reboot
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

assert_command() {
  if ! command -v "$1" &> /dev/null; then
    echo "error: required command not found: $1"
    exit 1
  fi
}

assert_command curl
assert_command zstd
assert_command chroot
assert_command funzip
assert_command pv

# auto-detect target disk if not specified
if [ -z "$TARGET_DISK" ]; then
  # prefer /dev/vdb in QEMU (rescue system is on vda)
  if [ -b /dev/vdb ]; then
    TARGET_DISK="/dev/vdb"
  elif [ -b /dev/sda ]; then
    TARGET_DISK="/dev/sda"
  elif [ -b /dev/vda ]; then
    TARGET_DISK="/dev/vda"
  else
    echo "error: no suitable target disk found"
    echo "please specify target device explicitly"
    exit 1
  fi
  echo "auto-detected target disk: $TARGET_DISK"
fi

# verify target disk exists
if [ ! -b "$TARGET_DISK" ]; then
  echo "error: target disk not found: $TARGET_DISK"
  exit 1
fi

echo "[1/4] deploying $IMAGE to $TARGET_DISK"

# check if image is a URL or local file
if echo "$IMAGE" | grep -qE '^https?://'; then
  echo "downloading and decompressing from URL"

  if echo "$IMAGE" | grep -qE 'nightly\.link'; then
    # github artifact downloads are zip files with trailing metadata that
    # causes funzip to exit non-zero even though the data extracted successfully
    set +o pipefail
    curl -fsSL "$IMAGE" | pv | funzip | dd of="$TARGET_DISK" bs=4M
    set -o pipefail
  elif echo "$IMAGE" | grep -qE '\.zip$'; then
    curl -fsSL "$IMAGE" | pv | funzip | dd of="$TARGET_DISK" bs=4M
  elif echo "$IMAGE" | grep -qE '\.zst$'; then
    curl -fsSL "$IMAGE" | pv | zstd -d | dd of="$TARGET_DISK" bs=4M
  else
    curl -fsSL "$IMAGE" | pv | dd of="$TARGET_DISK" bs=4M
  fi
else
  # local
  if [ ! -f "$IMAGE" ]; then
    echo "error: image file not found: $IMAGE"
    exit 1
  fi

  if echo "$IMAGE" | grep -qE '\.zst$'; then
    cat "$IMAGE" | zstd -d | dd of="$TARGET_DISK" bs=4M
  elif echo "$IMAGE" | grep -qE '\.zip$'; then
    cat "$IMAGE" | funzip | dd of="$TARGET_DISK" bs=4M
  else
    dd if="$IMAGE" of="$TARGET_DISK" bs=4M
  fi
fi

echo ""
echo "[2/4] syncing disk"
sync

echo ""
echo "[3/4] setting up deployed system"

partprobe "$TARGET_DISK" || true
sleep 2

# mount the root partition
MOUNTED=0
for part in "${TARGET_DISK}2" "${TARGET_DISK}p2"; do
  if [ -b "$part" ]; then
    echo "attempting to mount root partition: $part"
    mkdir -p /mnt/target

    # mounting with btrfs subvolume first
    if mount -t btrfs -o subvol=@rootfs "$part" /mnt/target 2>/dev/null; then
      echo "mounted btrfs with @rootfs subvolume"
      MOUNTED=1
      ROOT_PART="$part"
      break
    # mounting as ext4
    elif mount -t ext4 "$part" /mnt/target 2>/dev/null; then
      echo "mounted ext4"
      MOUNTED=1
      ROOT_PART="$part"
      break
    fi
  fi
done

if [ "$MOUNTED" = "1" ]; then
  echo "root partition mounted"

  if [ -d /mnt/target/etc/ssh ]; then
    echo "regenerating SSH host keys"
    rm -f /mnt/target/etc/ssh/ssh_host_* || true

    # mount for chroot
    mount -t proc proc /mnt/target/proc 2>/dev/null || true
    mount -t sysfs sysfs /mnt/target/sys 2>/dev/null || true
    mount -o bind /dev /mnt/target/dev 2>/dev/null || true

    chroot /mnt/target /bin/sh -c "ssh-keygen -A" 2>/dev/null || true

    umount /mnt/target/dev 2>/dev/null || true
    umount /mnt/target/sys 2>/dev/null || true
    umount /mnt/target/proc 2>/dev/null || true
  fi

  umount /mnt/target
  echo "unmounted root partition"
else
  echo "note: could not mount root partition for customization"
  echo "system will regenerate SSH keys on first boot"
fi

echo ""
echo "[4/4] installation complete"
echo "======================================"
echo ""
echo "now reboot and login"

# poweroff
# reboot
