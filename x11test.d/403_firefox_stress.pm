use base "basetest";
use bmwqemu;

my @sites=qw(en.opensuse.org www.slashdot.com www.freshmeat.net www.microsoft.com www.yahoo.com www.ibm.com www.hp.com www.intel.com www.amd.com www.asus.com www.gigabyte.com software.opensuse.org);

sub open_tab($)
{ my $addr=shift;
	sendkey "ctrl-t"; # new tab
	sleep 2;
	sendautotype($addr);
	sleep 2;
	sendkey "ret";
	sleep 6;
}

sub is_applicable
{
	return !$ENV{NICEVIDEO};
}

sub run()
{
	my $self=shift;
	x11_start_program("firefox");
	$self->take_screenshot;
	foreach my $site (@sites) {
		open_tab($site);
	}
	$self->take_screenshot;
	sendkey "alt-f4"; sleep 2;
	sendkey "ret"; # confirm "save&quit"
	waitidle;

	# re-open to see how long it takes to open all tabs together
	x11_start_program("firefox");
	$self->take_screenshot;
	sendkey "alt-f4"; sleep 2;
	sendkey "ret"; # confirm "save&quit"
}

sub checklist()
{
	# return hashref:
	# firefox disabled icons (back, forw, stop) differ by one bit between 32/64 arch
	return {qw(
	)}
}

1;
