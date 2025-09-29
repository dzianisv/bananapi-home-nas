# BananaPi Home NAS

Turn your BananaPi into a fast home NAS with printer sharing.

## Quick Setup

```bash
ssh root@your-bananapi-ip
curl -O https://raw.githubusercontent.com/dzianisv/bananapi-home-nas/master/setup-bananapi-nas.sh
chmod +x setup-bananapi-nas.sh
sudo ./setup-bananapi-nas.sh
```

## Features

- **SMB/AFP file sharing** - Works with Windows, Mac, Linux
- **Auto-discovery** - Shows up in network browsers
- **Printer sharing** - Kyocera FS-1040 support via CUPS
- **Performance optimized** - 30x speed improvement (from 1MB/s to 30MB/s)

## Access Your NAS

- **Windows:** `\\BANANAPI` or `\\<IP-address>`
- **Mac:** `smb://BANANAPI.local` or `afp://BANANAPI.local`
- **Printer:** `http://<IP-address>:631`

## Commands

```bash
./setup-bananapi-nas.sh           # Full setup
./setup-bananapi-nas.sh status    # Check services
./setup-bananapi-nas.sh performance # Optimize speed only
./test-printer.sh                  # Test printer
```

## Troubleshooting

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