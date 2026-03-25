#!/bin/bash -ex

# Copy udev scripts over to handle USB KVM switch switching keyboards
# needs to be run as root
#
# run with ECHO=echo to debug

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if hash inotifywait 2>/dev/null; then
  echo "Found inotifywait command installed"
else
  echo "Didn't find inotifywait, installing"
  $ECHO apt install inotify-tools
fi

$ECHO cp -v "$DOTFILES_DIR/udev/99-keyboard.rules" /etc/udev/rules.d/99-keyboard.rules
$ECHO cp -v "$DOTFILES_DIR/home/bin/keyboard-udev" /usr/local/bin/keyboard-udev
$ECHO udevadm control --reload-rules
