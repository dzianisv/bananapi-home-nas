# Kyocera FS-1040 Printer Setup for Banana Pi

This repository contains a comprehensive setup script for configuring the Kyocera FS-1040 printer on a Banana Pi running Debian ARMv7.

## 🚀 Quick Start

### Prerequisites
- Banana Pi with Debian installed
- Kyocera FS-1040 printer connected via USB
- Root access (sudo)

### Basic Installation
```bash
# Clone or copy the setup script
sudo ./setup-printer.sh
```

### Advanced Options
```bash
# Show help
sudo ./setup-printer.sh --help

# Show current printer status
sudo ./setup-printer.sh --status

# Clean print queue (cancel all jobs)
sudo ./setup-printer.sh --clean

# Only test existing printer (skip installation)
sudo ./setup-printer.sh --test

# Remove and reinstall printer configuration
sudo ./setup-printer.sh --reinstall
```

## 📋 What the Script Does

### 1. Package Installation
- **CUPS**: Core printing system
- **Printer Drivers**: All manufacturer drivers including Kyocera
- **USB Support**: USB printer utilities and libraries
- **Network Sharing**: Samba and Netatalk for file/printer sharing

### 2. USB Configuration
- Loads `usblp` kernel module automatically
- Creates udev rules for proper device permissions
- Disables USB autosuspend to prevent connection issues

### 3. CUPS Setup
- Configures Kyocera FS-1040 with correct PPD file
- Enables printer sharing
- Sets up network printing via IPP

### 4. Printer Sharing
- **SMB/CIFS**: Windows network printing
- **IPP**: Standard network printing protocol
- **Bonjour**: Automatic printer discovery

### 5. System Integration
- Persistent configuration across reboots
- Automatic USB device handling
- Power management optimization

## 🔧 Manual Configuration (If Script Fails)

If the automatic script fails, you can manually configure the printer:

### 1. Install Packages
```bash
sudo apt update
sudo apt install cups cups-filters printer-driver-all ipp-usb python3-usb
```

### 2. Configure USB Driver
```bash
# Load USB printer module
sudo modprobe usblp

# Make it persistent
echo "usblp" | sudo tee /etc/modules-load.d/usblp.conf

# Create udev rule
sudo tee /etc/udev/rules.d/99-lp-permissions.rules > /dev/null <<EOF
KERNEL=="lp*", MODE="0666"
EOF

sudo udevadm control --reload-rules
```

### 3. Add Printer to CUPS
```bash
# Start CUPS
sudo systemctl enable cups
sudo systemctl start cups

# Add printer
sudo lpadmin -p Kyocera-FS1040 \
  -v "usb://Kyocera/FS-1040?serial=V235751419" \
  -P /usr/share/cups/model/Kyocera/Kyocera_FS-1040GDI.ppd \
  -E

# Enable printer
sudo cupsenable Kyocera-FS1040
sudo cupsaccept Kyocera-FS1040
```

## 🧪 Testing the Printer

### Check Status
```bash
# Check printer status
lpstat -p Kyocera-FS1040

# Check print queue
lpstat -o

# Check USB connection
lsusb | grep Kyocera

# Quick status check with our script
sudo ./setup-printer.sh --status
```

### Print Test Page
```bash
# Print test file
echo "Test print from Banana Pi" | lp -d Kyocera-FS1040

# Print existing test file
lp -d Kyocera-FS1040 /usr/share/cups/data/testprint

# Clean print queue if jobs get stuck
sudo ./setup-printer.sh --clean
```

### Web Interface
Access the CUPS web interface at: `http://localhost:631`

## 🌐 Network Access

### Windows (SMB)
```
\\bananapi\Kyocera-FS1040
```

### macOS/Linux (IPP)
```
ipp://bananapi/printers/Kyocera-FS1040
```

### Web Browser
```
http://bananapi:631/printers/Kyocera-FS1040
```

## 🔍 Troubleshooting

### Printer Not Found
```bash
# Check USB devices
lsusb | grep Kyocera

# Check device nodes
ls -la /dev/lp* /dev/usb/lp*

# Reload USB modules
sudo modprobe -r usblp
sudo modprobe usblp
```

### Print Jobs Stuck
```bash
# Clear print queue
cancel -a Kyocera-FS1040

# Restart CUPS
sudo systemctl restart cups

# Check CUPS logs
tail -f /var/log/cups/error_log
```

### Permission Issues
```bash
# Fix device permissions
sudo chmod 666 /dev/lp0 /dev/usblp0

# Check CUPS user permissions
sudo usermod -a -G lp $USER
```

### Service Mode Issues
If printer shows "Service Mode":
1. Power off the printer
2. Press and hold specific buttons (check manual)
3. Power on while holding buttons
4. Release when normal operation resumes

## 📁 Files Created

- `setup-printer.sh` - Main setup script
- `/etc/modules-load.d/usblp.conf` - Auto-load USB printer module
- `/etc/udev/rules.d/99-lp-permissions.rules` - Device permissions
- `/usr/local/bin/disable-printer-autosuspend.sh` - Power management script
- `/etc/systemd/system/disable-printer-autosuspend.service` - Systemd service

## 🏗️ Architecture Notes

This setup is specifically designed for:
- **Platform**: Banana Pi (ARMv7)
- **OS**: Debian GNU/Linux
- **Printer**: Kyocera FS-1040
- **Connection**: USB

## 📞 Support

If you encounter issues:
1. Run the script with `--test` to diagnose problems
2. Check the troubleshooting section above
3. Verify printer is not in service mode
4. Ensure USB cable is properly connected

## 📝 Changelog

- **v1.0**: Initial release with complete Kyocera FS-1040 setup
- Includes USB driver configuration, CUPS setup, and network sharing
- Automatic device permission management
- Power management optimization for USB printers