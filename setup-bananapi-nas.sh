#!/bin/bash

# Banana Pi NAS and Print Server Setup Script
# This script configures the Banana Pi as a complete home NAS with printer sharing

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration variables
HOSTNAME="BANANAPI"
WORKGROUP="WORKGROUP"
SMB_USER="engineer"
MEDIA_MOUNTS=("/media/HDD750GB" "/media/Dzianis-2")

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root (sudo)"
        exit 1
    fi
}

# Function to install required packages
install_packages() {
    print_status "Installing required packages..."
    
    apt update
    
    # Install all necessary packages
    apt install -y \
        samba \
        samba-common-bin \
        smbclient \
        netatalk \
        avahi-daemon \
        cups \
        cups-filters \
        cups-browsed \
        printer-driver-all \
        ipp-usb \
        python3 \
        python3-pip \
        wget \
        curl \
        ufw
    
    print_success "Packages installed successfully"
}

# Function to configure SMB/Samba
configure_samba() {
    print_status "Configuring Samba for file sharing..."

    # Backup existing config
    if [ -f /etc/samba/smb.conf ]; then
        cp /etc/samba/smb.conf /etc/samba/smb.conf.backup.$(date +%Y%m%d)
    fi

    # Create optimized SMB configuration
    cat > /etc/samba/smb.conf << 'EOF'
[global]
   workgroup = WORKGROUP
   server string = %h server (Samba)

   # Network discovery settings
   netbios name = BANANAPI
   wins support = yes
   local master = yes
   preferred master = yes
   os level = 65

   # Security and authentication
   security = user
   map to guest = Bad User
   guest account = nobody

   # Protocol settings - Force SMB3 for best performance
   server min protocol = SMB3
   client min protocol = SMB2
   client max protocol = SMB3_11

   # High-performance settings
   socket options = TCP_NODELAY SO_RCVBUF=524288 SO_SNDBUF=524288
   use sendfile = yes
   min receivefile size = 16384
   aio read size = 1
   aio write size = 1
   write cache size = 524288
   max xmit = 65536
   dead time = 15
   getwd cache = yes

   # Disable oplocks for better compatibility
   oplocks = no
   level2 oplocks = no
   kernel oplocks = no
   
   # Logging (reduced for performance)
   log file = /var/log/samba/log.%m
   max log size = 50
   log level = 0
   
   # Printer support
   load printers = yes
   printing = cups
   printcap name = cups
   
   # File permissions
   create mask = 0664
   directory mask = 0775
   force create mode = 0664
   force directory mode = 0775
   
   # Browsing
   browseable = yes

[homes]
   comment = Home Directories
   browseable = no
   read only = no
   create mask = 0700
   directory mask = 0700
   valid users = %S

[printers]
   comment = All Printers
   browseable = no
   path = /var/tmp
   printable = yes
   guest ok = no
   read only = yes
   create mask = 0700

[print$]
   comment = Printer Drivers
   path = /var/lib/samba/printers
   browseable = yes
   read only = no
   guest ok = no

[HDD750GB]
   comment = HDD 750GB Storage
   path = /media/HDD750GB
   browseable = yes
   read only = no
   guest ok = yes
   create mask = 0664
   directory mask = 0775
   force user = engineer
   force group = engineer

[Dzianis-2]
   comment = Dzianis-2 Storage
   path = /media/Dzianis-2
   browseable = yes
   read only = no
   guest ok = yes
   create mask = 0664
   directory mask = 0775
   force user = engineer
   force group = engineer
   # Performance optimizations
   strict locking = no
   strict allocate = yes
   allocation roundup size = 4096
EOF
    
    # Restart Samba services
    systemctl restart smbd nmbd
    systemctl enable smbd nmbd
    
    print_success "Samba configured successfully"
}

# Function to install and configure WSDD for Windows 10/11 discovery
configure_wsdd() {
    print_status "Installing WSDD for Windows network discovery..."
    
    # Download wsdd
    wget -O /usr/local/bin/wsdd https://raw.githubusercontent.com/christgau/wsdd/master/src/wsdd.py
    chmod +x /usr/local/bin/wsdd
    
    # Create systemd service for wsdd
    cat > /etc/systemd/system/wsdd.service << 'EOF'
[Unit]
Description=Web Services Dynamic Discovery host daemon
After=network-online.target

[Service]
Type=simple
ExecStart=/usr/bin/python3 /usr/local/bin/wsdd --workgroup WORKGROUP --hostname BANANAPI
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
    
    # Enable and start wsdd
    systemctl daemon-reload
    systemctl enable wsdd
    systemctl start wsdd
    
    print_success "WSDD installed and configured"
}

