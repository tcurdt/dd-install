#!/usr/bin/env bash
# usage:
#   ./docker.sh                                   # defaults
#   VERSION=trixie BOOT=bios ARCH=amd ./docker.sh # defaults explicit
#   VERSION=bookworm ./docker.sh                  # different version

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

VERSION="${VERSION:-trixie}"
BOOT="${BOOT:-bios}"
ARCH="${ARCH:-amd}"
SSH_PUBKEY_FILE="${SSH_PUBKEY_FILE:-$HOME/.ssh/id_ed25519.pub}"
OUTPUT_DIR="${OUTPUT_DIR:-${DIR}/result}"

set -Euo pipefail

if [ ! -f "$SSH_PUBKEY_FILE" ]; then
  echo "Error: SSH public key file not found: $SSH_PUBKEY_FILE"
  echo "Please provide a valid SSH public key file via SSH_PUBKEY_FILE environment variable"
  exit 1
fi

mkdir -p "$OUTPUT_DIR"

docker build \
  --platform linux/amd64 \
  -t debian-dd-builder \
  "$DIR"

# docker buildx build \
#   --platform linux/amd64 \
#   -t debian-dd-builder \
#   --load \
#   "$DIR"

docker run --rm --privileged \
  -v "$OUTPUT_DIR:/result" \
  -v "$SSH_PUBKEY_FILE:/etc/ssh.pub:ro" \
  -e VERSION="$VERSION" \
  -e BOOT="$BOOT" \
  -e ARCH="$ARCH" \
  -e SSH_PUBKEY_FILE="/etc/ssh.pub" \
  debian-dd-builder /work/build.sh
