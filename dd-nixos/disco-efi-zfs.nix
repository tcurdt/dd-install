{ lib, ... }:
{
  disko.devices = {
    disk.main = {
      device = lib.mkDefault "/dev/sda";
      type = "disk";
      imageSize = "11G"; # must be larger than sum of partitions
      content = {
        type = "gpt";
        partitions = {
          esp = {
            size = "256M";
            type = "EF00"; # EFI System Partition
            content = {
              type = "filesystem";
              format = "vfat";
              mountpoint = "/boot";
            };
          };
          root = {
            size = "10G";
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
