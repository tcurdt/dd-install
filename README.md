# dd-based server deployment

1. install the script

```
   curl https://raw.githubusercontent.com/tcurdt/dd-install/refs/heads/main/install.sh > install.sh
```

2. run the script pointing to an image

```
   bash install.sh https://nightly.link/tcurdt/dd-install/actions/runs/21321173101/nixos-25.11-cpx.img.zip
   bash install.sh https://nightly.link/tcurdt/dd-install/actions/runs/21321173101/alpine-3.21-cpx.img.zip
   bash install.sh https://nightly.link/tcurdt/dd-install/actions/runs/21321173101/debian-trixie-cpx.img.zip
```

# testing on qemu

1. create the rescue system

   ./qemu.sh init # create disk-rescue.qcow2

2. run the rescue system and install

   ./qemu.sh rescue # run rescue

   install.sh debian-trixie-bios-amd.img.zst # install disk-target.qcow2

3. run the target system

   ./qemu.sh target # run the newly installed system
