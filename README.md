# DD-based Server Deployment

Automated server deployment using pre-built disk images and dd.

## Overview

This project provides:

1. **image builders** - create minimal, bootable disk images (Alpine, Debian, NixOS)
2. **install script** - deploy images to servers in rescue mode
3. **qemu testing** - test the complete flow locally before deploying

## Structure

```
dd/
├── dd-alpine/          # Alpine image builder
│   ├── build.sh        # Creates bootable disk image
│   └── Dockerfile      # Build environment
│
├── dd-debian/          # Debian image builder
│   ├── build.sh        # Creates bootable disk image
│   └── Dockerfile      # Build environment
│
├── dd-nixos/           # NixOS image builder
│   ├── build.sh        # Creates bootable disk image
│   └── Dockerfile      # Build environment
│
│
└── README.md           # This file
```

## Quick Start

### 1. Build a Debian Image

```bash
./dd-debian/build.sh trixie bios x86
ls -la debian-trixie-bios-x86.img.zst
```

This creates a compressed disk image (~400MB transfer size).

    SSH_PUBKEY := env_var_or_default('SSH_PUBKEY', env_var('HOME') + '/.ssh/id_ed25519.pub')

The SSH public key is automatically baked into the image for testing.

**What's inside:**

- Minimal Debian Bookworm (systemd, SSH, networking)
- BIOS boot compatible (GPT + BIOS boot partition)
- Btrfs root with @rootfs subvolume
- Pre-installed GRUB bootloader
- DHCP networking via systemd-networkd
- SSH keys-only authentication

### 2. Test in QEMU

```bash
./qemu.sh init # setups up the rescue image
./qemu.sh rescue
```

This boots QEMU with Alpine rescue:

- Console login (root:secret)
- SSH login with your key
- Network configuration
- Bootloader

Then we run the install

```bash
./install.sh ./debian-trixie-bios-x86.img.zst
```

Now we can stop the rescue system and boot the fresh install system

```bash
./qemu.sh run
```

## Partition Layout

The images use this partition scheme (compatible with QEMU and Hetzner):

```
GPT Partition Table
├── /dev/sda1  1MiB-3MiB     BIOS boot partition (no filesystem)
├── /dev/sda2  3MiB-25GiB    Btrfs root (subvol=@rootfs)
└── /dev/sda3  25GiB-100%    ext4 /var/lib
```

## Image Optimization

Images are sparse, meaning:

- **Apparent size**: 30GB (full disk)
- **Actual size**: ~2GB (only used blocks)
- **Transfer time**: Minutes instead of hours
- **Expansion**: Automatic on write

## References

- Existing work: `/Users/tcurdt/Desktop/newfra/server/rescue/mkbootstrap/`
- QEMU setup: `/Users/tcurdt/Desktop/newfra/server/rescue/`
- Plan: `CLAUDE.md`