# Function to configure Avahi for mDNS/Bonjour
configure_avahi() {
    print_status "Configuring Avahi for network discovery..."
    
    # Create SMB service file for Avahi
    mkdir -p /etc/avahi/services
    cat > /etc/avahi/services/smb.service << 'EOF'
<?xml version="1.0" standalone='no'?>
<!DOCTYPE service-group SYSTEM "avahi-service.dtd">
<service-group>
  <name replace-wildcards="yes">%h</name>
  <service>
    <type>_smb._tcp</type>
    <port>445</port>
  </service>
  <service>
    <type>_device-info._tcp</type>
    <port>0</port>
    <txt-record>model=RackMac</txt-record>
  </service>
</service-group>
EOF
    
    # Restart Avahi
    systemctl restart avahi-daemon
    systemctl enable avahi-daemon
    
    print_success "Avahi configured for mDNS discovery"
}

# Function to configure firewall
configure_firewall() {
    print_status "Configuring firewall rules..."
    
    # SMB/CIFS ports
    iptables -A INPUT -p tcp --dport 445 -j ACCEPT
    iptables -A INPUT -p tcp --dport 139 -j ACCEPT
    iptables -A INPUT -p udp --dport 137 -j ACCEPT
    iptables -A INPUT -p udp --dport 138 -j ACCEPT
    
    # WSDD ports
    iptables -A INPUT -p tcp --dport 5357 -j ACCEPT
    iptables -A INPUT -p udp --dport 3702 -j ACCEPT
    
    # AFP/Netatalk port
    iptables -A INPUT -p tcp --dport 548 -j ACCEPT
    
    # CUPS printer sharing
    iptables -A INPUT -p tcp --dport 631 -j ACCEPT
    
    # mDNS/Bonjour
    iptables -A INPUT -p udp --dport 5353 -j ACCEPT
    
    # Save firewall rules
    mkdir -p /etc/iptables
    iptables-save > /etc/iptables/rules.v4
    
    print_success "Firewall configured"
}

# Function to optimize system performance
optimize_system_performance() {
    print_status "Optimizing system performance for NAS operations..."

    # Kernel network optimizations
    cat >> /etc/sysctl.conf << 'EOF'

# Network performance optimizations
net.core.rmem_max = 134217728
net.core.wmem_max = 134217728
net.ipv4.tcp_rmem = 4096 87380 134217728
net.ipv4.tcp_wmem = 4096 65536 134217728
net.core.netdev_max_backlog = 30000
net.ipv4.tcp_timestamps = 0
net.ipv4.tcp_sack = 0

# Disk I/O optimizations
vm.dirty_ratio = 5
vm.dirty_background_ratio = 2
vm.swappiness = 10
EOF

    # Apply settings immediately
    sysctl -p

    # Disable unnecessary services that consume CPU
    systemctl disable --now ModemManager.service 2>/dev/null || true
    systemctl disable --now bluetooth.service 2>/dev/null || true

    # Optimize mount options for external drives
    print_status "Optimizing mount options..."

    # Create mount optimization script
    cat > /usr/local/bin/optimize-mounts.sh << 'EOF'
#!/bin/bash
# Remount external drives with optimized options

# Check if Dzianis-2 is mounted
if mount | grep -q "/media/Dzianis-2"; then
    umount /media/Dzianis-2 2>/dev/null
    mount -t exfat -o rw,uid=1000,gid=1000,umask=000,iocharset=utf8,noatime /dev/sdb1 /media/Dzianis-2 2>/dev/null || \
    mount -t exfat -o rw,uid=1000,gid=1000,umask=000,iocharset=utf8,noatime /dev/sdd1 /media/Dzianis-2 2>/dev/null
fi

# Check if HDD750GB is mounted
if mount | grep -q "/media/HDD750GB"; then
    umount /media/HDD750GB 2>/dev/null
    mount -o rw,noatime,nodiratime /dev/sde2 /media/HDD750GB 2>/dev/null || \
    mount -o rw,noatime,nodiratime /dev/sdc1 /media/HDD750GB 2>/dev/null
fi
EOF

    chmod +x /usr/local/bin/optimize-mounts.sh

    # Run mount optimization
    /usr/local/bin/optimize-mounts.sh

    print_success "System performance optimized"
}

# Function to configure CUPS for printer sharing
configure_cups() {
    print_status "Configuring CUPS for printer sharing..."
    
    # Configure CUPS for network access
    cupsctl --share-printers --remote-admin --remote-any
    
    # Enable CUPS service
    systemctl enable cups
    systemctl restart cups
    
    print_success "CUPS configured for printer sharing"
}

