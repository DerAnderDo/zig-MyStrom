#!/bin/bash

# Crosscompile
zig build-exe ../src/main.zig -O ReleaseSmall -fstrip -target aarch64-linux

# Move to embedded device
scp main root@192.168.2.24:/home/dietpi/services/myStromer_bin

rm main
rm main.o