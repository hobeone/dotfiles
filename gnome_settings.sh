#!/bin/bash -ex

gsettings set org.gnome.desktop.interface enable-animations false
gsettings set org.gnome.desktop.peripherals.keyboard repeat-interval 30
gsettings set org.gnome.desktop.peripherals.keyboard delay 220
gsettings set org.gnome.desktop.wm.preferences mouse-button-modifier "'<Alt>'"
gsettings set org.gnome.desktop.wm.keybindings switch-to-workspace-left "['<Control>Left']"
gsettings set org.gnome.desktop.wm.keybindings switch-to-workspace-right "['<Control>Right']"
gsettings set org.gnome.desktop.wm.preferences num-workspaces 2
gsettings set org.gnome.mutter dynamic-workspaces false
gsettings set org.gnome.shell.app-switcher current-workspace-only false
gsettings set org.gnome.desktop.wm.keybindings maximize-vertically "['<Shift><Alt>f']"
gsettings set org.gnome.shell.extensions.dash-to-panel animate-window-launch false
gsettings set org.gnome.shell.extensions.dash-to-panel animate-app-switch false
gsettings set org.gnome.mutter focus-change-on-pointer-rest false
gsettings set org.gnome.shell.extensions.dash-to-panel isolate-workspaces false
gsettings set org.gnome.mutter workspaces-only-on-primary false
gsettings set org.gnome.desktop.interface enable-hot-corners false

