#!/bin/bash
set -euo pipefail

# Write dirty pages to disk, then drop pagecache+dentries+inodes (level 3)
# so the "available RAM" reading below isn't inflated by reclaimable cache.
sudo sync
echo 3 | sudo tee /proc/sys/vm/drop_caches >/dev/null

mem=$(LC_ALL=C free | awk '/Mem:/ {print $4}')
swap=$(LC_ALL=C free | awk '/Swap:/ {print $3}')

if [ "$mem" -lt "$swap" ]; then
    echo "ERROR: not enough free RAM (${mem}KB) to hold swap in use (${swap}KB), nothing done" >&2
    exit 1
fi

sudo swapoff -a
sudo swapon -a
