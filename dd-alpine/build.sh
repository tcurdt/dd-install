#!/usr/bin/env bash

VERSION="${VERSION:-3.21}"
BOOT="${BOOT:-bios}"
ARCH="${ARCH:-x86_64}"
SSH_PUBKEY_FILE="${SSH_PUBKEY_FILE:-$HOME/.ssh/id_ed25519.pub}"
OUTPUT_DIR="${OUTPUT_DIR:-/result}"

set -Euo pipefail

mkdir -p "$OUTPUT_DIR"

IMAGE="alpine.img"
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

# create sparse disk image
IMAGE_PATH="$OUTPUT_DIR/${IMAGE}"
echo "[1/10] Creating sparse disk image ($IMAGE_SIZE)..."
rm -f "$IMAGE_PATH"
truncate -s "$IMAGE_SIZE" "$IMAGE_PATH"

# set up loop device
echo "[2/10] Setting up loop device..."
LOOP_DEV=$(losetup -f --show "$IMAGE_PATH")
echo "Loop device: $LOOP_DEV"

# partition the disk (GPT with BIOS boot partition)
echo "[3/10] Partitioning disk..."
parted -s "$LOOP_DEV" -- mklabel gpt
parted -s "$LOOP_DEV" -- mkpart primary 1MiB 3MiB          # BIOS boot partition
parted -s "$LOOP_DEV" -- mkpart primary btrfs 3MiB 4GiB    # root (smaller for 5G disk)
parted -s "$LOOP_DEV" -- mkpart primary ext4 4GiB 100%     # /var/lib
parted -s "$LOOP_DEV" -- set 1 bios_grub on

# reload partition table and create device mappings
echo "[4/10] Creating partition mappings..."
partprobe "$LOOP_DEV"
kpartx -u "$LOOP_DEV"
PART_MAPPINGS=$(kpartx -av "$LOOP_DEV" | cut -d' ' -f3)
sleep 2

# get partition device paths
PART1="/dev/mapper/$(echo "$PART_MAPPINGS" | sed -n 1p)"
PART2="/dev/mapper/$(echo "$PART_MAPPINGS" | sed -n 2p)"
PART3="/dev/mapper/$(echo "$PART_MAPPINGS" | sed -n 3p)"

echo "Partitions:"
echo "  BIOS boot: $PART1"
echo "  Root:      $PART2"
echo "  /var/lib:  $PART3"

# format partitions
echo "[5/10] Formatting partitions..."
mkfs.btrfs -f "$PART2"
mkfs.ext4 -F "$PART3"

# mount partitions and create btrfs subvolume
echo "[6/10] Mounting partitions..."
mkdir -p /mnt

# create btrfs subvolume
mount "$PART2" /mnt
btrfs subvolume create /mnt/@rootfs
umount /mnt

# mount with subvolume
mount -o subvol=@rootfs "$PART2" /mnt
mkdir -p /mnt/var/lib
mount "$PART3" /mnt/var/lib

# bootstrap Alpine Linux using apk.static
# reference: https://wiki.alpinelinux.org/wiki/Bootstrapping_Alpine_Linux
echo "[7/10] Bootstrapping Alpine Linux..."

MIRROR="https://dl-cdn.alpinelinux.org/alpine"

# install alpine-base using apk from the build container
# since we're running inside Alpine container, we can use apk directly with --root
apk --arch "$ARCH" \
    -X "${MIRROR}/v${VERSION}/main" \
    -X "${MIRROR}/v${VERSION}/community" \
    -U --allow-untrusted \
    --root /mnt \
    --initdb \
    add alpine-base

# configure repositories before installing more packages
mkdir -p /mnt/etc/apk
cat > /mnt/etc/apk/repositories << EOF
${MIRROR}/v${VERSION}/main
${MIRROR}/v${VERSION}/community
EOF

# copy resolv.conf for package installation
cp /etc/resolv.conf /mnt/etc/resolv.conf

# mount proc, sys, dev for chroot operations
mount -t proc proc /mnt/proc
mount -t sysfs sysfs /mnt/sys
mount -o bind /dev /mnt/dev
mount -o bind /dev/pts /mnt/dev/pts

# configure the system
echo "[8/10] Configuring system..."

# install essential packages
# reference: https://wiki.alpinelinux.org/wiki/GRUB
chroot /mnt apk update
chroot /mnt apk add --no-cache \
    linux-virt \
    linux-firmware-none \
    grub \
    grub-bios \
    btrfs-progs \
    openssh \
    curl \
    ca-certificates \
    openrc \
    mkinitfs \
    cloud-init

# set hostname
echo "server" > /mnt/etc/hostname

# configure hosts file
cat > /mnt/etc/hosts << 'EOF'
127.0.0.1       localhost
127.0.1.1       server

::1             localhost ip6-localhost ip6-loopback
ff02::1         ip6-allnodes
ff02::2         ip6-allrouters
EOF

# configure network with /etc/network/interfaces (Alpine style)
mkdir -p /mnt/etc/network
cat > /mnt/etc/network/interfaces << 'EOF'
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet dhcp
EOF

# configure DNS
cat > /mnt/etc/resolv.conf << 'EOF'
nameserver 1.1.1.1
nameserver 1.0.0.1
nameserver 8.8.8.8
EOF

# configure SSH for keys-only authentication
mkdir -p /mnt/etc/ssh
cat > /mnt/etc/ssh/sshd_config << 'EOF'
Port 22
PermitRootLogin prohibit-password
PasswordAuthentication no
ChallengeResponseAuthentication no
PubkeyAuthentication yes
UsePAM no
Subsystem sftp /usr/lib/ssh/sftp-server
EOF

