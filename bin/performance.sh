#!/bin/sh
for d in 0 1 2 3 4 5 6 7 ; do
  echo performance | sudo tee /sys/devices/system/cpu/cpu${d}/cpufreq/scaling_governor
done

