#!/usr/bin/perl -w
use strict;
use bmwqemu;
my $basedir="/home/bernhard/code/cvs/perl/autoinst/raid";
my $iso=$ENV{SUSEISO};
system(qw"/bin/mkdir -p", $basedir);
for my $i (1..4) {
	system(qw(qemu-img create) ,"$basedir/$i", "4G");
}

$qemupid=fork();
die "fork failed" if(!defined($qemupid));
if($qemupid==0) {
	my @params=(qw(-m 1024 -net user -smp 4 -monitor), "tcp:127.0.0.1:15222,server,nowait", "-net", "nic,model=e1000,macaddr=52:54:00:12:34:56");
	for my $i (1..4) {
		my $boot=$i==1?",boot=on":"";
		push(@params, "-drive", "file=$basedir/$i,if=virtio$boot");
	}
	push(@params, "-boot", "d", "-cdrom", $iso);
	push(@params, "-vnc", ":99");
	exec($qemubin, @params);
	die "exec $qemubin failed";
}
sleep 1; # time to let qemu start

1;
