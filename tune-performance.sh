#!/bin/bash

# Banana Pi NAS Performance Tuning Script
# Run this script to optimize system performance for SMB file transfers

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root (sudo)"
    exit 1
fi

print_status "=== Banana Pi NAS Performance Tuning ==="
echo ""

# 1. Apply kernel optimizations
print_status "Applying kernel network and I/O optimizations..."

cat > /etc/sysctl.d/99-nas-performance.conf << 'EOF'
# Network performance optimizations
net.core.rmem_max = 134217728
net.core.wmem_max = 134217728
net.ipv4.tcp_rmem = 4096 87380 134217728
net.ipv4.tcp_wmem = 4096 65536 134217728
net.core.netdev_max_backlog = 30000
net.ipv4.tcp_timestamps = 0
net.ipv4.tcp_sack = 0
net.ipv4.tcp_no_metrics_save = 1
net.ipv4.tcp_congestion_control = htcp

# Disk I/O optimizations
vm.dirty_ratio = 5
vm.dirty_background_ratio = 2
vm.swappiness = 10
vm.vfs_cache_pressure = 50

# File handle limits
fs.file-max = 2097152
fs.nr_open = 1048576
EOF

sysctl -p /etc/sysctl.d/99-nas-performance.conf
print_success "Kernel optimizations applied"

# 2. Optimize SMB configuration
print_status "Checking SMB configuration..."

if [ -f /etc/samba/smb.conf ]; then
    if ! grep -q "socket options = TCP_NODELAY SO_RCVBUF=524288" /etc/samba/smb.conf; then
        print_warning "SMB not optimized. Backing up and updating configuration..."
        cp /etc/samba/smb.conf /etc/samba/smb.conf.backup.perf

        # Update socket options
        sed -i 's/socket options = .*/socket options = TCP_NODELAY SO_RCVBUF=524288 SO_SNDBUF=524288/' /etc/samba/smb.conf

        # Restart SMB
        systemctl restart smbd nmbd
        print_success "SMB configuration optimized"
    else
        print_success "SMB already optimized"
    fi
fi

# 3. Optimize mount options
print_status "Optimizing mount options for external drives..."

# Check and remount Dzianis-2
if mount | grep -q "/media/Dzianis-2"; then
    DEVICE=$(mount | grep "/media/Dzianis-2" | awk '{print $1}')
    print_status "Remounting Dzianis-2 with optimized options..."
    umount /media/Dzianis-2 2>/dev/null || true
    mount -t exfat -o rw,uid=1000,gid=1000,umask=000,iocharset=utf8,noatime $DEVICE /media/Dzianis-2
    print_success "Dzianis-2 remounted with noatime"
fi

# Check and remount HDD750GB
if mount | grep -q "/media/HDD750GB"; then
    DEVICE=$(mount | grep "/media/HDD750GB" | awk '{print $1}')
    print_status "Remounting HDD750GB with optimized options..."
    umount /media/HDD750GB 2>/dev/null || true
    mount -o rw,noatime,nodiratime $DEVICE /media/HDD750GB
    print_success "HDD750GB remounted with noatime,nodiratime"
fi

# 4. Disable unnecessary services
print_status "Disabling unnecessary services..."

SERVICES="ModemManager bluetooth snapd"
for service in $SERVICES; do
    if systemctl is-enabled $service 2>/dev/null | grep -q enabled; then
        systemctl disable --now $service 2>/dev/null || true
        print_success "Disabled $service"
    fi
done

# 5. Stop WSDD if running (can be CPU intensive)
print_status "Checking WSDD service..."
if systemctl is-active wsdd >/dev/null 2>&1; then
    print_warning "WSDD is running and may impact performance"
    read -p "Stop WSDD for better performance? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        systemctl stop wsdd
        print_success "WSDD stopped"
    fi
fi

# 6. CPU governor optimization
print_status "Optimizing CPU governor..."
if [ -f /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor ]; then
    echo performance > /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || \
    echo ondemand > /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null
    print_success "CPU governor set to performance mode"
fi

# 7. Test disk performance
print_status "Testing disk write performance..."
echo ""

if [ -d /media/Dzianis-2 ]; then
    print_status "Testing Dzianis-2 write speed..."
    dd if=/dev/zero of=/media/Dzianis-2/speedtest bs=1M count=100 conv=fdatasync 2>&1 | tail -1
    rm -f /media/Dzianis-2/speedtest
fi

if [ -d /media/HDD750GB ]; then
    print_status "Testing HDD750GB write speed..."
    dd if=/dev/zero of=/media/HDD750GB/speedtest bs=1M count=100 conv=fdatasync 2>&1 | tail -1
    rm -f /media/HDD750GB/speedtest
fi

# 8. Show current performance metrics
print_status "Current system performance metrics:"
echo ""
echo "Load average: $(uptime | awk -F'load average:' '{print $2}')"
echo "Memory usage: $(free -h | grep Mem | awk '{print "Used: " $3 " / Total: " $2}')"
echo "Network interface: $(ip link show | grep -E "end0|eth0" | head -1 | awk '{print $2}' | tr -d ':')"
echo "Network speed: $(cat /sys/class/net/end0/speed 2>/dev/null || echo 'Unknown') Mbps"
echo ""

# 9. Create performance monitoring script
print_status "Creating performance monitoring script..."

cat > /usr/local/bin/nas-performance-check.sh << 'EOF'
#!/bin/bash
echo "=== NAS Performance Check ==="
echo "Date: $(date)"
echo ""
echo "SMB Connections:"
smbstatus -b 2>/dev/null | grep -E "192.168|10." | head -5
echo ""
echo "Disk I/O:"
iostat -x 1 2 2>/dev/null | tail -n +4 | head -10 || echo "iostat not available"
echo ""
echo "Network throughput:"
ifstat -i end0 1 1 2>/dev/null || ip -s link show end0 | grep -A1 "RX:"
echo ""
echo "Top processes:"
ps aux | sort -nrk 3,3 | head -5
EOF

chmod +x /usr/local/bin/nas-performance-check.sh
print_success "Performance monitoring script created at /usr/local/bin/nas-performance-check.sh"

print_success "=== Performance Tuning Complete ==="
echo ""
print_status "Expected SMB transfer speeds:"
echo "  - USB 2.0 drives: 15-25 MB/s"
echo "  - USB 3.0 drives: 30-80 MB/s"
echo "  - Network limit: ~110 MB/s (Gigabit)"
echo ""
print_status "To monitor performance, run:"
echo "  nas-performance-check.sh"
echo ""
print_warning "Note: Actual speeds depend on drive type, file sizes, and network conditions"