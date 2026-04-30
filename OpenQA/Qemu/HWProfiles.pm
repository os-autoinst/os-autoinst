# Copyright SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package OpenQA::Qemu::HWProfiles;
use Mojo::Base -base, -signatures;

my $serial = [
    ['chardev', 'ringbuf,id=serial0,logfile=serial0,logappend=on'],
    ['serial', 'chardev:serial0'],
];

our %profiles = (
    default => {
        default => $serial,
        provides => [qw(serial)],
    },
    'virt-manager-defaults' => {
        x86_64 => [
            @$serial,
            ['device', 'pcie-root-port,id=root_port1,bus=pcie.0,chassis=1,slot=1,addr=0x1'],
            ['device', 'pcie-root-port,id=root_port2,bus=pcie.0,chassis=2,slot=2,addr=0x1.0x1'],
            ['device', 'pcie-root-port,id=root_port3,bus=pcie.0,chassis=3,slot=3,addr=0x1.0x2'],
            ['device', 'pcie-root-port,id=root_port4,bus=pcie.0,chassis=4,slot=4,addr=0x1.0x3'],
            ['device', 'pcie-root-port,id=root_port5,bus=pcie.0,chassis=5,slot=5,addr=0x1.0x4'],
            ['device', 'pcie-root-port,id=root_port6,bus=pcie.0,chassis=6,slot=6,addr=0x1.0x5'],
            ['device', 'pcie-root-port,id=root_port7,bus=pcie.0,chassis=7,slot=7,addr=0x1.0x6'],
            ['device', 'pcie-root-port,id=root_port8,bus=pcie.0,chassis=8,slot=8,addr=0x1.0x7'],
            ['device', 'qemu-xhci,id=usb,bus=root_port1,addr=0x0'],
            ['device', 'virtio-serial-pci,id=virtio-serial0,bus=root_port3,addr=0x0'],
            ['device', 'virtio-vga,id=video0,bus=root_port4,addr=0x0'],
            ['device', 'virtio-balloon-pci,id=balloon0,bus=root_port6,addr=0x0'],
            ['device', 'virtio-rng-pci,rng=rng0,id=rng0,bus=root_port7,addr=0x0'],
            ['object', 'rng-random,filename=/dev/urandom,id=rng0'],
        ],
        provides => [qw(serial pci usb graphics balloon rng input)],
    },
);

sub get_profile ($name, $arch) {
    my $p = $profiles{$name} or return undef;
    return {args => ($p->{$arch} // $p->{default} // []), provides => ($p->{provides} // [])};
}

1;
