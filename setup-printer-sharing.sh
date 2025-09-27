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
    "printer-driver-all"
    "printer-driver-cups-pdf"
    "qemu-user-static"
    "qemu-user-binfmt"
    "libc6-i386"
    "lib32stdc++6"
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

# Configure USB printer driver for libusb backend
log_info "Configuring USB printer driver for libusb backend..."
# Blacklist usblp module to use libusb backend
cat > /etc/modprobe.d/blacklist-usblp.conf << 'EOF'
# Blacklist usblp to use CUPS libusb backend
blacklist usblp
EOF

# Remove usblp from modules-load
rm -f /etc/modules-load.d/usblp.conf

# Unload the module if loaded
modprobe -r usblp 2>/dev/null || true

# Create udev rule for printer permissions
cat > /etc/udev/rules.d/99-lp-permissions.rules << 'EOF'
KERNEL=="lp*", MODE="0666"
SUBSYSTEM=="usb", ATTR{idVendor}=="0482", ATTR{idProduct}=="0493", MODE="0666"
EOF

# Reload udev rules
udevadm control --reload-rules
udevadm trigger

# Install Kyocera PPD files if not present
log_info "Installing Kyocera PPD files..."
mkdir -p /usr/share/cups/model/Kyocera

# Create Kyocera FS-1040 PPD file
cat > /usr/share/cups/model/Kyocera/Kyocera_FS-1040GDI.ppd << 'EOF'
*PPD-Adobe: "4.3"
*%=============================================================================
*%
*%  PPD file for Kyocera FS-1040 (European English)
*%
*% (C) 2012 KYOCERA Document Solutions Inc.
*%
*%  Permission is granted for redistribution of this file as long as this
*%  copyright notice is intact and the contents of the file are not altered
*%  in any way from their original form.
*%
*%  Permission is hereby granted, free of charge, to any person obtaining
*%  a copy of this software and associated documentation files (the
*%  "Software"), to deal in the Software without restriction, including
*%  without limitation the rights to use, copy, modify, merge, publish,
*%  distribute, sublicense, and/or sell copies of the Software, and to
*%  permit persons to whom the Software is furnished to do so, subject to
*%  the following conditions:
*%
*%=============================================================================
*FormatVersion: "4.3"
*FileVersion: "1.0"
*LanguageVersion: English
*LanguageEncoding: ISOLatin1
*PCFileName: "KYFS1040.PPD"
*Manufacturer: "Kyocera"
*Product: "(FS-1040)"
*ModelName: "Kyocera FS-1040"
*ShortNickName: "Kyocera FS-1040"
*NickName: "Kyocera FS-1040, KPDL, 1.0"
*PSVersion: "(3010.000) 0"
*LanguageLevel: "3"
*ColorDevice: True
*DefaultColorSpace: RGB
*FileSystem: False
*cupsVersion: 1.0
*cupsFilter: "application/vnd.cups-raster 0 /usr/lib/cups/filter/rastertokpsl"
*cupsModelNumber: 1
*cupsManualCopies: True
*cupsFilter: "application/vnd.cups-postscript 0 /usr/lib/cups/filter/pstops"
*cupsFilter: "application/vnd.cups-pdf 0 /usr/lib/cups/filter/pdftops"
*OpenUI *PageSize/Media Size: PickOne
*OrderDependency: 10 AnySetup *PageSize
*DefaultPageSize: A4
*PageSize A4/A4: "<</PageSize[595 842]/ImagingBBox null>>setpagedevice"
*PageSize Letter/US Letter: "<</PageSize[612 792]/ImagingBBox null>>setpagedevice"
*CloseUI: *PageSize
*OpenUI *PageRegion: PickOne
*OrderDependency: 10 AnySetup *PageRegion
*DefaultPageRegion: A4
*PageRegion A4/A4: "<</PageSize[595 842]/ImagingBBox null>>setpagedevice"
*PageRegion Letter/US Letter: "<</PageSize[612 792]/ImagingBBox null>>setpagedevice"
*CloseUI: *PageRegion
*DefaultImageableArea: A4
*ImageableArea A4/A4: "18 18 577 824"
*ImageableArea Letter/US Letter: "18 18 594 774"
*DefaultPaperDimension: A4
*PaperDimension A4/A4: "595 842"
*PaperDimension Letter/US Letter: "612 792"
*OpenUI *Resolution/Resolution: PickOne
*OrderDependency: 10 AnySetup *Resolution
*DefaultResolution: 600dpi
*Resolution 300dpi/300 dpi: "<</HWResolution[300 300]>>setpagedevice"
*Resolution 600dpi/600 dpi: "<</HWResolution[600 600]>>setpagedevice"
*CloseUI: *Resolution
*OpenUI *ColorModel/Color Model: PickOne
*OrderDependency: 10 AnySetup *ColorModel
*DefaultColorModel: Gray
*ColorModel Gray/Grayscale: "<</ProcessColorModel /DeviceGray>>setpagedevice"
*ColorModel RGB/RGB Color: "<</ProcessColorModel /DeviceRGB>>setpagedevice"
*CloseUI: *ColorModel
*DefaultBitsPerPixel: 1
*BitsPerPixel 1/1 bit per pixel: "<</BitsPerPixel 1>>setpagedevice"
*BitsPerPixel 8/8 bits per pixel: "<</BitsPerPixel 8>>setpagedevice"
*BitsPerPixel 24/24 bits per pixel: "<</BitsPerPixel 24>>setpagedevice"
EOF

