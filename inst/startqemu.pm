#!/usr/bin/perl -w
use strict;
use File::Path qw/mkpath/;

my $basedir="raid";
my $qemuimg="/usr/bin/kvm-img";
if(!-e $qemuimg) {$qemuimg="/usr/bin/qemu-img"}

my $qemubin = $ENV{'QEMU'};
unless ($qemubin) {
	for my $bin (map { '/usr/bin/'.$_ } qw/kvm qemu-kvm qemu/) {
		next unless -x $bin;
		$qemubin = $bin;
		last;
	}
	die "no Qemu/KVM found\n" unless $qemubin;
}

my $iso=$ENV{ISO};
my $sizegb=10;
$ENV{HDDMODEL}||="virtio-blk";
$ENV{NICMODEL}||="virtio";
$ENV{QEMUVGA}||="cirrus";
$ENV{QEMUCPUS}||=1;
$ENV{NUMDISKS}||=2;
if(defined($ENV{RAIDLEVEL})) {$ENV{NUMDISKS}=4}

$ENV{QEMU_AUDIO_DRV}="wav";
$ENV{QEMU_WAV_PATH}="/dev/null";

if ($ENV{UEFI} && !-e $ENV{UEFI_BIOS_DIR}.'/bios.bin') {
	die "'$ENV{UEFI_BIOS_DIR}/bios.bin' missing, check UEFI_BIOS_DIR\n";
}

mkpath($basedir);

if($ENV{UPGRADE} && !$ENV{LIVECD}) {
	my $file=$ENV{UPGRADE};
	if(!-e $file) {die "'$ENV{UPGRADE}' should be old img.gz"}
	$ENV{KEEPHDDS}=1;
	# use qemu snapshot/cow feature to work on old image without writing it
	unlink "$basedir/l1";
	unlink "$basedir/1";
	#system($qemuimg, "create", "-b", $file, "-f", "qcow2", "$basedir/l1");
	system(qw"cp -a", $file, "$basedir/l1"); # reduce disk IO later
	for my $i (2..$ENV{NUMDISKS}) {
		system($qemuimg, "create" ,"$basedir/$i", "-f", "qcow2", $sizegb."G");
	}
}

if(!$ENV{KEEPHDDS} && !$ENV{SKIPTO}) {
	# fresh HDDs
	for my $i (1..4) {
		unlink("$basedir/l$i");
		if(-e "$basedir/$i.lvm") {
			symlink("$i.lvm","$basedir/l$i") or die "$!\n";
			die "$!\n" unless system("/bin/dd", "if=/dev/zero", "count=1", "of=$basedir/l1") == 0; # for LVM
		} else {
			die "$!\n" unless system($qemuimg, "create" ,"$basedir/$i", "-f", "qcow2", $sizegb."G") == 0;
			symlink($i,"$basedir/l$i") or die "$!\n";
		}
	}
}

for my $i (1..4) { # create missing symlinks
	next if -e "$basedir/l$i";
	next unless -e "$basedir/$i";
	symlink($i,"$basedir/l$i") or die "$!\n";
}

$self->{'pid'}=fork();
die "fork failed" if(!defined($self->{'pid'}));
if($self->{'pid'}==0) {
	my @params=('-m', '1024',
	       '-net', 'user', "-net", "nic,model=$ENV{NICMODEL},macaddr=52:54:00:12:34:56",
	       "-serial", "file:serial0",
	       "-soundhw", "ac97",
	       "-vga", $ENV{QEMUVGA}
       );

	if ($ENV{LAPTOP}) {
	    for my $f (<$ENV{LAPTOP}/*.bin>) {
		push @params, '-smbios', "file=$f";
	    }
	}

	for my $i (1..$ENV{NUMDISKS}) {
		my $boot="";#$i==1?",boot=on":""; # workaround bnc#696890
		push(@params, "-drive", "file=$basedir/l$i,cache=unsafe,if=none$boot,id=hd$i");
		push(@params, "-device", "$ENV{HDDMODEL},drive=hd$i");
	}

	if ($iso) {
	    if ($ENV{USBBOOT}) {
		push(@params, "-drive", "if=none,id=usbstick,file=$iso,snapshot=on");
		push(@params, "-device", "usb-ehci,id=ehci");
		push(@params, "-device", "usb-storage,bus=ehci.0,drive=usbstick,id=devusb");
	    } else {
		push(@params, "-cdrom", $iso);
	    }
	}

	push(@params, "-boot", "once=d,menu=on,splash-time=5000");

	if($ENV{QEMUCPU}) { push(@params, "-cpu", $ENV{QEMUCPU}); }
	if($ENV{UEFI}) { push(@params, "-L", $ENV{UEFI_BIOS_DIR}); }
	if($ENV{MULTINET}) {push(@params, qw"-net nic,vlan=1,model=virtio,macaddr=52:54:00:12:34:57 -net none,vlan=1")}
	push(@params, "-usb", "-usbdevice", "tablet");
	push(@params, "-smp", $ENV{QEMUCPUS});
	push(@params, "-enable-kvm");

	if (open(my $cmdfd, '>', 'runqemu')) {
		print $cmdfd "#!/bin/bash\n";
		my @args = map { s,\\,\\\\,g; s,\$,\\\$,g; s,\",\\\",g; s,\`,\\\`,g; "\"$_\"" } @params;
		printf $cmdfd "%s \\\n  %s\n", $qemubin, join(" \\\n  ", @args);
		close $cmdfd;
		chmod 0755, 'runqemu';
	}

	if($ENV{VNC}) {
		if($ENV{VNC}!~/:/) {$ENV{VNC}=":$ENV{VNC}"}
		push(@params, "-vnc", $ENV{VNC});
		push(@params, "-k", $ENV{VNCKB}) if($ENV{VNCKB});
	}

	push @params, '-qmp',  "unix:qmp_socket,server,nowait", "-monitor", "unix:hmp_socket,server,nowait", "-S";

	unshift(@params, $qemubin);
	unshift(@params, "/usr/bin/eatmydata") if (-e "/usr/bin/eatmydata");

	bmwqemu::diag("starting: ".join(" ", @params));

	exec(@params);
	die "exec $qemubin failed";
}
open(my $pidf, ">", $self->{'pidfilename'}) or die "can not write ".$self->{'pidfilename'};
print $pidf $self->{'pid'},"\n";
close $pidf;
sleep 6; # time to let qemu start

1;
