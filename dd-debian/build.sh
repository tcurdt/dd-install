#!/usr/bin/env bash

VERSION="${VERSION:-trixie}"
BOOT="${BOOT:-bios}"
ARCH="${ARCH:-amd}"
SSH_PUBKEY_FILE="${SSH_PUBKEY_FILE:-$HOME/.ssh/id_ed25519.pub}"
OUTPUT_DIR="${OUTPUT_DIR:-/result}"

set -Euo pipefail

mkdir -p "$OUTPUT_DIR"

ARCH_BITS="${ARCH}64"

# IMAGE="debian-${VERSION}-${BOOT}-${ARCH_BITS}.img"
IMAGE="debian.img"
IMAGE_SIZE="${IMAGE_SIZE:-5G}"

echo "VERSION: $VERSION"
echo "BOOT: $BOOT"
echo "ARCH: ${ARCH}"
echo "SSH_PUBKEY_FILE: ${SSH_PUBKEY_FILE}"
echo "OUTPUT: $OUTPUT_DIR/$IMAGE"
echo ""

cleanup() {
    if [ -n "${LOOP_DEV:-}" ]; then
        umount -R /mnt 2>/dev/null || true
        kpartx -d "$LOOP_DEV" 2>/dev/null || true
        losetup -d "$LOOP_DEV" 2>/dev/null || true
    fi
}

trap cleanup EXIT SIGINT SIGTERM

# Create sparse disk image
IMAGE_PATH="$OUTPUT_DIR/${IMAGE}"
echo "[1/9] Creating sparse disk image ($IMAGE_SIZE)..."
rm -f "$IMAGE_PATH"
truncate -s "$IMAGE_SIZE" "$IMAGE_PATH"

# Set up loop device
echo "[2/9] Setting up loop device..."
LOOP_DEV=$(losetup -f --show "$IMAGE_PATH")
echo "Loop device: $LOOP_DEV"

# Partition the disk
echo "[3/9] Partitioning disk..."
parted -s "$LOOP_DEV" -- mklabel gpt
if [ "$BOOT" = "efi" ]; then
    parted -s "$LOOP_DEV" -- mkpart primary fat32 1MiB 257MiB   # EFI System Partition
    parted -s "$LOOP_DEV" -- mkpart primary btrfs 257MiB 4GiB   # root
    parted -s "$LOOP_DEV" -- mkpart primary xfs 4GiB 100%       # /var/lib
    parted -s "$LOOP_DEV" -- set 1 esp on
    parted -s "$LOOP_DEV" -- set 1 boot on
else
    parted -s "$LOOP_DEV" -- mkpart primary 1MiB 3MiB           # BIOS boot partition
    parted -s "$LOOP_DEV" -- mkpart primary btrfs 3MiB 4GiB     # root
    parted -s "$LOOP_DEV" -- mkpart primary xfs 4GiB 100%       # /var/lib
    parted -s "$LOOP_DEV" -- set 1 bios_grub on
fi

# Reload partition table and create device mappings
echo "[4/9] Creating partition mappings..."
partprobe "$LOOP_DEV"
kpartx -u "$LOOP_DEV"
PART_MAPPINGS=$(kpartx -av "$LOOP_DEV" | cut -d' ' -f3)
sleep 2

# Get partition device paths
PART1="/dev/mapper/$(echo "$PART_MAPPINGS" | sed -n 1p)"
PART2="/dev/mapper/$(echo "$PART_MAPPINGS" | sed -n 2p)"
PART3="/dev/mapper/$(echo "$PART_MAPPINGS" | sed -n 3p)"

echo "Partitions:"
if [ "$BOOT" = "efi" ]; then
    echo "  ESP:       $PART1"
else
    echo "  BIOS boot: $PART1"
fi
echo "  Root:      $PART2"
echo "  /var/lib:  $PART3"

# Format partitions
echo "[5/9] Formatting partitions..."
if [ "$BOOT" = "efi" ]; then
    mkfs.fat -F 32 "$PART1"
fi
mkfs.btrfs -f "$PART2"
mkfs.xfs -f "$PART3"

# Mount partitions and create btrfs subvolume
echo "[6/9] Mounting partitions..."
mkdir -p /mnt

