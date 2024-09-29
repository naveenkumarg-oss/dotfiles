#!/bin/bash

# OS version
echo "OS Version:"
lsb_release -d | cut -f2-

# Kernel version
echo -e "\nKernel Version:"
uname -r

# CPU Architecture
echo -e "\nCPU Architecture:"
lscpu | grep "Architecture" | awk '{print $2}'

# CPU description
echo -e "\nCPU Description:"
lscpu | grep "Model name" | cut -d':' -f2- | sed 's/^[ \t]*//'

# CPU Cores
echo -e "\nCPU Cores:"
nproc --all

# CPU Threads
echo -e "\nCPU Threads:"
lscpu | grep "Thread(s) per core" | awk '{print $4}'

# RAM Information
echo -e "\nRAM Information:"
free -h | grep -v total | awk '
    /Mem:/ {print "Total RAM: " $2 "\nUsed RAM: " $3 "\nFree RAM: " $4}
    /Swap:/ {print "Total Swap: " $2 "\nUsed Swap: " $3 "\nFree Swap: " $4}'
