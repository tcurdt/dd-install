# ZFS for /var/lib

Switch the `/var/lib` partition from ext4 to ZFS across all three distros.

## Current State

All three distros share the same partition layout:
- BIOS boot (1-3MiB)
- btrfs root with `@rootfs` subvolume (3MiB - 4GiB)
- ext4 `/var/lib` (4GiB - 100%)

`/var/lib` is mounted via UUID in fstab.

## Target State

Replace the ext4 `/var/lib` partition with a ZFS pool (`varlib`) with a single dataset mounted at `/var/lib`. Fstab entry removed — ZFS manages its own mount.

## Docker

Docker detects ZFS and switches to the `zfs` storage driver, which is worse than `overlay2`. Fix by adding to `/etc/docker/daemon.json`:

```json
{"storage-driver": "overlay2"}
```

This must be written into the image at build time. Also requires `zfs set overlay=on varlib` on the dataset (supported in ZFS 2.2+).

---

## Alpine (`dd-alpine/build.sh`)

**Packages** — add to `apk add`:
```
zfs
```

**mkinitfs** — add `zfs` to features:
```
features="ata base btrfs ext4 zfs keymap kms mmc nvme scsi usb virtio"
```

**Format** — replace `mkfs.ext4 -F "$PART3"` with:
```bash
zpool create -o ashift=12 -O mountpoint=/var/lib -O atime=off varlib "$PART3"
zfs set overlay=on varlib
```

**Mount** — replace `mount "$PART3" /mnt/var/lib` with:
```bash
zpool export varlib
zpool import -R /mnt varlib
```

**fstab** — remove the `/var/lib` UUID line entirely.

**OpenRC** — add:
```bash
chroot /mnt rc-update add zfs-import boot
chroot /mnt rc-update add zfs-mount boot
```

**Modules** — add `zfs` to `/etc/modules`.

**Unmount** — replace `umount /mnt/var/lib` with:
```bash
zpool export varlib
```

---

## Debian (`dd-debian/build.sh`)

**Packages** — add to `apt-get install`:
```
zfsutils-linux
```

**Format** — replace `mkfs.ext4 -F "$PART3"` with:
```bash
zpool create -o ashift=12 -O mountpoint=/var/lib -O atime=off varlib "$PART3"
zfs set overlay=on varlib
```

**Mount** — replace `mount "$PART3" /mnt/var/lib` with:
```bash
zpool export varlib
zpool import -R /mnt varlib
```

**fstab** — remove the `/var/lib` UUID line entirely.

**systemd** — add:
```bash
chroot /mnt systemctl enable zfs-import-cache zfs-mount
```

**Unmount** — replace `umount /mnt/var/lib` with:
```bash
zpool export varlib
```

---

## NixOS (`dd-nixos/disco-bios.nix`)

**Partition** — replace the `varlib` partition content:
```nix
varlib = {
  size = "100%";
  content = {
    type = "zpool";
    name = "varlib";
    options = {
      ashift = "12";
    };
    rootFsOptions = {
      mountpoint = "none";
      atime = "off";
    };
    datasets.varlib = {
      type = "zfs_fs";
      options = {
        mountpoint = "/var/lib";
        "com.sun:auto-snapshot" = "false";
      };
    };
  };
};
```

**System config** — add to `flake.nix` or a shared config:
```nix
boot.supportedFilesystems = [ "zfs" ];
networking.hostId = "...";  # required by ZFS, generate with: head -c4 /dev/urandom | od -A none -t x4 | tr -d ' '
virtualisation.docker.daemon.settings = {
  storage-driver = "overlay2";
};
```

---

## Notes

- Pool name `varlib` is consistent across distros for clarity.
- `ashift=12` targets 4K sector alignment (correct for most modern storage).
- `overlay=on` is required for Docker `overlay2` on ZFS (ZFS 2.2+).
- The pool cachefile (`/etc/zfs/zpool.cache`) is written automatically by `zpool create` and is what the boot-time import services use — no manual setup needed.
- Alpine ZFS package version in 3.21 community: `2.2.x` — `overlay=on` is supported.
- Debian trixie ships ZFS via DKMS (`zfsutils-linux`), version `2.2.x`.
