#!/usr/bin/perl -w
use strict;
use bmwqemu;
my $basedir="raid";
my $qemuimg="/usr/bin/kvm-img";
if(!-e $qemuimg) {$qemuimg="/usr/bin/qemu-img"}
my $qemubin="/usr/bin/kvm";
if(!-x $qemubin) {$qemubin=~s/kvm/qemu-kvm/}
if(!-x $qemubin) {$qemubin=~s/-kvm//}
if(!-x $qemubin) {die "no Qemu/KVM found"}

my $iso=$ENV{ISO};
$ENV{HDDMODEL}||="virtio";
$ENV{NICMODEL}||="virtio";
$ENV{QEMUVGA}||="cirrus";
$ENV{QEMUCPUS}||=1;
$ENV{NUMDISKS}||=1;
if(defined($ENV{RAIDLEVEL})) {$ENV{NUMDISKS}=4}
my @cdrom=("-cdrom", $iso);

$ENV{QEMU_AUDIO_DRV}="wav";
$ENV{QEMU_WAV_PATH}="/dev/null";

my $ison=$iso; $ison=~s{.*/}{}; # drop path
if($ison=~m/LiveCD/i) {$ENV{LIVECD}=1}
if($ison=~m/Promo/) {$ENV{PROMO}=1}
if($ison=~m/-i[3-6]86-/) {$ENV{QEMUCPU}||="qemu32"}
if($ison=~m/openSUSE-Smeegol/) {$ENV{DESKTOP}||="gnome"}
if($ison=~m/openSUSE-(DVD|NET|KDE|GNOME|LXDE|XFCE)/) {
	$ENV{$1}=1; $ENV{NETBOOT}=$ENV{NET};
	if($ENV{LIVECD}) {
		$ENV{DESKTOP}=lc($1);
	}
}

system(qw"/bin/mkdir -p", $basedir);

if($ENV{UPGRADE} && !$ENV{LIVECD}) {
	my $file=$ENV{UPGRADE};
	if(!-e $file) {die "'$ENV{UPGRADE}' should be old img.gz"}
	$ENV{KEEPHDDS}=1;
	# use qemu snapshot/cow feature to work on old image without writing it
	unlink "$basedir/l1";
	unlink "$basedir/1";
	#system($qemuimg, "create", "-b", $file, "-f", "qcow2", "$basedir/l1");
	system(qw"cp -a", $file, "$basedir/l1"); # reduce disk IO later
}

if(!qemualive) {
	if(!$ENV{KEEPHDDS}) {
		# fresh HDDs
		for my $i (1..4) {
			unlink("$basedir/l$i");
			if(-e "$basedir/$i.lvm") {
				symlink("$i.lvm","$basedir/l$i");
				system("/bin/dd", "if=/dev/zero", "count=1", "of=$basedir/l1"); # for LVM
			} else {
				system($qemuimg, "create" ,"$basedir/$i", "8G");
				symlink($i,"$basedir/l$i");
			}
		}
		if($ENV{USBBOOT}) {
			$ENV{NUMDISKS}=2;
			system("dd", "if=$iso", "of=$basedir/l1", "bs=1M", "conv=notrunc");
			@cdrom=();
		}
	}
	sleep 5;

	$qemupid=fork();
	die "fork failed" if(!defined($qemupid));
	if($qemupid==0) {
		my @params=(qw(-m 1024 -net user -monitor), "tcp:127.0.0.1:$ENV{QEMUPORT},server,nowait", "-net", "nic,model=$ENV{NICMODEL},macaddr=52:54:00:12:34:56", "-serial", "file:serial0", "-soundhw", "ac97", "-vga", $ENV{QEMUVGA}, "-S");
		for my $i (1..$ENV{NUMDISKS}) {
			my $boot="";#$i==1?",boot=on":""; # workaround bnc#696890
			push(@params, "-drive", "file=$basedir/l$i,if=$ENV{HDDMODEL}$boot");
		}
		push(@params, "-boot", "dc", @cdrom) if($iso);
		if($ENV{VNC}) {
			if($ENV{VNC}!~/:/) {$ENV{VNC}=":$ENV{VNC}"}
			push(@params, "-vnc", $ENV{VNC});
			push(@params, "-k", $ENV{VNCKB}) if($ENV{VNCKB});
		}
		if($ENV{QEMUCPU}) { push(@params, "-cpu", $ENV{QEMUCPU}); }
		push(@params, "-usb", "-usbdevice", "tablet");
		push(@params, "-smp", $ENV{QEMUCPUS});
		print "starting: $qemubin ".join(" ", @params)."\n";
		exec($qemubin, @params);
		die "exec $qemubin failed";
	}
	open(my $pidf, ">", $bmwqemu::qemupidfilename) or die "can not write $bmwqemu::qemupidfilename";
	print $pidf $qemupid,"\n";
	close $pidf;
	sleep 6; # time to let qemu start
}

1;
