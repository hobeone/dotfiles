#!/bin/bash -e

~/bin/keyboard-settings &
~/bin/file-inotify /tmp/keyboard.lock ~/bin/keyboard-settings &  # Triggered by udev rule

~/bin/synclient.sh &

~/bin/start-xss-lock &
