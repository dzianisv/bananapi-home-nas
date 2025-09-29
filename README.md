# Banana Pi Home NAS and Print Server

Complete setup scripts and configuration files for turning a Banana Pi into a home NAS with printer sharing capabilities.

## Features

- **SMB/CIFS File Sharing** - Windows, Mac, and Linux compatible
- **AFP Support** - Native Apple File Protocol for Mac
- **Network Discovery** - Automatic discovery on Windows 10/11
- **Printer Sharing** - CUPS-based printer sharing (Kyocera FS-1040)
- **Guest Access** - No authentication required for shares
- **Performance Optimized** - Tuned for home network speeds

## Quick Start

### 1. Copy Scripts to Banana Pi

```bash
# SSH into Banana Pi
ssh root@100.72.20.32

# Make scripts executable
chmod +x *.sh
```

### 2. Run the Complete Setup

```bash
# Run the all-in-one setup script
sudo ./setup-bananapi-nas.sh
```

This will:
- Install and configure Samba for file sharing
- Setup WSDD for Windows 10/11 discovery
- Configure Avahi for mDNS/Bonjour
- Setup Netatalk for AFP (Mac support)
- Configure CUPS and Kyocera FS-1040 printer
- Open necessary firewall ports
- Create test files in shares

## Individual Setup Scripts

| Script | Purpose |
|--------|---------|
| `setup-bananapi-nas.sh` | Complete NAS and printer setup with performance optimizations |
| `tune-performance.sh` | Standalone performance optimization script |
| `setup-printer.sh` | Kyocera FS-1040 printer only |
| `setup-printer-sharing.sh` | AFP/SMB sharing setup |
| `setup_shares.sh` | Basic share configuration |

## Network Access

### Windows
- Open File Explorer
- In address bar type: `\\BANANAPI` or `\\192.168.43.131`
- Shares appear automatically (no login required)

### Mac
- Finder → Go → Connect to Server
- SMB: `smb://BANANAPI.local` or `smb://192.168.43.131`
- AFP: `afp://BANANAPI.local` or `afp://192.168.43.131`

### Linux
- File Manager → Other Locations
- Enter: `smb://BANANAPI.local` or `smb://192.168.43.131`

### Android
- Use file manager like CX File Explorer
- Add SMB server: `192.168.43.131`
- Shares: `HDD750GB` or `Dzianis-2`
- Leave username/password blank

## Available Shares

| Share Name | Path | Size | Description |
|------------|------|------|-------------|
| HDD750GB | /media/HDD750GB | 750GB | External USB HDD |
| Dzianis-2 | /media/Dzianis-2 | 4.5TB | External Storage |

## Printer Access

### Web Interface
- URL: `http://192.168.43.131:631`
- Printer: Kyocera_FS1040

### Windows
- Settings → Printers & scanners → Add printer
- Auto-discovers "Kyocera_FS1040 on BANANAPI"

### Mac
- System Preferences → Printers & Scanners
- Click + → Select "Kyocera_FS1040 @ BANANAPI"

## Configuration Files

| File | Purpose |
|------|---------|
| `config/smb.conf` | Optimized Samba configuration |
| `config/wsdd.service` | Windows discovery service |

## Services Status

Check all services:
```bash
sudo ./setup-bananapi-nas.sh status
```

Individual services:
```bash
sudo systemctl status smbd nmbd wsdd avahi-daemon cups
```

## Troubleshooting

### Windows Can't Find NAS
1. Ensure network discovery is enabled in Windows
2. Try direct IP: `\\192.168.43.131`
3. Check firewall: `sudo iptables -L`

### Printer Issues
```bash
# Check status
sudo ./setup-printer.sh -s

# Clean queue
sudo ./setup-printer.sh -c

# Reinstall
sudo ./setup-printer.sh -r
```

### Permission Errors
```bash
# Fix permissions
sudo chown -R engineer:engineer /media/HDD750GB
sudo chmod -R 775 /media/HDD750GB
```

## Backup

System backup created at:
```
/media/Dzianis-2/bananapi-rootfs-backup-*.img
```

## Ports Used

| Port | Protocol | Service |
|------|----------|---------|
| 139,445 | TCP | SMB/CIFS |
| 137,138 | UDP | NetBIOS |
| 548 | TCP | AFP |
| 631 | TCP | CUPS |
| 5353 | UDP | mDNS |
| 5357 | TCP | WSDD |

## Performance

### Automatic Optimizations
The setup script includes extensive performance tuning:

**Network Optimizations:**
- Force SMB3 protocol for best performance
- 512KB socket buffers (up from 64KB)
- TCP_NODELAY for low latency
- Kernel network buffer tuning (128MB)
- Disabled TCP timestamps and SACK

**Storage Optimizations:**
- `noatime` mount option on external drives
- Optimized dirty page ratios (5%/2%)
- Write cache enabled (512KB)
- Async I/O with size=1 for better throughput

**System Optimizations:**
- Reduced SMB logging overhead
- Disabled oplocks for stability
- CPU governor set to performance
- Unnecessary services disabled

### Expected Transfer Speeds
After optimization:
- **USB 2.0 drives**: 15-25 MB/s
- **USB 3.0 drives**: 30-80 MB/s
- **Network maximum**: ~110 MB/s (Gigabit)

*Before optimization: ~1 MB/s*
*After optimization: 15-30 MB/s typical*

### Manual Performance Tuning
Run the performance tuning script for additional optimization:
```bash
sudo ./tune-performance.sh
```

### Performance Monitoring
Check current performance:
```bash
# Quick performance check
nas-performance-check.sh

# Test disk write speed
dd if=/dev/zero of=/media/Dzianis-2/test bs=1M count=100 conv=fdatasync

# Monitor SMB connections
smbstatus -b

# Check system load
htop
```

### Troubleshooting Slow Transfers
1. **Check if optimizations are applied**:
```bash
sysctl net.core.rmem_max
# Should show: 134217728
```

2. **Verify SMB protocol version**:
```bash
testparm -s | grep "server min protocol"
# Should show: SMB3
```

3. **Check mount options**:
```bash
mount | grep media
# Should include: noatime
```

4. **If still slow**, run:
```bash
sudo ./tune-performance.sh
```