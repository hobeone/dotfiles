#!/bin/bash -e

# Set thinkpad laptop touchpad settings
~/bin/synclient.sh &

python3 /usr/share/goobuntu-indicator/goobuntu_indicator.py &