# set timezone to UTC
chroot /mnt ln -sf /usr/share/zoneinfo/UTC /etc/localtime

# set root password (will be disabled via SSH config)
echo "root:secret" | chroot /mnt chpasswd
chroot /mnt passwd -u root

# create note about SSH keys requirement
cat > /mnt/root/README << 'EOF'
This system requires SSH key authentication.
Root password login is disabled.
EOF

# remove SSH host keys (will be regenerated on deployment)
rm -f /mnt/etc/ssh/ssh_host_*

# configure cloud-init for Hetzner
mkdir -p /mnt/etc/cloud/cloud.cfg.d
cat > /mnt/etc/cloud/cloud.cfg.d/99_hetzner.cfg << 'EOF'
datasource_list: [ Hetzner, None ]
disable_root: false
users: []
growpart:
  mode: auto
  devices:
    - /var/lib
EOF

# add SSH public key if provided
echo "Adding SSH public key to root authorized_keys..."
mkdir -p /mnt/root/.ssh
cat "$SSH_PUBKEY_FILE" > /mnt/root/.ssh/authorized_keys
chmod 700 /mnt/root/.ssh
chmod 600 /mnt/root/.ssh/authorized_keys

# create fstab with UUIDs (device-independent)
echo "Generating fstab with UUIDs..."
ROOT_UUID=$(blkid -s UUID -o value "$PART2")
VARLIB_UUID=$(blkid -s UUID -o value "$PART3")

cat > /mnt/etc/fstab << EOF
UUID=$ROOT_UUID   /         btrfs  subvol=@rootfs,defaults,noatime  0 1
UUID=$VARLIB_UUID /var/lib  ext4   defaults,noatime                 0 2
EOF

# configure mkinitfs for btrfs and virtio support
# reference: https://wiki.alpinelinux.org/wiki/Btrfs
echo "[9/10] Configuring initramfs with btrfs support..."
cat > /mnt/etc/mkinitfs/mkinitfs.conf << 'EOF'
features="ata base btrfs ext4 keymap kms mmc nvme scsi usb virtio"
EOF

# add btrfs module to load at boot
# reference: https://wiki.alpinelinux.org/wiki/Btrfs
echo "btrfs" >> /mnt/etc/modules

# find the kernel version
KERNEL_VERSION=$(ls /mnt/lib/modules/ | head -1)
echo "Kernel version: $KERNEL_VERSION"

# regenerate initramfs with btrfs support
chroot /mnt mkinitfs "$KERNEL_VERSION"

# sysinit runlevel
chroot /mnt rc-update add devfs sysinit
chroot /mnt rc-update add dmesg sysinit
chroot /mnt rc-update add mdev sysinit
chroot /mnt rc-update add hwdrivers sysinit

# boot runlevel
chroot /mnt rc-update add hwclock boot
chroot /mnt rc-update add modules boot
chroot /mnt rc-update add sysctl boot
chroot /mnt rc-update add hostname boot
chroot /mnt rc-update add bootmisc boot
chroot /mnt rc-update add networking boot
chroot /mnt rc-update add btrfs-scan boot  # critical for btrfs root!

# default runlevel
chroot /mnt rc-update add sshd default
chroot /mnt rc-update add cloud-init-local boot
chroot /mnt rc-update add cloud-init default
chroot /mnt rc-update add cloud-config default
chroot /mnt rc-update add cloud-final default

# shutdown runlevel
chroot /mnt rc-update add mount-ro shutdown
chroot /mnt rc-update add killprocs shutdown
chroot /mnt rc-update add savecache shutdown

# configure serial console in inittab
sed -i 's/^#ttyS0/ttyS0/' /mnt/etc/inittab 2>/dev/null || true
if ! grep -q "^ttyS0" /mnt/etc/inittab; then
    echo "ttyS0::respawn:/sbin/getty -L ttyS0 115200 vt100" >> /mnt/etc/inittab
fi

# reference: https://wiki.alpinelinux.org/wiki/GRUB
echo "[10/10] Installing GRUB bootloader..."

ROOT_UUID=$(blkid -s UUID -o value "$PART2")
echo "Root UUID: $ROOT_UUID"

# serial console and UUID-based root
mkdir -p /mnt/etc/default
cat > /mnt/etc/default/grub << EOF
GRUB_TIMEOUT=5
GRUB_DISTRIBUTOR="Alpine"
GRUB_CMDLINE_LINUX_DEFAULT="console=tty0 console=ttyS0,115200 modules=sd-mod,usb-storage,btrfs,ext4"
GRUB_CMDLINE_LINUX="root=UUID=$ROOT_UUID rootfstype=btrfs rootflags=subvol=@rootfs"
GRUB_TERMINAL="console serial"
GRUB_SERIAL_COMMAND="serial --unit=0 --speed=115200"
GRUB_DISABLE_OS_PROBER=true
EOF

# install to the loop device
chroot /mnt grub-install --target=i386-pc "$LOOP_DEV"

# generate configuration
chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg

# clean up
rm -rf /mnt/var/cache/apk/*
rm -rf /mnt/tmp/*
rm -rf /mnt/var/tmp/*

# unmount everything
umount /mnt/dev/pts 2>/dev/null || true
umount /mnt/dev 2>/dev/null || true
umount /mnt/sys 2>/dev/null || true
umount /mnt/proc 2>/dev/null || true
umount /mnt/var/lib 2>/dev/null || true
umount /mnt 2>/dev/null || true

# remove loop device
kpartx -d "$LOOP_DEV"
losetup -d "$LOOP_DEV"
LOOP_DEV=""

echo ""
echo "======================================"
echo "Image: $IMAGE_PATH"
echo "Size: $(du -h "$IMAGE_PATH" | cut -f1)"
