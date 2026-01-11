#!/bin/bash

# Switch Banana Pi filesystem to readonly mode
# This script sets up overlayfs to make the root filesystem readonly
# while providing writable overlays for necessary directories

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

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

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root (sudo)"
        exit 1
    fi
}

# Function to backup current fstab
backup_fstab() {
    print_status "Backing up current fstab..."
    cp /etc/fstab "/etc/fstab.backup.$(date +%Y%m%d_%H%M%S)"
    print_success "Backup created"
}

# Function to modify fstab for readonly root
modify_fstab() {
    print_status "Modifying fstab for readonly root filesystem..."

    # Add tmpfs mounts for essential writable directories
    cat >> /etc/fstab << 'EOF'

# tmpfs for essential writable directories on readonly root
tmpfs /var/log tmpfs defaults,size=50M 0 0
tmpfs /var/run tmpfs defaults,size=10M 0 0
tmpfs /var/lock tmpfs defaults,size=10M 0 0
tmpfs /var/tmp tmpfs defaults,size=20M 0 0
tmpfs /tmp tmpfs defaults,size=50M 0 0
EOF

    print_success "fstab modified for readonly operation"
}

# Function to create init script for tmpfs setup
create_init_script() {
    print_status "Creating init script for tmpfs setup..."

    cat > /etc/init.d/setup-readonly << 'EOF'
#!/bin/bash
### BEGIN INIT INFO
# Provides:          setup-readonly
# Required-Start:    $local_fs
# Required-Stop:     $local_fs
# Default-Start:     S
# Default-Stop:      0 6
# Short-Description: Set up tmpfs mounts for readonly root
### END INIT INFO

case "$1" in
    start)
        echo "Setting up tmpfs mounts for readonly root..."

        # Create directories if they don't exist
        mkdir -p /var/log /var/run /var/lock /var/tmp /tmp

        # Mount tmpfs for essential writable directories
        mount -t tmpfs tmpfs /var/log -o size=50M
        mount -t tmpfs tmpfs /var/run -o size=10M
        mount -t tmpfs tmpfs /var/lock -o size=10M
        mount -t tmpfs tmpfs /var/tmp -o size=20M
        mount -t tmpfs tmpfs /tmp -o size=50M

        # Copy essential files to tmpfs mounts
        cp -a /var/log/* /var/log/ 2>/dev/null || true
        cp -a /var/run/* /var/run/ 2>/dev/null || true
        cp -a /var/lock/* /var/lock/ 2>/dev/null || true
        cp -a /var/tmp/* /var/tmp/ 2>/dev/null || true
        cp -a /tmp/* /tmp/ 2>/dev/null || true

        echo "tmpfs mounts setup complete"
        ;;
    stop)
        echo "Stopping tmpfs mounts..."
        # tmpfs mounts will be unmounted automatically on shutdown
        ;;
    *)
        echo "Usage: $0 {start|stop}"
        exit 1
        ;;
esac
EOF

    chmod +x /etc/init.d/setup-readonly
    update-rc.d setup-readonly defaults

    print_success "Init script created and enabled"
}

# Function to modify boot parameters
modify_boot_params() {
    print_status "Modifying boot parameters for readonly root..."

    # For Armbian/Debian on Banana Pi, check if u-boot or grub is used
    if [ -f /boot/boot.cmd ]; then
        # u-boot with boot.cmd
        print_status "Found u-boot boot.cmd, modifying..."

        # Backup boot.cmd
        cp /boot/boot.cmd "/boot/boot.cmd.backup.$(date +%Y%m%d_%H%M%S)"

        # Add 'ro' to root mount options in bootargs
        if ! grep -q " ro " /boot/boot.cmd; then
            sed -i 's|rootfstype=ext4|rootfstype=ext4 ro|' /boot/boot.cmd
        fi

        # Recompile boot.scr
        mkimage -C none -A arm -T script -d /boot/boot.cmd /boot/boot.scr

        print_success "u-boot boot parameters modified"

    elif [ -f /boot/cmdline.txt ]; then
        # Raspberry Pi style cmdline.txt
        print_status "Found cmdline.txt, modifying..."

        cp /boot/cmdline.txt "/boot/cmdline.txt.backup.$(date +%Y%m%d_%H%M%S)"

        # Add 'ro' if not present
        if ! grep -q " ro " /boot/cmdline.txt; then
            sed -i 's| root=| ro root=|' /boot/cmdline.txt
        fi

        print_success "cmdline.txt modified for readonly root"

    else
        print_warning "Could not find boot.cmd or cmdline.txt. Manual boot parameter modification may be required."
        print_warning "Please add 'ro' to the root mount options in your boot loader configuration."
    fi
}

# Function to create revert script
create_revert_script() {
    print_status "Creating revert script..."

    cat > /usr/local/bin/revert-to-readwrite.sh << 'EOF'
#!/bin/bash

# Revert from readonly filesystem back to read-write

set -e

echo "Reverting to read-write filesystem..."

# Remove readonly init script
update-rc.d setup-readonly remove 2>/dev/null || true
rm -f /etc/init.d/setup-readonly

# Restore fstab
if [ -f /etc/fstab.backup.* ]; then
    LATEST_BACKUP=$(ls -t /etc/fstab.backup.* | head -1)
    cp "$LATEST_BACKUP" /etc/fstab
    echo "fstab restored from $LATEST_BACKUP"
fi

# Restore boot parameters
if [ -f /boot/boot.cmd.backup.* ]; then
    LATEST_BACKUP=$(ls -t /boot/boot.cmd.backup.* | head -1)
    cp "$LATEST_BACKUP" /boot/boot.cmd
    mkimage -C none -A arm -T script -d /boot/boot.cmd /boot/boot.scr 2>/dev/null || true
    echo "boot.cmd restored from $LATEST_BACKUP"
elif [ -f /boot/cmdline.txt.backup.* ]; then
    LATEST_BACKUP=$(ls -t /boot/cmdline.txt.backup.* | head -1)
    cp "$LATEST_BACKUP" /boot/cmdline.txt
    echo "cmdline.txt restored from $LATEST_BACKUP"
fi

echo "Filesystem reverted to read-write mode. Please reboot."
EOF

    chmod +x /usr/local/bin/revert-to-readwrite.sh

    print_success "Revert script created at /usr/local/bin/revert-to-readwrite.sh"
}

# Main function
main() {
    print_status "=== Switching Banana Pi to Readonly Filesystem ==="
    echo ""

    check_root

    # Warn user about the changes
    print_warning "This will make the root filesystem readonly."
    print_warning "Writable data will be stored in RAM (tmpfs)."
    print_warning "Changes to /var, /tmp, /home, /root will not persist across reboots."
    print_warning "Use 'revert-to-readwrite.sh' to undo these changes."
    echo ""
    read -p "Continue? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_status "Operation cancelled."
        exit 0
    fi

    # Perform the switch
    backup_fstab
    modify_boot_params
    modify_fstab
    create_init_script
    create_revert_script

    print_success "=== Configuration Complete ==="
    echo ""
    print_status "The system is now configured for readonly operation."
    print_status "Please reboot to activate the readonly filesystem."
    echo ""
    print_status "To revert back to read-write mode, run:"
    echo "  sudo /usr/local/bin/revert-to-readwrite.sh"
    echo "  sudo reboot"
}

# Run main function
main "$@"