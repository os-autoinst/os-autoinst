use strict;
use base "basetest";
use bmwqemu;

our %valueranges=(
#	LVM=>[0,1], 
	NOIMAGES=>[0,1],
#	SYSTEMD=>[0,1],
#	BTRFS=>[0,1],
#	DESKTOP=>[qw(kde gnome xfce lxde)],
#	ROOTFS=>[qw(ext3 xfs jfs btrfs reiserfs)],
);

sub logcurrentenv(@)
{
	foreach my $k (@_) {
		my $e=$ENV{$k};
		next unless defined $e;
		diag("randomenv $k=$e");
		diag("usingenv $k=$e");
	}
}

sub setrandomenv()
{
	foreach my $k (keys %valueranges) {
		next if defined $ENV{$k};
		next if $k eq "DESKTOP" && $ENV{LIVECD};
		my @range=@{$valueranges{$k}};
		my $rand=int(rand(scalar @range));
		$ENV{$k}=$range[$rand];
		logcurrentenv($k);
	}
}

sub run()
{
	my $iso=$ENV{ISO};
	my $ison=$iso; $ison=~s{.*/}{}; # drop path
	if($ison=~m/LiveCD/i) {$ENV{LIVECD}=1}
	if($ison=~m/Promo/) {$ENV{PROMO}=1}
	if($ison=~m/-i[3-6]86-/) {$ENV{QEMUCPU}||="qemu32"}
	if($ison=~m/openSUSE-(DVD|NET|KDE|GNOME|LXDE|XFCE)-/) {
		$ENV{$1}=1; $ENV{NETBOOT}=$ENV{NET};
		if($ENV{LIVECD}) {
			$ENV{DESKTOP}=lc($1);
		}
	}
	# dump other important ENV:
	logcurrentenv(qw"BIGTEST MOZILLATEST UPGRADE USBBOOT LIVETEST ADDONURL DESKTOP BTRFS LVM");
	setrandomenv if($ENV{RANDOMENV} && $0!~m/checklog/);
	$ENV{DESKTOP}||="kde";
	autotest::runtestdir("$scriptdir/consoletest.d", undef);
	autotest::runtestdir("$scriptdir/x11test.d", undef);
}

1;
