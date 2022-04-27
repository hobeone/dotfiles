#!/bin/bash -ex

tmux new-session \; \
split-window -v \; \
select-pane -t 0 \; \
resize-pane -y 15 \; \
split-window -h \; \
select-pane -t 0 \; \
send-keys 'watch sensors coretemp-isa-0000 thinkpad-isa-0000' C-m \; \
select-pane -t 1 \; \
split-window -v \; \
select-pane -t 1 \; \
send-keys 'watch -n 1 cat /sys/devices/virtual/powercap/intel-rapl-mmio/intel-rapl-mmio\:0/constraint_0_power_limit_uw' C-m \; \
resize-pane -y 5 \; \
select-pane -t 2 \; \
send-keys 'intel_gpu_top' C-m \; \
select-pane -t 3 \; \
send-keys 'htop' C-m \; set -g mouse on
