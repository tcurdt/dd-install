# dd-based server deployment

1. install the script

```
   curl https://raw.githubusercontent.com/tcurdt/dd-install/refs/heads/main/install.sh > install.sh
```

2. run the script pointing to an image

```
   bash install.sh https://github.com/tcurdt/dd-install/releases/download/build-24332928883-1/nixos-25.11-efi-cpx-zfs.img.zst
   bash install.sh https://github.com/tcurdt/dd-install/releases/download/build-24332928883-1/alpine-3.21-efi-cpx-zfs.img.zst
   bash install.sh https://github.com/tcurdt/dd-install/releases/download/build-24332928883-1/debian-trixie-efi-cpx-zfs.img.zst
```

# testing on qemu

1. create the rescue system

   ./qemu.sh init # create disk-rescue.qcow2

2. run the rescue system and install

   ./qemu.sh rescue # run rescue

   install.sh debian-trixie-bios-amd.img.zst # install disk-target.qcow2

3. run the target system

   ./qemu.sh target # run the newly installed system
