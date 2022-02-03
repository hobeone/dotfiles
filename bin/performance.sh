#!/bin/bash -ex
for d in 0 1 2 3 4 5 6 7 ; do
  echo performance | sudo tee /sys/devices/system/cpu/cpu${d}/cpufreq/scaling_governor
done


# Requires intel-gpu-tools package
# Set's GPU clock to max
sudo intel_gpu_frequency -m

# Set's power limit to max (on Lenovo X1 Gen 9)
echo 64000000 | sudo tee /sys/devices/virtual/powercap/intel-rapl-mmio/intel-rapl-mmio\:0/constraint_0_power_limit_u
