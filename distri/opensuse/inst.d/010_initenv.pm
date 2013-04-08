use strict;
use base "basetest";
use bmwqemu;

our %valueranges=(
#	LVM=>[0,1], 
	NOIMAGES=>[0,1],
	REBOOTAFTERINSTALL=>[0,1],
	DOCRUN=>[0,1],
#	BTRFS=>[0,1],
	DESKTOP=>[qw(kde gnome xfce lxde minimalx textmode)],
#	ROOTFS=>[qw(ext3 xfs jfs btrfs reiserfs)],
	VIDEOMODE=>["","text"],
);

our @can_randomize = qw/NOIMAGES REBOOTAFTERINSTALL DESKTOP VIDEOMODE/;

sub logcurrentenv(@)
{
	foreach my $k (@_) {
		my $e=$ENV{$k};
		next unless defined $e;
		diag("usingenv $k=$e");
	}
}

sub setrandomenv()
{
	for my $k (@can_randomize) {
		next if defined $ENV{$k};
		next if $k eq "DESKTOP" && $ENV{LIVECD};
		if ($ENV{DOCRUN}) {
			next if $k eq "VIDEOMODE";
			next if $k eq "NOIMAGES";
		}
		my @range=@{$valueranges{$k}};
		my $rand=int(rand(scalar @range));
		$ENV{$k}=$range[$rand];
		logcurrentenv($k);
	}
}

sub check_env()
{
	for my $k (keys %valueranges) {
		next unless exists $ENV{$k};
		unless (grep { $ENV{$k} eq $_ } @{$valueranges{$k}} ) {
			die sprintf("%s must be one of %s\n", $k, join(',', @{$valueranges{$k}}));
		}
	}
}

sub unregister_needle_tags($) {
	my $tag = shift;
	my @a = @{needle::tags($tag)};
	for my $n (@a) { $n->unregister(); }
}

sub remove_desktop_needles($)
{
	my $desktop = shift;
        if (!checkEnv("DESKTOP", $desktop)) {
		unregister_needle_tags("ENV-DESKTOP-$desktop");
        }
}

sub cleanup_needles()
{
	remove_desktop_needles("lxde");
	remove_desktop_needles("kde");
	remove_desktop_needles("gnome");
	remove_desktop_needles("xfce");
	remove_desktop_needles("minimalx");
	remove_desktop_needles("textmode");

	if (!$ENV{LIVECD}) {
		unregister_needle_tags("ENV-LIVECD-1");
	} else {
		unregister_needle_tags("ENV-LIVECD-0");
	}
	if (!checkEnv("VIDEOMODE", "text")) {
		unregister_needle_tags("ENV-VIDEOMODE-text");
	}

}

sub run()
{
	my $iso=$ENV{ISO};
	my $ison=$iso; $ison=~s{.*/}{}; # drop path
	if($ison=~m/Live/i) {$ENV{LIVECD}=1}
	if($ison=~m/Promo/) {$ENV{PROMO}=1}
	if($ison=~m/-i[3-6]86-/) {$ENV{QEMUCPU}||="qemu32"}
	if($ison=~m/openSUSE-.*-(DVD|NET|KDE|GNOME|LXDE|XFCE)-/) {
		$ENV{$1}=1; $ENV{NETBOOT}=$ENV{NET};
		if($ENV{LIVECD}) {
			$ENV{DESKTOP}=lc($1);
		}
	}
	check_env();
	setrandomenv if($ENV{RANDOMENV} && $0!~m/checklog/);
	unless ($ENV{DESKTOP}) {
		if (checkEnv("VIDEOMODE", "text")) {
			$ENV{DESKTOP}="textmode";
		} else {
			$ENV{DESKTOP}="kde";
		}
	}
	if (checkEnv('DESKTOP', 'minimalx')) {
		$ENV{'NOAUTOLOGIN'} = 1;
	}
	cleanup_needles();
	$ENV{SCREENSHOTINTERVAL}||=.5;
	autotest::runtestdir("$scriptdir/consoletest.d", undef);
	autotest::runtestdir("$scriptdir/x11test.d", undef);
	# dump other important ENV:
	logcurrentenv(qw"ADDONURL BIGTEST BTRFS DESKTOP HW HWSLOT LIVETEST LVM MOZILLATEST NOINSTALL REBOOTAFTERINSTALL UPGRADE USBBOOT TUMBLEWEED WDUP ZDUP ZDUPREPOS TEXTMODE DISTRI NOAUTOLOGIN");
}

1;
