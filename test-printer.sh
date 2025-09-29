#!/bin/bash

# Test Printer Script for Kyocera FS-1040 on Banana Pi

echo "=== Kyocera FS-1040 Printer Test ==="

# Check if printer device exists
if [ ! -e /dev/usb/lp0 ]; then
    echo "ERROR: Printer device not found at /dev/usb/lp0"
    echo "Loading USB printer module..."
    modprobe usblp
    sleep 2

    if [ ! -e /dev/usb/lp0 ]; then
        echo "ERROR: Still no printer device. Check USB connection."
        lsusb | grep -i kyocera
        exit 1
    fi
fi

# Check printer status
echo "Printer Status:"
lpstat -p -d

# Send test print
echo ""
echo "Sending test page..."
echo "Test page from Banana Pi - $(date)" | lp -d Kyocera_FS1040

echo ""
echo "Test print sent!"