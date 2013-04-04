use base "basetest";
use bmwqemu;

sub is_applicable()
{
	return !$ENV{LIVETEST} || $ENV{USBBOOT};
}

sub run()
{
	my $self=shift;
	waitinststage "booted", 150; # wait until booted again
	mouse_hide(1);
}

1;
