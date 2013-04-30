use base "basetest";
use bmwqemu;

sub is_applicable()
{
	return !$ENV{LIVETEST} || $ENV{USBBOOT};
}

sub run()
{
	my $self=shift;
	waitforneedle( "bootloader", 30); # wait until reboot
}

1;
