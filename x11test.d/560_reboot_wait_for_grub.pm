use base "basetest";
use bmwqemu;

sub run()
{
	my $self=shift;
	waitinststage "grub", 60; # wait until reboot
}

sub checklist()
{
	# return hashref:
	return {qw(
		6dad21ea36802fca6a7b4dc14db62c0e OK
	)}
}

1;
