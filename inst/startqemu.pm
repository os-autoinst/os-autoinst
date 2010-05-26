#!/usr/bin/perl -w
use strict;
use bmwqemu;
my $basedir="raid";
my $iso=$ENV{SUSEISO};
if($iso=~m/openSUSE-[A-Z]+-LiveCD/) {$ENV{LIVECD}=1}
if($iso=~m/openSUSE-(NET|KDE|GNOME)-/) {$ENV{$1}=1; $ENV{NETBOOT}=$ENV{NET}}
system(qw"/bin/mkdir -p", $basedir);
system("/bin/dd", "if=/dev/zero", "count=1", "of=$basedir/1"); # for LVM
for my $i (1..4) {
	my $qemuimg="/usr/bin/kvm-img";
	if(!-e $qemuimg) {$qemuimg="/usr/bin/qemu-img"}
	system($qemuimg, "create" ,"$basedir/$i", "5G");
}
system("sync"); sleep 5;

$qemupid=fork();
die "fork failed" if(!defined($qemupid));
if($qemupid==0) {
	my @params=(qw(-m 1024 -net user -monitor), "tcp:127.0.0.1:$ENV{QEMUPORT},server,nowait", "-net", "nic,model=virtio,macaddr=52:54:00:12:34:56");
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
open(my $pidf, ">", $bmwqemu::qemupidfilename) or die "can not write $bmwqemu::qemupidfilename";
print $pidf $qemupid,"\n";
close $pidf;
sleep 1; # time to let qemu start

1;
