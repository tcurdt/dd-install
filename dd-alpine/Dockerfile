FROM alpine:3.21
WORKDIR /work

RUN apk add --no-cache \
  bash \
  parted \
  btrfs-progs \
  e2fsprogs \
  dosfstools \
  grub \
  grub-bios \
  grub-efi \
  multipath-tools \
  qemu-img \
  zstd \
  curl \
  util-linux \
  coreutils \
  mkinitfs \
  linux-virt

COPY build.sh /work/build.sh
RUN chmod +x /work/build.sh

CMD ["/work/build.sh"]
