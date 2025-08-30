#!/bin/bash

# BananaPi Printer Sharing Setup Script
# This script sets up printer sharing with automatic discovery for Android/iOS devices
# Run with: curl -sSL https://raw.githubusercontent.com/yourusername/bananapi-home-nas/main/setup-printer-sharing.sh | sudo bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   log_error "This script must be run as root"
   exit 1
fi

log_info "Starting printer sharing setup..."

# Update package list
log_info "Updating package list..."
apt-get update -qq

# Install required packages
log_info "Installing required packages..."
PACKAGES=(
    "cups"
    "cups-client"
    "cups-browsed"
    "cups-filters"
    "avahi-daemon"
    "avahi-utils"
    "usbutils"
    "printer-driver-foo2zjs"
    "printer-driver-foo2zjs-common"
    "printer-driver-pxljr"
    "printer-driver-gutenprint"
    "ipp-usb"
)

for package in "${PACKAGES[@]}"; do
    if ! dpkg -l | grep -q "^ii.*$package"; then
        log_info "Installing $package..."
        DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "$package" >/dev/null 2>&1
    else
        log_info "$package already installed"
    fi
done

# Stop IPP-USB to avoid conflicts
log_info "Disabling IPP-USB to avoid conflicts..."
systemctl stop ipp-usb 2>/dev/null || true
systemctl disable ipp-usb 2>/dev/null || true

# Configure CUPS for network sharing
log_info "Configuring CUPS for network sharing..."
cat > /etc/cups/cupsd.conf << 'EOF'
# CUPS configuration for network printing with Android/iOS support
LogLevel warn
MaxLogSize 0

# Listen on all interfaces
Port 631
Listen /run/cups/cups.sock

# Enable browsing and sharing
Browsing Yes
BrowseLocalProtocols dnssd
DefaultShared Yes
WebInterface Yes

# Allow access from network
ServerAlias *

# Root location - allow all
<Location />
  Order allow,deny
  Allow @LOCAL
  Allow 192.168.0.0/16
  Allow 10.0.0.0/8
  Allow 172.16.0.0/12
  Allow 100.64.0.0/10
</Location>

# Admin pages
<Location /admin>
  Order allow,deny
  Allow @LOCAL
</Location>

# Printer access
<Location /printers>
  Order allow,deny
  Allow @LOCAL
  Allow 192.168.0.0/16
  Allow 10.0.0.0/8
  Allow 172.16.0.0/12
  Allow 100.64.0.0/10
</Location>

<Policy default>
  JobPrivateAccess default
  JobPrivateValues default
  SubscriptionPrivateAccess default
  SubscriptionPrivateValues default
  
  <Limit All>
    Order deny,allow
    Allow @LOCAL
    Allow 192.168.0.0/16
    Allow 10.0.0.0/8
    Allow 172.16.0.0/12
    Allow 100.64.0.0/10
  </Limit>
</Policy>
EOF

# Get network interface name
INTERFACE=$(ip route | grep default | awk '{print $5}' | head -1)
if [ -z "$INTERFACE" ]; then
    INTERFACE=$(ip link | grep -E "^[0-9]+" | grep -v "lo" | awk -F': ' '{print $2}' | head -1)
fi

log_info "Detected network interface: $INTERFACE"

# Configure Avahi daemon
log_info "Configuring Avahi for printer discovery..."
cat > /etc/avahi/avahi-daemon.conf << EOF
[server]
host-name=$(hostname)
domain-name=local
browse-domains=0pointer.de, zeroconf.org
use-ipv4=yes
use-ipv6=yes
allow-interfaces=$INTERFACE
ratelimit-interval-usec=1000000
ratelimit-burst=1000

[wide-area]
enable-wide-area=yes

[publish]
disable-publishing=no
disable-user-service-publishing=no
add-service-cookie=yes
publish-addresses=yes
publish-hinfo=yes
publish-workstation=yes
publish-domain=yes
publish-dns-servers=
publish-resolv-conf-dns-servers=yes
publish-aaaa-on-ipv4=yes
publish-a-on-ipv6=no

[reflector]
enable-reflector=no
reflect-ipv=no

[rlimits]
rlimit-core=0
rlimit-data=4194304
rlimit-fsize=0
rlimit-nofile=768
rlimit-stack=4194304
rlimit-nproc=3
EOF

# Restart services
log_info "Restarting CUPS and Avahi services..."
systemctl restart cups
systemctl enable cups
systemctl restart avahi-daemon
systemctl enable avahi-daemon
systemctl restart cups-browsed
systemctl enable cups-browsed

