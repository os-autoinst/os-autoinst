#!/bin/bash

# assumes a disk image exists here...
#FILE=/home/usbarmory/usbdisk.img
modprobe usb_f_mass_storage
modprobe usb_f_hid
modprobe usb_f_acm # serial
#modprobe usb_f_uac2 # audio

#mount -a -t nfs
FILE=/mounts/dist/install/openSUSE-13.2-GM/iso/openSUSE-13.2-NET-i586.iso
FILE=/root/openSUSE-13.2-NET-i586.iso
#mkdir -p ${FILE/img/d}
#mount -o loop,ro,offset=1048576 -t ext4 $FILE ${FILE/img/d}

cd /sys/kernel/config/usb_gadget/

mkdir -p usbarmory
cd usbarmory
#echo '' > UDC

echo 0x1d6b > idVendor # Linux Foundation
echo 0x0104 > idProduct # Multifunction Composite Gadget
echo 0x0090 > bcdDevice # v0.9.0

mkdir -p strings/0x409
echo "fedcba9876543210" > strings/0x409/serialnumber
echo "Inverse Path" > strings/0x409/manufacturer
echo "USB Armory" > strings/0x409/product

N="usb0"
mkdir -p functions/mass_storage.$N
echo 1 > functions/mass_storage.$N/stall
echo 1 > functions/mass_storage.$N/lun.0/cdrom
echo 1 > functions/mass_storage.$N/lun.0/ro
echo 0 > functions/mass_storage.$N/lun.0/nofua

echo $FILE > functions/mass_storage.$N/lun.0/file

# keyboard
mkdir -p functions/hid.$N
echo 1 > functions/hid.$N/protocol
echo 1 > functions/hid.$N/subclass
echo 8 > functions/hid.$N/report_length
echo -ne '\x05\x01\x09\x06\xa1\x01\x05\x07\x19\xe0\x29\xe7\x15\x00\x25\x01\x75\x01\x95\x08\x81\x02\x95\x01\x75\x08\x81\x03\x95\x05\x75\x01\x05\x08\x19\x01\x29\x05\x91\x02\x95\x01\x75\x03\x91\x03\x95\x06\x75\x08\x15\x00\x25\x65\x05\x07\x19\x00\x29\x65\x81\x00\xc0' > functions/hid.$N/report_desc

C=1
mkdir -p configs/c.$C/strings/0x409
echo "Config $C: mass-storage" > configs/c.$C/strings/0x409/configuration
echo 250 > configs/c.$C/MaxPower
ln -s functions/mass_storage.$N configs/c.$C/
ln -s functions/hid.$N configs/c.$C/
# serial
mkdir -p functions/acm.$N
ln -s functions/acm.$N configs/c.$C/
# audio
#mkdir -p functions/uac2.$N
#ln -s functions/uac2.$N configs/c.$C/

#echo "interactive check" ; bash -i
ls /sys/class/udc > UDC  # enable

sleep 3
# send "A" through keyboard
#echo left-shift a | /root/hid-gadget-test/jni/hid-gadget-test /dev/hidg0 keyboard
#/root/rpc_hid.pl daemon --listen "http://:::3000"
