How to flash
```shell
gzcat boot-banana_pi_m1.bin.gz debian-bookworm-armhf-uu3foo.bin.gz | sudo dd status=progress bs=1M of=/dev/disk5
```

Flash a backup image:
```shell
gzcat bananapi-rootfs-backup-20250830.img.gz | sudo dd of=/dev/disk5s2 status=progress bs=1M
```