# Create Kyocera raster filter with QEMU wrapper
log_info "Creating Kyocera raster filter with QEMU wrapper..."
cat > /usr/lib/cups/filter/rastertokpsl << 'EOF'
#!/bin/bash
# Kyocera FS-1040 raster filter wrapper for ARM
# Uses either native ARM binary or QEMU for x86 binary

# Get job parameters
JOBID=$1
USER=$2
TITLE=$3
COPIES=$4
OPTIONS=$5
FILENAME=$6

# Log for debugging
echo "rastertokpsl: Job $JOBID for $USER" >> /tmp/rastertokpsl.log

# Check if we have a native ARM binary
if [ -f "/usr/lib/cups/filter/rastertokpsl-arm" ]; then
    echo "Using native ARM binary" >> /tmp/rastertokpsl.log
    exec /usr/lib/cups/filter/rastertokpsl-arm "$@"
elif [ -f "/usr/lib/cups/filter/rastertokpsl-bin" ]; then
    # Use QEMU for i386 binary
    echo "Using i386 binary with QEMU" >> /tmp/rastertokpsl.log
    export LD_LIBRARY_PATH="/usr/lib/i386-linux-gnu:/lib/i386-linux-gnu:$LD_LIBRARY_PATH"
    exec /usr/bin/qemu-i386-static -L /usr/lib/i386-linux-gnu /usr/lib/cups/filter/rastertokpsl-bin "$@"
else
    echo "ERROR: No rastertokpsl binary found!" >> /tmp/rastertokpsl.log
    echo "ERROR: No rastertokpsl binary found!" >&2
    exit 1
fi
EOF

chmod +x /usr/lib/cups/filter/rastertokpsl

