{ lib, ... }:
{
  disko.devices = {
    disk.main = {
      device = lib.mkDefault "/dev/sda";
      type = "disk";
      imageSize = "6G";  # must be larger than sum of partitions
      content = {
        type = "gpt";
        partitions = {
          esp = {
            size = "256M";
            type = "EF00";  # EFI System Partition
            content = {
              type = "filesystem";
              format = "vfat";
              mountpoint = "/boot";
            };
          };
          root = {
            size = "4G";
            content = {
              type = "filesystem";
              format = "ext4";
              mountpoint = "/";
              mountOptions = [ "noatime" ];
              extraArgs = [ "-L" "nixos" ];  # filesystem label
            };
          };
          varlib = {
            size = "100%";
            content = {
              type = "filesystem";
              format = "ext4";
              mountpoint = "/var/lib";
              mountOptions = [ "noatime" ];
              extraArgs = [ "-L" "varlib" ];  # filesystem label
            };
          };
        };
      };
    };
  };
}
