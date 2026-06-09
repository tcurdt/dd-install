FROM alpine:3.24
WORKDIR /work

RUN apk add --no-cache \
  bash \
  parted \
  btrfs-progs \
  e2fsprogs \
  xfsprogs \
  zfs \
  dosfstools \
  multipath-tools \
  qemu-img \
  zstd \
  curl \
  util-linux \
  coreutils \
  mkinitfs \
  linux-virt

# install grub without scripts to avoid grub-probe failing on overlay filesystem
RUN apk add --no-cache --no-scripts grub grub-bios grub-efi

COPY build.sh /work/build.sh
RUN chmod +x /work/build.sh

CMD ["/work/build.sh"]
