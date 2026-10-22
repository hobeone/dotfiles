#!/usr/bin/env bash
while true; do
  xdotool mousemove_relative -- 1 0
  xdotool mousemove_relative -- -1 0
  sleep 60
done
