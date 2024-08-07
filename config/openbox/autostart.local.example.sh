#!/bin/bash -e

~/bin/keyboard-settings &
~/bin/file-inotify /tmp/keyboard.lock ~/bin/keyboard-settings &  # Triggered by udev rule
~/dotfiles/synclient.sh &

xfconf-query -c xfce4-session -p /general/LockCommand -s 'xset s activate' &
~/dotfiles/bin/start-xss-lock &
