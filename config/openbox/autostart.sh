#!/bin/bash
xmodmap ~/.Xmodmap &
xset r rate 220 30 &
xset dpms 300 600 600 &
xrdb ~/.Xresources &
xfce4-volumed &
xfce4-power-manager &
#$HOME/bin/keyserver &
feh --no-xinerama --bg-scale images/Backgrounds/mandolux-basil-lr-1920.jpg &
