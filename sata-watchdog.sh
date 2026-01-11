#!/bin/bash

MOUNT_POINT="/media/HDD750GB"
UUID="6394-CC61"
LOG_FILE="/var/log/sata-watchdog.log"

log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

check_and_remount() {
    if ! mountpoint -q "$MOUNT_POINT"; then
        log_message "WARNING: $MOUNT_POINT is not mounted"
        
        DEVICE=$(blkid -U "$UUID")
        
        if [ -n "$DEVICE" ] && [ -b "$DEVICE" ]; then
            log_message "Device with UUID $UUID found at $DEVICE, attempting to mount..."
            mkdir -p "$MOUNT_POINT"
            if mount -U "$UUID" "$MOUNT_POINT"; then
                log_message "SUCCESS: Mounted UUID $UUID to $MOUNT_POINT"
            else
                log_message "ERROR: Failed to mount UUID $UUID"
            fi
        else
            log_message "ERROR: Device with UUID $UUID not found"
            log_message "Attempting USB/SCSI rescan..."
            
            for host in /sys/class/scsi_host/host*; do
                if [ -e "$host/scan" ]; then
                    echo "- - -" > "$host/scan" 2>/dev/null
                fi
            done
            
            sleep 5
            
            DEVICE=$(blkid -U "$UUID")
            if [ -n "$DEVICE" ] && [ -b "$DEVICE" ]; then
                log_message "Device found after rescan at $DEVICE, attempting to mount..."
                mkdir -p "$MOUNT_POINT"
                if mount -U "$UUID" "$MOUNT_POINT"; then
                    log_message "SUCCESS: Mounted UUID $UUID to $MOUNT_POINT after rescan"
                else
                    log_message "ERROR: Failed to mount UUID $UUID after rescan"
                fi
            else
                log_message "ERROR: Device with UUID $UUID still not found after rescan"
            fi
        fi
    else
        log_message "OK: $MOUNT_POINT is already mounted"
    fi
}

log_message "SATA Watchdog started"
check_and_remount
