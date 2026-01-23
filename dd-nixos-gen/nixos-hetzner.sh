#!/bin/bash
set -euxo pipefail

TARGET_DISK="/dev/sda"
SSH_KEY="ssh-ed25519 AAAA...yourkey..."
HOSTNAME="hetzner"
STATE_VERSION="25.11"

# partition
parted "$TARGET_DISK" -- mklabel gpt
parted "$TARGET_DISK" -- mkpart ESP fat32 1MiB 513MiB
parted "$TARGET_DISK" -- set 1 esp on
parted "$TARGET_DISK" -- mkpart primary ext4 513MiB 100%
partprobe "$TARGET_DISK"

# format
mkfs.fat -F32 "${TARGET_DISK}1"
mkfs.ext4 "${TARGET_DISK}2"

# mount for chroot
mount "${TARGET_DISK}2" /mnt
mkdir -p /mnt/boot
mount "${TARGET_DISK}1" /mnt/boot

# rescue workaround
groupadd nixbld
for i in $(seq 1 10); do
  useradd -g nixbld -G nixbld -M -N -r -d /var/empty -s /sbin/nologin nixbld$i
done

# bootstrap nix
curl -L https://releases.nixos.org/nix/nix-2.33.1/nix-2.33.1-x86_64-linux.tar.xz | tar -xJ
cd nix-2.33.1-x86_64-linux
mkdir -m 0755 /nix && chown root /nix
./install --no-daemon --yes
. /root/.nix-profile/etc/profile.d/nix.sh

nix-shell -p nixos-install-tools --run "nixos-generate-config --root /mnt"

cat > /mnt/etc/nixos/configuration.nix <<EOF
{ config, pkgs, ... }:

{
  imports = [ ./hardware-configuration.nix ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.hostName = "$HOSTNAME";
  networking.useDHCP = true;

  services.openssh.enable = true;
  users.users.root.openssh.authorizedKeys.keys = [
    "$SSH_KEY"
  ];

  time.timeZone = "UTC";
  system.stateVersion = "$STATE_VERSION";
}
EOF

nix-shell -p nixos-install-tools --run "nixos-install --no-root-passwd"

echo "NixOS installation complete. Reboot and disable rescue mode."