# Detect USB printers
log_info "Detecting USB printers..."
USB_PRINTER=$(lsusb | grep -i "print" | head -1)
if [ -z "$USB_PRINTER" ]; then
    # Check for common printer manufacturers
    USB_PRINTER=$(lsusb | grep -iE "kyocera|canon|epson|brother|hp|samsung|xerox" | head -1)
fi

if [ -n "$USB_PRINTER" ]; then
    log_success "Found USB printer: $USB_PRINTER"
    
    # Extract vendor and product IDs
    VENDOR_ID=$(echo "$USB_PRINTER" | awk '{print $6}' | cut -d: -f1)
    PRODUCT_ID=$(echo "$USB_PRINTER" | awk '{print $6}' | cut -d: -f2)
    
    # Get manufacturer and model
    MANUFACTURER=$(lsusb -v 2>/dev/null | grep -A2 "idVendor.*$VENDOR_ID" | grep "iManufacturer" | awk '{$1=$2=""; print $0}' | xargs)
    MODEL=$(lsusb -v 2>/dev/null | grep -A3 "idVendor.*$VENDOR_ID" | grep "iProduct" | awk '{$1=$2=""; print $0}' | xargs)
    
    if [ -z "$MANUFACTURER" ]; then
        MANUFACTURER="Generic"
    fi
    if [ -z "$MODEL" ]; then
        MODEL="USB Printer"
    fi
    
    log_info "Printer details: $MANUFACTURER $MODEL"
    
    # Remove any existing printer with same name
    PRINTER_NAME=$(echo "${MANUFACTURER}-${MODEL}" | sed 's/[^a-zA-Z0-9-]/-/g')
    lpadmin -x "$PRINTER_NAME" 2>/dev/null || true
    
    # Determine the best driver
    log_info "Selecting appropriate driver..."
    
    # Try to find specific driver for the printer
    DRIVER=""
    if echo "$MANUFACTURER" | grep -qi "kyocera"; then
        if lpinfo -m | grep -qi "kyocera.*fs-1040"; then
            DRIVER=$(lpinfo -m | grep -i "kyocera.*fs-1040" | head -1 | awk '{print $1}')
        else
            DRIVER="drv:///sample.drv/generpcl.ppd"
        fi
    elif echo "$MANUFACTURER" | grep -qi "hp"; then
        DRIVER="drv:///sample.drv/generpcl.ppd"
    elif echo "$MANUFACTURER" | grep -qi "epson"; then
        DRIVER="drv:///sample.drv/epson24.ppd"
    elif echo "$MANUFACTURER" | grep -qi "canon"; then
        DRIVER="drv:///sample.drv/generpcl.ppd"
    else
        # Use generic PCL driver as fallback
        DRIVER="drv:///sample.drv/generpcl.ppd"
    fi
    
    log_info "Using driver: $DRIVER"
    
    # Detect USB device URI
    USB_URI=""
    if [ -e /dev/usb/lp0 ]; then
        USB_URI="usb://Unknown/Printer"
    fi
    
    # Try to get proper USB URI from lpinfo
    DETECTED_URI=$(lpinfo -v 2>/dev/null | grep -i "usb://" | head -1 | awk '{print $2}')
    if [ -n "$DETECTED_URI" ]; then
        USB_URI="$DETECTED_URI"
    fi
    
    if [ -z "$USB_URI" ]; then
        USB_URI="usb://${MANUFACTURER}/${MODEL}"
    fi
    
    log_info "Using USB URI: $USB_URI"
    
    # Add the printer
    log_info "Adding printer to CUPS..."
    lpadmin -p "$PRINTER_NAME" \
            -E \
            -v "$USB_URI" \
            -m "$DRIVER" \
            -D "$MANUFACTURER $MODEL" \
            -L "$(hostname)" \
            -o printer-is-shared=true \
            -o auth-info-required=none 2>/dev/null || {
        log_warn "Failed with selected driver, trying raw queue..."
        lpadmin -p "$PRINTER_NAME" \
                -E \
                -v "$USB_URI" \
                -m raw \
                -D "$MANUFACTURER $MODEL" \
                -L "$(hostname)" \
                -o printer-is-shared=true \
                -o auth-info-required=none
    }
    
    # Set as default printer
    lpadmin -d "$PRINTER_NAME"
    
    # Enable and accept jobs
    cupsaccept "$PRINTER_NAME"
    cupsenable "$PRINTER_NAME"
    
    log_success "Printer configured: $PRINTER_NAME"
    
    # Create Avahi service for printer discovery
    log_info "Creating Avahi service for automatic discovery..."
    cat > /etc/avahi/services/airprint-printer.service << EOF
