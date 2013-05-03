use base "basetest";
use bmwqemu;

my @sites=qw(en.opensuse.org www.slashdot.com www.freshmeat.net www.microsoft.com www.yahoo.com www.ibm.com www.hp.com www.intel.com www.amd.com www.asus.com www.gigabyte.com fractal.webhop.net openqa.opensuse.org http://openqa.opensuse.org/images/openqaqr.png http://openqa.opensuse.org/opensuse/permanent/video/openSUSE-DVD-x86_64-Build0039-nice3.ogv http://openqa.opensuse.org/opensuse/qatests/ER3_020_cut.webm software.opensuse.org about:memory);

sub open_tab($)
{ my $addr=shift;
	sendkey "ctrl-t"; # new tab
	sleep 2;
	sendautotype($addr);
	sleep 2;
	sendkey "ret";
	sleep 6;
	sendkey "pgdn";
	sleep 1;
}

sub is_applicable
{
	return !$ENV{NICEVIDEO} && $ENV{BIGTEST};
}

sub run()
{
	my $self=shift;
	x11_start_program("firefox");
	$self->check_screen;
	foreach my $site (@sites) {
		open_tab($site);
		if($site=~m/openqa/) {$self->check_screen;}
	}
	$self->check_screen;
	sendkey "alt-f4"; sleep 2;
	sendkey "ret"; # confirm "save&quit"
	waitidle;

	# re-open to see how long it takes to open all tabs together
	x11_start_program("firefox");
	$self->check_screen;
	sendkey "alt-f4"; sleep 2;
	sendkey "ret"; # confirm "save&quit"
}

1;
