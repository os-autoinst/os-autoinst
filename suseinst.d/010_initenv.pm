use strict;
use base "basetest";
use bmwqemu;

our %valueranges=(
	LVM=>[0,1], 
	USEIMAGES=>[0,1],
	DESKTOP=>[qw(kde gnome xfce lxde)],
	ROOTFS=>[qw(ext3 xfs jfs btrfs reiserfs)],
);

sub setrandomenv()
{
	foreach my $k (keys %valueranges) {
		next if defined $ENV{$k};
		next if $k eq "DESKTOP" && $ENV{LIVECD};
		my @range=@{$valueranges{$k}};
		my $rand=int(rand(scalar @range));
		$ENV{$k}=$range[$rand];
		diag "randomenv $k=$ENV{$k}";
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
	setrandomenv if($ENV{RANDOMENV});
	$ENV{DESKTOP}||="kde";
}

