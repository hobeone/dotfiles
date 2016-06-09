#!/bin/bash
/usr/lib/policykit-1-gnome/polkit-gnome-authentication-agent-1 &
eval $(gnome-keyring-daemon -s --components=pkcs11,secrets,ssh,gpg) &
export SSH_AUTH_SOCK
gsettings set com.canonical.desktop.interface scrollbar-mode normal &
xinput set-prop 11 "Device Enabled" 1 &
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
#xinput set-button-map "Kingsis Peripherals Evoluent VerticalMouse 4" 1 3 8 4 5 6 7 8 2 10 11 12 13 14
if [[ -e ~/.config/openbox/autostart.local.sh ]]; then
  ~/.config/openbox/autostart.local.sh
fi
