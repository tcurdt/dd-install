#!/bin/bash
set -euxo pipefail

TARGET_DISK="/dev/sda"
SSH_KEY="ssh-ed25519 AAAA...yourkey..."
HOSTNAME="hetzner"
STATE_VERSION="25.11"

# partition (GPT with BIOS boot partition for Hetzner)
parted -s "$TARGET_DISK" -- mklabel gpt
parted -s "$TARGET_DISK" -- mkpart bios 1MiB 2MiB
parted -s "$TARGET_DISK" -- set 1 bios_grub on
parted -s "$TARGET_DISK" -- mkpart primary ext4 2MiB 100%
partprobe "$TARGET_DISK"

# format
mkfs.ext4 -F "${TARGET_DISK}2"

# mount for chroot
mount "${TARGET_DISK}2" /mnt

# rescue workaround (ignore errors on re-run)
groupadd nixbld || true
for i in $(seq 1 10); do
  useradd -g nixbld -G nixbld -M -N -r -d /var/empty -s /sbin/nologin nixbld$i || true
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

  boot.loader.grub.enable = true;
  boot.loader.grub.device = "$TARGET_DISK";

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
