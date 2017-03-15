#!/bin/bash -ex
MTP_DIR=~/mtp
FIT_DIR="$MTP_DIR/USB storage/exports"
SYNC_DIR=~/garmin/wahoo
mkdir -p "$SYNC_DIR"
jmtpfs "$MTP_DIR"
pushd "$FIT_DIR"
rsync -rlvP --size-only ./ "$SYNC_DIR"
popd
fusermount -u "$MTP_DIR"
