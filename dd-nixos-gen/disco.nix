{ lib, ... }:
{
  disko.devices = {
    disk.disk1 = {
      device = lib.mkDefault "/dev/sda";
      type = "disk";
      content = {
        type = "table";
        format = "msdos";
        partitions = [
          {
            name = "root";
            size = "4G";
            content = {
              type = "filesystem";
              format = "btrfs";
              # extraArgs = [ "-f" "-O block-group-tree" ];
              extraArgs = [ "-f" ];
              mountpoint = "/";
              mountOptions = [ "compress=zstd" "noatime" ];
            };
          }
          {
            name = "var-lib";
            size = "100%";
            content = {
              type = "filesystem";
              format = "ext4";
              mountpoint = "/var/lib";
              mountOptions = [ "noatime" ];
            };
          }
        ];
      };
    };
  };
}
