{ lib, ... }:
{
  disko.devices = {
    disk.main = {
      device = lib.mkDefault "/dev/sda";
      type = "disk";
      imageSize = "6G"; # must be larger than sum of partitions
      content = {
        type = "gpt";
        partitions = {
          boot = {
            size = "1M";
            type = "EF02"; # BIOS boot partition for GRUB
          };
          root = {
            size = "4G";
            content = {
              type = "filesystem";
              format = "ext4";
              mountpoint = "/";
              mountOptions = [ "noatime" ];
              extraArgs = [
                "-L"
                "nixos"
              ]; # filesystem label
            };
          };
          varlib = {
            size = "100%";
            content = {
              type = "zfs";
              pool = "varlib";
            };
          };
        };
      };
    };

    zpool.varlib = {
      type = "zpool";
      rootFsOptions = {
        atime = "off";
        compression = "lz4";
        xattr = "sa";
        acltype = "posixacl";
      };
      datasets = {
        "data" = {
          type = "zfs_fs";
          mountpoint = "/var/lib";
          options.mountpoint = "legacy";
        };
      };
    };
  };
}
