#!/bin/bash
xmodmap ~/.Xmodmap &
xset r rate 220 30 &
xset dpms 300 600 600 &
xrdb ~/.Xresources &
xfce4-volumed &
$HOME/bin/keyserver &