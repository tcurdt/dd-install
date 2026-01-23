#!/usr/bin/env bash
# usage:
#   ./docker.sh                                       # defaults
#   VERSION=3.21 BOOT=bios ARCH=x86_64 ./docker.sh   # defaults explicit
#   VERSION=3.20 ./docker.sh                          # different version

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

VERSION="${VERSION:-3.21}"
BOOT="${BOOT:-bios}"
ARCH="${ARCH:-x86_64}"
SSH_PUBKEY_FILE="${SSH_PUBKEY_FILE:-$HOME/.ssh/id_ed25519.pub}"
OUTPUT_DIR="${OUTPUT_DIR:-${DIR}/result}"

set -Euo pipefail

mkdir -p "$OUTPUT_DIR"

docker build \
  --platform linux/amd64 \
  -t alpine-dd-builder \
  "$DIR"

docker run --rm --privileged \
  -v "$OUTPUT_DIR:/result" \
  -v "$SSH_PUBKEY_FILE:/etc/ssh.pub:ro" \
  -e VERSION="$VERSION" \
  -e BOOT="$BOOT" \
  -e ARCH="$ARCH" \
  -e SSH_PUBKEY_FILE="/etc/ssh.pub" \
  alpine-dd-builder /work/build.sh