<?xml version="1.0" standalone='no'?>
<!DOCTYPE service-group SYSTEM "avahi-service.dtd">
<service-group>
  <name replace-wildcards="yes">$MANUFACTURER $MODEL on %h</name>
  
  <!-- IPP service -->
  <service>
    <type>_ipp._tcp</type>
    <port>631</port>
    <txt-record>txtvers=1</txt-record>
    <txt-record>qtotal=1</txt-record>
    <txt-record>Transparent=T</txt-record>
    <txt-record>URF=none</txt-record>
    <txt-record>rp=printers/$PRINTER_NAME</txt-record>
    <txt-record>note=</txt-record>
    <txt-record>product=($MANUFACTURER $MODEL)</txt-record>
    <txt-record>printer-state=3</txt-record>
    <txt-record>printer-type=0x809016</txt-record>
    <txt-record>pdl=application/octet-stream,application/pdf,application/postscript,image/jpeg,image/png,application/vnd.hp-PCL</txt-record>
  </service>
  
  <!-- IPP Everywhere / AirPrint -->
  <service>
    <type>_ipp._tcp</type>
    <subtype>_universal._sub._ipp._tcp</subtype>
    <port>631</port>
    <txt-record>txtvers=1</txt-record>
    <txt-record>qtotal=1</txt-record>
    <txt-record>Transparent=T</txt-record>
    <txt-record>URF=none</txt-record>
    <txt-record>rp=printers/$PRINTER_NAME</txt-record>
    <txt-record>note=</txt-record>
    <txt-record>product=($MANUFACTURER $MODEL)</txt-record>
    <txt-record>printer-state=3</txt-record>
    <txt-record>printer-type=0x809016</txt-record>
    <txt-record>Scan=F</txt-record>
    <txt-record>Duplex=F</txt-record>
    <txt-record>Color=T</txt-record>
    <txt-record>pdl=application/octet-stream,application/pdf,application/postscript,image/jpeg,image/png,application/vnd.hp-PCL</txt-record>
    <txt-record>mopria-certified=1.3</txt-record>
  </service>
  
  <!-- Traditional LPD -->
  <service>
    <type>_printer._tcp</type>
    <port>631</port>
  </service>
</service-group>
EOF
    
else
    log_warn "No USB printer detected. Please connect a printer and run this script again."
    log_info "You can still access CUPS web interface to add network printers."
fi

# Configure firewall if iptables is available
if command -v iptables &> /dev/null; then
    log_info "Configuring firewall rules..."
    iptables -I INPUT -p tcp --dport 631 -j ACCEPT 2>/dev/null || true
    iptables -I INPUT -p udp --dport 5353 -j ACCEPT 2>/dev/null || true
fi

# Restart Avahi to load the service
systemctl restart avahi-daemon

# Get IP address
IP_ADDRESS=$(ip -4 addr show "$INTERFACE" | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1)

# Display summary
echo ""
log_success "==================================="
log_success "Printer Sharing Setup Complete!"
log_success "==================================="
echo ""
log_info "Access Points:"
log_info "  • CUPS Web Interface: http://$IP_ADDRESS:631"
log_info "  • Hostname: http://$(hostname).local:631"
echo ""

if [ -n "$USB_PRINTER" ]; then
    log_info "Configured Printer:"
    log_info "  • Name: $PRINTER_NAME"
    log_info "  • Model: $MANUFACTURER $MODEL"
    log_info "  • Status: Shared and Ready"
    echo ""
    log_info "Android/iOS Printing:"
    log_info "  1. Ensure your device is on the same network"
    log_info "  2. The printer should appear automatically as:"
    log_info "     '$MANUFACTURER $MODEL on $(hostname)'"
    log_info "  3. If not visible, add manually using:"
    log_info "     http://$IP_ADDRESS:631/printers/$PRINTER_NAME"
else
    log_warn "No printer detected. Connect a USB printer and run:"
    log_warn "  sudo $0"
fi

echo ""
log_info "Test printer discovery:"
log_info "  avahi-browse -rt _ipp._tcp"
echo ""

# Test print option
if [ -n "$PRINTER_NAME" ]; then
    read -p "Would you like to send a test page? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "Test Page from $(hostname) - $(date)" | lp -d "$PRINTER_NAME"
        log_success "Test page sent to printer!"
    fi
fi

log_success "Setup complete!"