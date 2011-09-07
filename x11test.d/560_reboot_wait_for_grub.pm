use base "basetest";
use bmwqemu;

sub is_applicable()
{
	return !$ENV{LIVETEST} || $ENV{USBBOOT};
}

sub run()
{
	my $self=shift;
	waitinststage "bootloader", 30; # wait until reboot
}

sub checklist()
{
	# return hashref:
	return {qw(
		6dad21ea36802fca6a7b4dc14db62c0e OK
		5fa9163c004cc7b82cf16d06a810d270 OK
	)}
}

1;
