#!/usr/bin/env bash
#
# QEMU testing helper for dd images
#
# Usage:
#   ./qemu.sh init       # One-time: Setup Alpine rescue system on disk-rescue.qcow2
#   ./qemu.sh rescue     # Boot Alpine rescue system (for deploying images)
#   ./qemu.sh target     # Boot the deployed image from disk-target.qcow2
#
# Two-disk setup:
#   - disk-rescue.qcow2: Persistent Alpine rescue system (/dev/vda)
#   - disk-target.qcow2: Target for image deployment (/dev/vdb)
#
# Workflow:
#   1. One-time: ./qemu.sh init
#   2. Deploy: ./qemu.sh rescue → install.sh <image> /dev/vdb
#   3. Target: ./qemu.sh target (boots deployed image)
#   4. Repeat from step 2
#

set -Euo pipefail

MODE="${1:-rescue}"

if [ "$MODE" != "init" ] && [ "$MODE" != "rescue" ] && [ "$MODE" != "target" ]; then
    echo "Error: Invalid mode: $MODE"
    echo ""
    echo "Usage:"
    echo "  $0 init       # setup Alpine rescue system (run once)"
    echo "  $0 rescue     # boot Alpine rescue (for deploying images)"
    echo "  $0 test       # boot deployed image from disk-target.qcow2"
    echo ""
    exit 1
fi

ALPINE_ISO="alpine-standard-3.19.0-x86_64.iso"
ALPINE_URL="https://dl-cdn.alpinelinux.org/alpine/v3.19/releases/x86_64/${ALPINE_ISO}"
DISK_RESCUE="disk-rescue.qcow2"
DISK_TARGET="disk-target.qcow2"

QEMU_COMMON_ARGS=(
    -machine pc-i440fx-10.1
    -cpu qemu64
    -smp 2
    -m 4G
    -accel tcg
    -nographic
    -nic user,model=virtio,hostfwd=tcp::2222-:22
)

# download Alpine ISO if needed
if [ "$MODE" = "init" ] && [ ! -f "$ALPINE_ISO" ]; then
    echo "downloading alpine ISO..."
    curl -L -o "$ALPINE_ISO" "$ALPINE_URL"
    echo ""
fi

if [ "$MODE" = "init" ]; then

    rm -f "$DISK_RESCUE" 2>/dev/null

    echo "creating $DISK_RESCUE..."
    qemu-img create -f qcow2 "$DISK_RESCUE" 5G
    echo ""

    echo "==== instructions ===="
    echo ""
    echo "once alpine boots, login as root (no password) and run:"
    echo ""
    SETUP_CMD="mkdir -p /host && mount -t 9p -o trans=virtio,version=9p2000.L hostshare /host && sh /host/qemu-rescue-setup.sh"
    echo "  $SETUP_CMD"
    echo ""

    if command -v pbcopy >/dev/null 2>&1; then
        echo "$SETUP_CMD" | pbcopy
        echo "command copied to clipboard - just paste in alpine"
        echo ""
    fi

    echo "press RETURN to start QEMU..."
    read

    exec qemu-system-x86_64 \
        "${QEMU_COMMON_ARGS[@]}" \
        -boot order=d \
        -cdrom "$ALPINE_ISO" \
        -drive file="$DISK_RESCUE",if=virtio,format=qcow2 \
        -virtfs local,path="$PWD",mount_tag=hostshare,security_model=passthrough,id=hostshare

elif [ "$MODE" = "rescue" ]; then

    if [ ! -f "$DISK_RESCUE" ]; then
        echo "error: $DISK_RESCUE not found"
        echo ""
        echo "you need to create it first:"
        echo "  $0 init"
        echo ""
        exit 1
    fi

    if [ ! -f "$DISK_TARGET" ]; then
        echo "creating $DISK_TARGET..."
        qemu-img create -f qcow2 "$DISK_TARGET" 30G
        echo ""
    fi


    echo "==== instructions ===="
    echo ""
    echo "the rescue system is pre-configured with:"
    echo "  - host directory auto-mounted at /host"
    echo "  - zstd and curl installed"
    echo "  - networking already configured"
    echo ""
    echo "to deploy an image, run in alpine:"
    echo ""
    DEPLOY_CMD="cd /host && ./install.sh ./dd-debian/output/debian-trixie-bios-x86.img.zst /dev/vdb"
    echo "  $DEPLOY_CMD"
    echo ""
    echo "the system will reboot and boot from /dev/vdb ($DISK_TARGET)"
    echo ""

    if command -v pbcopy >/dev/null 2>&1; then
        echo "$DEPLOY_CMD" | pbcopy
        echo "(command copied to clipboard - just paste in alpine)"
        echo ""
    fi

    echo ""

    exec qemu-system-x86_64 \
        "${QEMU_COMMON_ARGS[@]}" \
        -drive file="$DISK_RESCUE",if=virtio,format=qcow2 \
        -drive file="$DISK_TARGET",if=virtio,format=qcow2 \
        -virtfs local,path="$PWD",mount_tag=hostshare,security_model=passthrough,id=hostshare

elif [ "$MODE" = "target" ]; then

    if [ ! -f "$DISK_TARGET" ]; then
        echo "error: $DISK_TARGET not found"
        echo ""
        echo "you need to deploy an image first:"
        echo "  $0 rescue"
        echo ""
        exit 1
    fi

    echo "booting deployed image from $DISK_TARGET..."
    echo ""
    echo "  ssh -p 2222 root@localhost"
    echo ""

    exec qemu-system-x86_64 \
        "${QEMU_COMMON_ARGS[@]}" \
        -drive file="$DISK_TARGET",if=virtio,format=qcow2

fi
