use strict;
use base "basetest";
use bmwqemu;

sub is_applicable
{
	return !$ENV{NICEVIDEO};
}

sub run()
{
	my $self=shift;
	sleep 10; # time to load kernel+initrd
	$self->take_screenshot;
	sleep 1;
	sendkey "esc";
}

1;
