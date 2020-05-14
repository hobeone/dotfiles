#!/bin/bash

~/bin/keyboard-settings &
~/bin/file-inotify /tmp/keyboard.lock ~/bin/keyboard-settings &  # Triggered by udev rule

