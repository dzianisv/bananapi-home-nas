#!/bin/bash

# Emergency recovery script for Banana Pi readonly filesystem issues
# Run this from a live USB or chroot environment if the board won't boot

set -e

echo "=== Banana Pi Readonly Filesystem Recovery ==="
echo ""

# Mount essential filesystems if not already mounted
if ! mountpoint -q /proc; then
    mount -t proc proc /proc
fi
if ! mountpoint -q /sys; then
    mount -t sysfs sys /sys
fi
if ! mountpoint -q /dev; then
    mount -t devtmpfs devtmpfs /dev
fi

echo "1. Checking current mount status..."
mount | grep -E "(sd|mmc|root)" || echo "No root filesystem mounted"

echo ""
echo "2. Finding root partition..."
# Try to find the root partition
ROOT_DEV=""
for dev in /dev/sd* /dev/mmcblk*; do
    if [ -b "$dev" ]; then
        if blkid "$dev" | grep -q "LABEL=\"rootfs\""; then
            ROOT_DEV="$dev"
            break
        fi
    fi
done

if [ -z "$ROOT_DEV" ]; then
    echo "Could not find root partition automatically."
    echo "Please specify the root device (e.g., /dev/sda2 or /dev/mmcblk0p2):"
    read -r ROOT_DEV
fi

echo "Found root device: $ROOT_DEV"

echo ""
echo "3. Mounting root filesystem read-write..."
mkdir -p /mnt/root
mount -t ext4 "$ROOT_DEV" /mnt/root -o rw

echo ""
echo "4. Restoring backups..."

# Restore fstab
if ls /mnt/root/etc/fstab.backup.* 2>/dev/null; then
    LATEST_BACKUP=$(ls -t /mnt/root/etc/fstab.backup.* | head -1)
    cp "$LATEST_BACKUP" /mnt/root/etc/fstab
    echo "Restored fstab from $LATEST_BACKUP"
else
    echo "No fstab backup found"
fi

# Restore boot parameters
if ls /mnt/root/boot/boot.cmd.backup.* 2>/dev/null; then
    LATEST_BACKUP=$(ls -t /mnt/root/boot/boot.cmd.backup.* | head -1)
    cp "$LATEST_BACKUP" /mnt/root/boot/boot.cmd
    echo "Restored boot.cmd from $LATEST_BACKUP"
    # Recompile boot.scr if mkimage is available
    if command -v mkimage >/dev/null 2>&1; then
        mkimage -C none -A arm -T script -d /mnt/root/boot/boot.cmd /mnt/root/boot/boot.scr
        echo "Recompiled boot.scr"
    fi
elif ls /mnt/root/boot/cmdline.txt.backup.* 2>/dev/null; then
    LATEST_BACKUP=$(ls -t /mnt/root/boot/cmdline.txt.backup.* | head -1)
    cp "$LATEST_BACKUP" /mnt/root/boot/cmdline.txt
    echo "Restored cmdline.txt from $LATEST_BACKUP"
else
    echo "No boot parameter backup found"
fi

# Remove readonly init scripts
if [ -f /mnt/root/etc/init.d/setup-readonly ]; then
    chroot /mnt/root update-rc.d setup-readonly remove 2>/dev/null || true
    rm -f /mnt/root/etc/init.d/setup-readonly
    echo "Removed readonly init script"
fi

if [ -f /mnt/root/etc/init.d/setup-overlay ]; then
    chroot /mnt/root update-rc.d setup-overlay remove 2>/dev/null || true
    rm -f /mnt/root/etc/init.d/setup-overlay
    echo "Removed overlay init script"
fi

echo ""
echo "5. Unmounting..."
umount /mnt/root

echo ""
echo "=== Recovery Complete ==="
echo "The Banana Pi should now boot normally."
echo "Remove this recovery media and reboot the Banana Pi."