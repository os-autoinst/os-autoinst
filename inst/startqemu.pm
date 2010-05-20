#!/usr/bin/perl -w
use strict;
use bmwqemu;
my $basedir="/home/bernhard/code/cvs/perl/autoinst/raid";
my $iso=$ENV{SUSEISO};
if($iso=~m/openSUSE-[A-Z]+-LiveCD/) {$ENV{LIVECD}=1}
if($iso=~m/openSUSE-(NET|KDE|GNOME)-/) {$ENV{$1}=1; $ENV{NETBOOT}=$ENV{NET}}
system(qw"/bin/mkdir -p", $basedir);
system("/bin/dd", "if=/dev/zero", "count=1", "of=$basedir/1"); # for LVM
for my $i (1..4) {
	system(qw(qemu-img create) ,"$basedir/$i", "5G");
}
system("sync");

$qemupid=fork();
die "fork failed" if(!defined($qemupid));
if($qemupid==0) {
	my @params=(qw(-m 1024 -net user -monitor), "tcp:127.0.0.1:15222,server,nowait", "-net", "nic,model=virtio,macaddr=52:54:00:12:34:56");
	for my $i (1..4) {
		my $boot=$i==1?",boot=on":"";
		push(@params, "-drive", "file=$basedir/$i,if=virtio$boot");
	}
	push(@params, "-boot", "dc", "-cdrom", $iso);
	push(@params, "-vnc", ":99");
#	push(@params, "-smp", "4");
	exec($qemubin, @params);
	die "exec $qemubin failed";
}
sleep 1; # time to let qemu start

1;