# Create btrfs subvolume
mount "$PART2" /mnt
btrfs subvolume create /mnt/@rootfs
umount /mnt

# Mount with subvolume
mount -o subvol=@rootfs "$PART2" /mnt
mkdir -p /mnt/var/lib
mount "$PART3" /mnt/var/lib
if [ "$BOOT" = "efi" ]; then
    mkdir -p /mnt/boot/efi
    mount "$PART1" /mnt/boot/efi
fi

# Install minimal Debian system
echo "[7/9] Installing minimal Debian system (this will take a few minutes)..."
debootstrap \
    --arch="$ARCH_BITS" \
    --include=systemd-sysv \
    --variant=minbase \
    "$VERSION" \
    /mnt \
    http://deb.debian.org/debian

# Mount proc, sys, dev for chroot operations
mount -t proc proc /mnt/proc
mount -t sysfs sysfs /mnt/sys
mount -o bind /dev /mnt/dev
mount -o bind /dev/pts /mnt/dev/pts

# Configure the system
echo "[8/9] Configuring system..."

# Configure apt to avoid bloat
export DEBIAN_FRONTEND=noninteractive
export APT_OPTIONS="-oAPT::Install-Recommends=false -oAPT::Install-Suggests=false -oAcquire::Languages=none"

# Install essential packages
if [ "$BOOT" = "efi" ]; then
    GRUB_PKG="grub-efi-amd64"
    EXTRA_PKGS="dosfstools"
else
    GRUB_PKG="grub-pc"
    EXTRA_PKGS=""
fi

chroot /mnt apt-get $APT_OPTIONS update
chroot /mnt apt-get $APT_OPTIONS --yes install \
    linux-image-"$ARCH_BITS" \
    "$GRUB_PKG" \
    openssh-server \
    curl \
    iproute2 \
    iputils-ping \
    ca-certificates \
    btrfs-progs \
    xfsprogs \
    cloud-init \
    $EXTRA_PKGS

# Set hostname
echo "server" > /mnt/etc/hostname

# Configure hosts file
cat > /mnt/etc/hosts << 'EOF'
127.0.0.1       localhost
127.0.1.1       server

::1             localhost ip6-localhost ip6-loopback
ff02::1         ip6-allnodes
ff02::2         ip6-allrouters
EOF

# Configure network with systemd-networkd
mkdir -p /mnt/etc/systemd/network
cat > /mnt/etc/systemd/network/20-wired.network << 'EOF'
[Match]
Name=en* eth*

[Network]
DHCP=yes
EOF

# Enable systemd-networkd and ssh
chroot /mnt systemctl enable systemd-networkd
chroot /mnt systemctl enable ssh

# Configure DNS
cat > /mnt/etc/resolv.conf << 'EOF'
nameserver 1.1.1.1
nameserver 1.0.0.1
nameserver 8.8.8.8
EOF

# Configure SSH for keys-only authentication
cat > /mnt/etc/ssh/sshd_config.d/10-hardening.conf << 'EOF'
PermitRootLogin prohibit-password
PasswordAuthentication no
ChallengeResponseAuthentication no
PubkeyAuthentication yes
EOF

# Configure apt sources
cat > /mnt/etc/apt/sources.list << EOF
deb http://deb.debian.org/debian $VERSION main contrib non-free non-free-firmware
deb http://deb.debian.org/debian $VERSION-updates main contrib non-free non-free-firmware
deb http://security.debian.org/debian-security $VERSION-security main contrib non-free non-free-firmware
EOF

# Set timezone to UTC
chroot /mnt ln -sf /usr/share/zoneinfo/UTC /etc/localtime

# Set root password (will be disabled via SSH config)
echo "root:secret" | chroot /mnt chpasswd
chroot /mnt passwd -u root

# Create note about SSH keys requirement
cat > /mnt/root/README << 'EOF'
This system requires SSH key authentication.
Root password login is disabled.
EOF

# Remove SSH host keys (will be regenerated on deployment)
rm -f /mnt/etc/ssh/ssh_host_*

# Configure cloud-init for Hetzner
mkdir -p /mnt/etc/cloud/cloud.cfg.d
cat > /mnt/etc/cloud/cloud.cfg.d/99_hetzner.cfg << 'EOF'
datasource_list: [ Hetzner, None ]
disable_root: false
users: []
EOF