# Function to setup Kyocera printer
setup_kyocera_printer() {
    print_status "Setting up Kyocera FS-1040 printer..."
    
    # Remove any existing printer configuration
    lpadmin -x Kyocera_FS1040 2>/dev/null || true
    
    # Load USB printer module
    modprobe usblp
    echo "usblp" > /etc/modules-load.d/usblp.conf
    
    # Create udev rule for printer permissions
    cat > /etc/udev/rules.d/99-lp-permissions.rules << 'EOF'
KERNEL=="lp*", MODE="0666"
SUBSYSTEM=="usb", ATTR{idVendor}=="0482", ATTR{idProduct}=="0493", MODE="0666"
EOF
    
    # Reload udev rules
    udevadm control --reload-rules
    udevadm trigger
    
    # Wait for device to be ready
    sleep 3
    
    # Add the printer using KPSL driver
    if [ -e /dev/usb/lp0 ]; then
        lpadmin -p Kyocera_FS1040 -v file:///dev/usb/lp0 -m "Kyocera FS-1040 (KPSL)" -E
        lpoptions -p Kyocera_FS1040 -o printer-is-shared=true
        cupsenable Kyocera_FS1040
        cupsaccept Kyocera_FS1040
        print_success "Kyocera FS-1040 printer configured"
    else
        print_warning "Printer not detected at /dev/usb/lp0"
    fi
}

# Function to configure Netatalk for AFP (Apple File Protocol)
configure_netatalk() {
    print_status "Configuring Netatalk for Mac compatibility..."
    
    # Configure Netatalk
    cat > /etc/netatalk/afp.conf << 'EOF'
[Global]
hostname = BANANAPI
log file = /var/log/netatalk.log
log level = default:info

[Homes]
basedir regex = /home

[HDD750GB]
path = /media/HDD750GB
valid users = engineer

[Dzianis-2]
path = /media/Dzianis-2
valid users = engineer
EOF
    
    # Restart Netatalk
    systemctl restart netatalk
    systemctl enable netatalk
    
    print_success "Netatalk configured for AFP"
}

# Function to create mount points and set permissions
setup_storage() {
    print_status "Setting up storage mount points..."
    
    for mount_point in "${MEDIA_MOUNTS[@]}"; do
        if [ -d "$mount_point" ]; then
            print_status "Setting permissions for $mount_point"
            chown -R ${SMB_USER}:${SMB_USER} "$mount_point" 2>/dev/null || true
            chmod -R 775 "$mount_point" 2>/dev/null || true
        else
            print_warning "Mount point $mount_point does not exist"
        fi
    done
    
    print_success "Storage setup complete"
}

# Function to show status
show_status() {
    print_status "=== Service Status ==="
    
    echo -e "\nSamba Status:"
    systemctl is-active smbd nmbd || true
    
    echo -e "\nWSDD Status:"
    systemctl is-active wsdd || true
    
    echo -e "\nAvahi Status:"
    systemctl is-active avahi-daemon || true
    
    echo -e "\nNetatalk Status:"
    systemctl is-active netatalk || true
    
    echo -e "\nCUPS Status:"
    systemctl is-active cups || true
    
    echo -e "\nNetwork Shares:"
    smbclient -L localhost -N 2>&1 | grep -E "Disk|IPC" || true
    
    echo -e "\nPrinter Status:"
    lpstat -p 2>/dev/null || echo "No printers configured"
    
    echo -e "\nListening Ports:"
    ss -tlnp | grep -E "139|445|548|631|5357" | awk '{print $4}' || true
}

# Function to create test files
create_test_files() {
    print_status "Creating test files in shares..."
    
    for mount_point in "${MEDIA_MOUNTS[@]}"; do
        if [ -d "$mount_point" ]; then
            echo "NAS Test File - Created $(date)" > "$mount_point/NAS_TEST.txt" 2>/dev/null || true
            print_success "Test file created in $mount_point"
        fi
    done
}

# Main installation function
main() {
    print_status "=== Banana Pi NAS and Print Server Setup ==="
    echo ""
    
    # Check if running as root
    check_root
    
    # Run installation steps
    install_packages
    configure_samba
    configure_wsdd
    configure_avahi
    configure_netatalk
    configure_firewall
    optimize_system_performance
    configure_cups
    setup_kyocera_printer
    setup_storage
    create_test_files
    
    print_success "=== Setup Complete! ==="
    echo ""
    print_status "Access your NAS:"
    echo "  Windows:  \\\\BANANAPI or \\\\$(hostname -I | awk '{print $1}')"
    echo "  Mac:      smb://BANANAPI.local or afp://BANANAPI.local"
    echo "  Linux:    smb://BANANAPI.local"
    echo ""
    print_status "Available Shares:"
    echo "  - HDD750GB"
    echo "  - Dzianis-2"
    echo ""
    print_status "Printer Access:"
    echo "  Web Interface: http://$(hostname -I | awk '{print $1}'):631"
    echo "  Printer: Kyocera_FS1040"
    echo ""
    
    # Show final status
    show_status
}

# Parse command line arguments
case "${1:-}" in
    status)
        show_status
        ;;
    test)
        create_test_files
        ;;
    *)
        main
        ;;
esac