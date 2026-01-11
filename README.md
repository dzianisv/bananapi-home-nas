# BananaPi Home NAS

Turn your BananaPi into a fast home NAS with printer sharing.


## Base Image

https://sd-card-images.johang.se/boards/banana_pi_m1.html

```
gzcat boot-banana_pi_m1.bin.gz debian-bookworm-armhf-uu3foo.bin.gz | sudo dd bs=1M of=/dev/disk5 
```

## Quick Setup

```bash
ssh root@your-bananapi-ip
curl -O https://raw.githubusercontent.com/dzianisv/bananapi-home-nas/master/setup-bananapi-nas.sh
chmod +x setup-bananapi-nas.sh
sudo ./setup-bananapi-nas.sh
```

## Features

- **SMB/AFP file sharing** - Works with Windows, Mac, Linux
- **DLNA/UPnP media streaming** - Stream to Smart TVs, game consoles, media players
- **Auto-discovery** - Shows up in network browsers
- **Printer sharing** - Kyocera FS-1040 support via CUPS
- **SATA disk support** - 750GB internal storage with auto-mount
- **Performance optimized** - 30x speed improvement (from 1MB/s to 30MB/s)

## Access Your NAS

- **Windows:** `\\BANANAPI` or `\\<IP-address>`
- **Mac:** `smb://BANANAPI.local` or `afp://BANANAPI.local`
- **Media Streaming:** `http://<IP-address>:8200` (DLNA/UPnP)
- **Printer:** `http://<IP-address>:631`

## Commands

```bash
./setup-bananapi-nas.sh           # Full setup
./setup-bananapi-nas.sh status    # Check services
./setup-bananapi-nas.sh performance # Optimize speed only
./switch-to-readonly.sh           # Switch filesystem to readonly mode
./recover-readonly.sh             # Emergency recovery from readonly issues
./revert-to-readwrite.sh          # Revert from readonly back to read-write
./test-printer.sh                  # Test printer
```

## Troubleshooting

**SATA disk not mounting?**

The SATA disk may have I/O errors on first boot. Solution:
```bash
# Rescan SATA bus
echo 1 > /sys/block/sdc/device/delete
sleep 3
echo '0 0 0' > /sys/class/scsi_host/host0/scan
sleep 5

# Mount the disk
mkdir -p /media/HDD750GB
mount -t exfat /dev/sda2 /media/HDD750GB

# Verify
df -h | grep HDD750GB
```

The disk should now appear as `/dev/sda` instead of `/dev/sdc` and mount successfully. This is automatically handled by the setup script.

**Check disk health:**
```bash
smartctl -H /dev/sda
```

**Printer not working?**
```bash
modprobe usblp
systemctl restart cups
```

**Slow transfers?**
```bash
./setup-bananapi-nas.sh performance
```

**Check performance:**
```bash
nas-performance-check.sh
```

**Switch to readonly filesystem:**
```bash
sudo ./switch-to-readonly.sh
sudo reboot
```

**Emergency recovery if board won't boot:**
```bash
# Boot from live USB, then:
sudo ./recover-readonly.sh
```

**Revert from readonly to read-write:**
```bash
sudo /usr/local/bin/revert-to-readwrite.sh
sudo reboot
```

## Readonly Filesystem Mode

The readonly filesystem mode mounts the root filesystem as readonly at boot time and uses tmpfs (RAM) for essential writable directories. This is useful for:

- **Increased reliability** - Prevents filesystem corruption from power failures
- **Extended SD card life** - Reduces wear on flash storage
- **Security** - Makes it harder for malware to persist

### How it works:
- **Root filesystem (`/`)** is mounted readonly at boot
- **Essential directories** (`/var/log`, `/var/run`, `/tmp`, etc.) use RAM-based tmpfs
- **Storage mounts** (`/media/HDD750GB`) remain fully writable
- **System changes don't persist** across reboots

### Important notes:
- **Logs and temporary files are stored in RAM** - lost on reboot
- **Package installations won't persist** - make all changes before switching
- **Configuration changes should be made before switching to readonly**

To switch back to read-write mode, use the revert script and reboot.

**Media not showing up in DLNA?**
```bash
# Force media rescan
minidlnad -R
systemctl restart minidlna

# Check status
systemctl status minidlna
```