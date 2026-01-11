#!/bin/bash

echo 1 > /sys/block/sdc/device/delete; echo '0 0 0' > /sys/class/scsi_host/host0/scan
