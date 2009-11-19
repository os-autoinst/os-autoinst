#!/bin/sh
(cd /mnt/enc/stuff/vm ;
mkdir -p raid
for i in $(seq 1 4) ; do
	qemu-img create raid/$i 4G
done
qemu-kvm -m 2048 -net nic,model=e1000,macaddr=52:54:00:12:34:56 -net vde -smp 4 -drive file=raid/1,if=virtio,boot=on -drive file=raid/2,if=virtio -drive file=raid/3,if=virtio -drive file=raid/4,if=virtio -cdrom ~/flash/no_backup/torrent/openSUSE-11.2-DVD-i586.iso -boot d -monitor tcp:127.0.0.1:15222,server,nowait )&
sleep 1
perl autoinst.pl | netcat localhost 15222

