#!/bin/bash
set -e

echo "Updating packages..."
apt update
apt install -y netatalk samba

echo "Configuring AFP..."
cat > /etc/netatalk/afp.conf <<EOL
[Global]
  mimic model = TimeCapsule6,106
  log level = default:warn

[All_Disks]
  path = /media
  guest = yes
  file perm = 0664
  directory perm = 0775
  time machine = no
EOL

echo "Configuring SMB..."
cat > /etc/samba/smb.conf <<EOL
[global]
   workgroup = WORKGROUP
   server string = BananaPi NAS
   security = user
   map to guest = bad user
   dns proxy = no

[media]
   path = /media
   browseable = yes
   writable = yes
   guest ok = yes
   public = yes
   create mask = 0644
   directory mask = 0755
EOL

echo "Enabling and starting services..."
systemctl enable netatalk smbd nmbd
systemctl start netatalk smbd nmbd

echo "Setup complete. Shares available at /media"
echo "Setting up automount for disks..."
mkdir -p /media

system_disk=$(lsblk -no PKNAME $(df / | tail -1 | awk '{print $1}') | head -1)

for dev in $(lsblk -ndo NAME | grep -E "^sd|^nvme|^mmc" | grep -v "^${system_disk}$"); do
  if ! mount | grep -q "/dev/$dev"; then
    uuid=$(blkid /dev/$dev | grep -o "UUID=\"[^\"]*\"" | cut -d'"' -f2)
    if [ -n "$uuid" ]; then
      mountpoint="/media/$dev"
      mkdir -p "$mountpoint"
      if ! grep -q "UUID=$uuid" /etc/fstab; then
        echo "UUID=$uuid $mountpoint auto defaults 0 2" >> /etc/fstab
      fi
      mount "$mountpoint"
      echo "Mounted /dev/$dev to $mountpoint"
    fi
  fi
done