# Handle Kyocera driver setup
if echo "$MANUFACTURER" | grep -qi "kyocera"; then
    log_info "Setting up Kyocera driver..."

    # Check for native ARM binary first
    if [ -f "/usr/lib/cups/filter/rastertokpsl-arm" ]; then
        log_success "Native ARM rastertokpsl binary found"
        chmod +x /usr/lib/cups/filter/rastertokpsl-arm
    elif [ -f "/usr/lib/cups/filter/rastertokpsl-bin" ]; then
        log_info "i386 rastertokpsl binary found, will use QEMU"
        chmod +x /usr/lib/cups/filter/rastertokpsl-bin
        
        # Install i386 libraries for QEMU
        log_info "Installing i386 libraries for QEMU..."
        dpkg --add-architecture i386 2>/dev/null || true
        apt-get update -qq
        apt-get install -y -qq libc6:i386 libcupsimage2:i386 2>/dev/null || true
    else
        log_warn "No Kyocera driver binary found"
        log_info "Attempting to compile native ARM driver..."
        
        # Try to compile rastertokpsl-re from source
        if command -v git &> /dev/null && command -v cmake &> /dev/null; then
            cd /tmp
            rm -rf rastertokpsl-re
            git clone https://github.com/Fe-Ti/rastertokpsl-re.git 2>/dev/null
            if [ -d "rastertokpsl-re" ]; then
                cd rastertokpsl-re
                # Fix compilation issues
                sed -i 's/sigset/signal/g' src/rastertokpsl.c 2>/dev/null || true
                sed -i 's/target_link_libraries(rastertokpsl)/target_link_libraries(rastertokpsl m)/g' CMakeLists.txt 2>/dev/null || true
                
                mkdir -p build && cd build
                if cmake .. && make; then
                    cp rastertokpsl /usr/lib/cups/filter/rastertokpsl-arm
                    chmod +x /usr/lib/cups/filter/rastertokpsl-arm
                    log_success "Successfully compiled native ARM rastertokpsl"
                else
                    log_warn "Failed to compile rastertokpsl-re"
                fi
                cd /
            fi
        fi
        
        if [ ! -f "/usr/lib/cups/filter/rastertokpsl-arm" ] && [ ! -f "/usr/lib/cups/filter/rastertokpsl-bin" ]; then
            log_warn "Could not set up Kyocera driver, will use generic driver"
        fi
    fi
fi

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
    PPD_FILE=""
    if echo "$MANUFACTURER" | grep -qi "kyocera"; then
        if echo "$MODEL" | grep -qi "fs-1040"; then
            # Use our custom Kyocera FS-1040 PPD
            PPD_FILE="/usr/share/cups/model/Kyocera/Kyocera_FS-1040GDI.ppd"
            log_info "Using Kyocera FS-1040 PPD: $PPD_FILE"
        elif lpinfo -m | grep -qi "kyocera"; then
            DRIVER=$(lpinfo -m | grep -i "kyocera" | head -1 | awk '{print $1}')
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

    if [ -n "$PPD_FILE" ]; then
        log_info "Using PPD file: $PPD_FILE"
    else
        log_info "Using driver: $DRIVER"
    fi
    
    # Detect USB device URI using libusb backend
    log_info "Detecting USB URI using libusb backend..."
    
    # Try to get proper USB URI from lpinfo (libusb backend)
    DETECTED_URI=$(lpinfo -v 2>/dev/null | grep -i "usb://" | grep -v "Unknown" | head -1 | awk '{print $2}')
    
    # If no standard USB URI, try Kyocera-specific URIs
    if [ -z "$DETECTED_URI" ] && echo "$MANUFACTURER" | grep -qi "kyocera"; then
        DETECTED_URI=$(lpinfo -v 2>/dev/null | grep -i "kyocera-usb://" | head -1 | awk '{print $2}')
    fi
    
    # Fallback to constructed URI
    if [ -n "$DETECTED_URI" ]; then
        USB_URI="$DETECTED_URI"
    else
        # Construct USB URI with serial if available
        SERIAL=$(lsusb -v -d "${VENDOR_ID}:${PRODUCT_ID}" 2>/dev/null | grep "iSerial" | awk '{print $3}')
        if [ -n "$SERIAL" ]; then
            USB_URI="usb://${MANUFACTURER}/${MODEL}?serial=${SERIAL}"
        else
            USB_URI="usb://${MANUFACTURER}/${MODEL}"
        fi
    fi
    
    log_info "Using USB URI: $USB_URI"
    
    # Add the printer
    log_info "Adding printer to CUPS..."
    if [ -n "$PPD_FILE" ] && [ -f "$PPD_FILE" ]; then
        # Use PPD file for Kyocera FS-1040
        lpadmin -p "$PRINTER_NAME" \
                -E \
                -v "$USB_URI" \
                -P "$PPD_FILE" \
                -D "$MANUFACTURER $MODEL" \
                -L "$(hostname)" \
                -o printer-is-shared=true \
                -o auth-info-required=none
        log_success "Added Kyocera FS-1040 with custom PPD"
    else
        # Use standard driver
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
    fi
    
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