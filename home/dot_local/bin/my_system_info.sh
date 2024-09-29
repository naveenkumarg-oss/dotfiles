#!/bin/bash

# Get OS Version and Kernel version
OS_VERSION=$(lsb_release -d | cut -f2-)
KERNEL_VERSION=$(uname -r)

# Print OS Version and Kernel version
echo "Operating System: $OS_VERSION"
echo "Kernel Version: $KERNEL_VERSION"

# Get CPU Architecture
CPU_ARCH=$(lscpu | grep "Architecture" | awk '{print $2}')

# Print CPU Architecture
echo "CPU Architecture: $CPU_ARCH"

# Get CPU Description
CPU_DESC=$(lscpu | grep "Model name" | cut -d':' -f2 | xargs)

# Print CPU description
echo "CPU Description: $CPU_DESC"

# Get CPU Cores and Threads
CORES=$(lscpu | grep "Core(s) per socket" | awk '{print $4}')
THREADS=$(lscpu | grep "Thread(s) per core" | awk '{print $4}')

# Print CPU Cores and Threads
echo "Total CPU Cores: $(nproc --all)"
echo "CPU Cores: $CORES"
echo "CPU Threads: $THREADS"

# Get RAM Information
RAM=$(free -m | awk '/Mem:/{print $2}')
RAM_IN_USE=$(free -m | awk '/Mem:/{print $3}')
RAM_FREE=$(free -m | awk '/Mem:/{print $4}')

# Print RAM Information
free -m | grep -v total | awk '
    /Mem:/ {print "Total RAM: " $2 " MB\nUsed RAM: " $3 " MB\nFree RAM: " $4 " MB"}
    /Swap:/ {print "Total Swap: " $2 " MB\nUsed Swap: " $3 " MB\nFree Swap: " $4 " MB"}'
