#!/bin/bash -ex

gsettings set org.gnome.desktop.interface enable-animations false
gsettings set org.gnome.desktop.peripherals.keyboard repeat-interval 30
gsettings set org.gnome.desktop.peripherals.keyboard delay 220
gsettings set org.gnome.desktop.wm.preferences mouse-button-modifier "'<Alt>'"