# Add SSH public key if provided
echo "Adding SSH public key to root authorized_keys..."
mkdir -p /mnt/root/.ssh
cat $SSH_PUBKEY_FILE > /mnt/root/.ssh/authorized_keys
chmod 700 /mnt/root/.ssh
chmod 600 /mnt/root/.ssh/authorized_keys

# Create fstab with UUIDs (device-independent)
echo "Generating fstab with UUIDs..."
ROOT_UUID=$(blkid -s UUID -o value "$PART2")
VARLIB_UUID=$(blkid -s UUID -o value "$PART3")

if [ "$BOOT" = "efi" ]; then
    ESP_UUID=$(blkid -s UUID -o value "$PART1")
    cat > /mnt/etc/fstab << EOF
UUID=$ROOT_UUID   /          btrfs  subvol=@rootfs,defaults,noatime  0 1
UUID=$VARLIB_UUID /var/lib   xfs    defaults,noatime                 0 2
UUID=$ESP_UUID    /boot/efi  vfat   defaults                         0 0
EOF
else
    cat > /mnt/etc/fstab << EOF
UUID=$ROOT_UUID   /         btrfs  subvol=@rootfs,defaults,noatime  0 1
UUID=$VARLIB_UUID /var/lib  xfs    defaults,noatime                 0 2
EOF
fi

# Install GRUB
echo "[9/9] Installing GRUB bootloader..."

# Get root filesystem UUID
ROOT_UUID=$(blkid -s UUID -o value "$PART2")
echo "Root UUID: $ROOT_UUID"

# Configure GRUB for serial console and UUID-based root
sed -i '/^GRUB_TERMINAL=/d; /^GRUB_GFXPAYLOAD_LINUX=/d; /^GRUB_CMDLINE_LINUX=/d' /mnt/etc/default/grub
sed -i 's/quiet//' /mnt/etc/default/grub
echo 'GRUB_TERMINAL="console serial"' >> /mnt/etc/default/grub
echo 'GRUB_SERIAL_COMMAND="serial --unit=0 --speed=115200"' >> /mnt/etc/default/grub
echo "GRUB_CMDLINE_LINUX=\"console=tty0 console=ttyS0,115200 root=UUID=$ROOT_UUID rootflags=subvol=@rootfs\"" >> /mnt/etc/default/grub

# Install grub
if [ "$BOOT" = "efi" ]; then
    chroot /mnt grub-install --target=x86_64-efi --efi-directory=/boot/efi --removable --no-nvram
else
    chroot /mnt grub-install --target=i386-pc "$LOOP_DEV"
fi

# Update initramfs
if ! grep -qx "xfs" /mnt/etc/initramfs-tools/modules; then
    echo "xfs" >> /mnt/etc/initramfs-tools/modules
fi
chroot /mnt update-initramfs -u -k all

# Generate grub configuration
chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg

# Clean up
chroot /mnt apt-get clean
rm -rf /mnt/var/lib/apt/lists/*
rm -rf /mnt/tmp/*
rm -rf /mnt/var/tmp/*
rm -rf /mnt/var/log/apt/*
rm -rf /mnt/var/log/alternatives.log
rm -rf /mnt/var/log/bootstrap.log
rm -rf /mnt/var/log/dpkg.log

# Unmount everything
umount /mnt/dev/pts 2>/dev/null || true
umount /mnt/dev 2>/dev/null || true
umount /mnt/sys 2>/dev/null || true
umount /mnt/proc 2>/dev/null || true
umount /mnt/boot/efi 2>/dev/null || true
umount /mnt/var/lib 2>/dev/null || true
umount /mnt 2>/dev/null || true

# Remove loop device
kpartx -d "$LOOP_DEV"
losetup -d "$LOOP_DEV"
LOOP_DEV=""

# Compress with zstd
# echo "Compressing image with zstd..."
# COMPRESSED_IMAGE="$OUTPUT_DIR/${IMAGE}.img.zst"
# zstd -19 --rm "$IMAGE_PATH" -o "$COMPRESSED_IMAGE"

# echo ""
# echo "======================================"
# echo "Image: $COMPRESSED_IMAGE"
# echo "Size: $(du -h "$COMPRESSED_IMAGE" | cut -f1)"
