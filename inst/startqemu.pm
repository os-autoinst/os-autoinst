#!/usr/bin/perl -w
use strict;
use bmwqemu;
my $basedir="/vm/raid";
my $iso="$ENV{HOME}/flash/no_backup/torrent/openSUSE-11.2-DVD-i586.iso";
system(qw"/bin/mkdir -p", $basedir);
for my $i (1..4) {
	system(qw(qemu-img create) ,"$basedir/$i", "4G");
}

$qemupid=fork();
die "fork failed" if(!defined($qemupid));
if($qemupid==0) {
	my @params=(qw(-m 2048 -net vde -smp 4 -monitor), "tcp:127.0.0.1:15222,server,nowait", "-net", "nic,model=e1000,macaddr=52:54:00:12:34:56");
	for my $i (1..4) {
		my $boot=$i==1?",boot=on":"";
		push(@params, "-drive", "file=$basedir/$i,if=virtio$boot");
	}
	push(@params, "-boot", "d", "-cdrom", $iso);
	exec("qemu-kvm", @params);
	die "exec qemu-kvm failed";
}
sleep 1;

1;
