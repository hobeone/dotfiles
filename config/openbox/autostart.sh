#!/bin/bash
/usr/lib/policykit-1-gnome/polkit-gnome-authentication-agent-1 &
eval $(gnome-keyring-daemon -s --components=pkcs11,secrets,ssh,gpg) &
export SSH_AUTH_SOCK
gsettings set com.canonical.desktop.interface scrollbar-mode normal &
xinput set-prop 11 "Device Enabled" 0 &
xscreensaver &
xmodmap ~/.Xmodmap &
xset r rate 220 30 &
xset dpms 300 600 600 &
xrdb ~/.Xresources &
xfsettingsd --no-daemon &
xfce4-volumed --no-daemon &
xfce4-power-manager --no-daemon &
xfce4-panel &
#$HOME/bin/keyserver &
feh --no-xinerama --bg-scale images/Backgrounds/mandolux-basil-lr-1920.jpg &
