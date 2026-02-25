FROM debian:trixie
WORKDIR /work

RUN apt-get update && apt-get install -y \
  debootstrap \
  parted \
  btrfs-progs \
  dosfstools \
  grub-pc-bin \
  grub-efi-amd64-bin \
  grub2-common \
  kpartx \
  qemu-utils \
  libguestfs-tools \
  zstd \
  curl \
  && rm -rf /var/lib/apt/lists/*

COPY build.sh /work/build.sh
RUN chmod +x /work/build.sh

CMD ["/work/build.sh"]
