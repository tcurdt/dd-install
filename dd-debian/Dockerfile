FROM debian:trixie-20260505
WORKDIR /work

RUN echo "deb http://deb.debian.org/debian trixie contrib" > /etc/apt/sources.list.d/contrib.list

RUN apt-get update && apt-get install -y \
  debootstrap \
  parted \
  btrfs-progs \
  xfsprogs \
  zfsutils-linux \
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
