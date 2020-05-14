#!/bin/bash

# Copy udev scripts over to handle USB KVM switch switching keyboards
# needs to be run as root

if hash inotifywait 2>/dev/null; then
  echo "Found inotifywait command installed"
else
  echo "Didn't find inotifywait, please install.  apt install inotify-tools"
fi

$ECHO cp -v udev/99-keyboard.rules /etc/udev/rules.d/99-keyboard.rules
$ECHO cp -v bin/keyboard-udev /usr/local/bin/keyboard-udev
