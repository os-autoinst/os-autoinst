#!/bin/sh
mkdir -p /vm/raid1 
for i in $(seq 1 2) ; do
	qemu-img create /vm/raid1/$i 4G
done
(cd /home/bernhard/temp/ ; zsync http://www3.zq1.de/bernhard/mirror/opensuse/factory/iso/openSUSE-NET-i586-current-Media.iso.zsync)

( cd /vm && qemu-kvm -m 2048 -net nic,model=e1000,macaddr=52:54:00:12:34:56 -net vde -smp 4 -drive file=raid1/1,if=virtio,boot=on -drive file=raid1/2,if=virtio -cdrom /home/bernhard/temp/openSUSE-NET-i586-current-Media.iso -boot d -monitor tcp:127.0.0.1:15222,server,nowait )&
sleep 8
perl autoinst-net.pl | netcat localhost 15222

