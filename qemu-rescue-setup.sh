#!/bin/sh

set -eu

TARGET_DISK="/dev/vda"

if [ ! -b "$TARGET_DISK" ]; then
    echo "Error: Target disk $TARGET_DISK not found"
    echo "Make sure you're running in QEMU with disk.qcow2"
    exit 1
fi

echo ""
echo "[1/8] Setting up networking..."
setup-interfaces -a
ifup eth0
#rc-service networking start


echo ""
echo "[2/8] Configuring package repositories..."
setup-apkrepos -1

echo ""
echo "[3/8] Updating package index..."
apk update

echo ""
echo "[4/8] Installing Alpine to disk (automated)..."
# Use setup-disk in automatic mode - it handles partitioning and bootloader
# -m sys = sys mode (full install to disk)
# -s 0 = no swap
# The target disk is specified directly
echo "Running setup-disk to install Alpine..."
export BOOTLOADER=syslinux
# Pipe 'y' to confirm disk erase
echo "y" | setup-disk -m sys -s 0 "$TARGET_DISK"

echo ""
echo "[5/8] Mounting installed system for configuration..."
# setup-disk creates /dev/vda3 as root partition by default (vda1=boot, vda2=swap, vda3=root)
# But with -s 0 (no swap), it creates vda1=boot, vda2=root
# Let's find and mount the root partition
ROOT_PART=""
for part in ${TARGET_DISK}3 ${TARGET_DISK}2 ${TARGET_DISK}1; do
    if mount -t ext4 "$part" /mnt 2>/dev/null; then
        ROOT_PART="$part"
        echo "Mounted root partition: $ROOT_PART"
        break
    fi
done

if [ -z "$ROOT_PART" ]; then
    echo "Error: Could not find and mount root partition"
    echo "Available partitions:"
    ls -l /dev/vd* 2>/dev/null || true
    exit 1
fi

echo ""
echo "[6/8] Configuring installed system..."

chroot /mnt apk add zstd curl openssh xfsprogs

# Add hostshare mount to fstab
mkdir -p /mnt/host
cat >> /mnt/etc/fstab << 'EOF'
hostshare /host 9p trans=virtio,version=9p2000.L,_netdev 0 0
EOF

# Enable mounting of network filesystems at boot
chroot /mnt rc-update add netmount default

chroot /mnt rc-update add networking boot

# Enable and configure SSH
chroot /mnt rc-update add sshd default

# Configure SSH for key-only authentication
cat > /mnt/etc/ssh/sshd_config.d/10-hardening.conf << 'EOF'
PermitRootLogin prohibit-password
PasswordAuthentication no
ChallengeResponseAuthentication no
PubkeyAuthentication yes
EOF

# Add SSH public key from host
SSH_KEY_FILE="/host/.ssh_id.pub"
if [ -f "$SSH_KEY_FILE" ]; then
    echo "Installing SSH public key from $SSH_KEY_FILE"
    mkdir -p /mnt/root/.ssh
    cat "$SSH_KEY_FILE" > /mnt/root/.ssh/authorized_keys
    chmod 700 /mnt/root/.ssh
    chmod 600 /mnt/root/.ssh/authorized_keys
    echo "SSH key installed successfully"
else
    echo "WARNING: No SSH key found at $SSH_KEY_FILE"
    echo "SSH will be enabled but you won't be able to login without a key"
    echo ""
    echo "To add SSH key, link .ssh_id.pub in the project directory"
    echo "cp ~/.ssh/id_ed25519.pub .ssh_id.pub"
    echo "containing your public key before running init"
    exit 1
fi

cat > /mnt/etc/motd << 'EOF'
====================================
Alpine Rescue System (Pre-configured)
====================================

Host directory is auto-mounted at: /host

To deploy an image:
  cd /host
  ./install.sh ./dd-debian/output/debian-trixie-bios-x86.img.zst /dev/vdb

The system will reboot and boot from the deployed image.
====================================
EOF

# Unmount
sync
umount /mnt

echo ""
echo "======================================"
echo "Setup Complete!"
echo "======================================"

echo "./qemu.sh rescue"

poweroff
