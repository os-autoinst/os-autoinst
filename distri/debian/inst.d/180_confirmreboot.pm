use base "basetest";
use strict;
use bmwqemu;

sub run()
{
	my $self=shift;
	waitidle(100);
	waitstillimage;
	$self->take_screenshot; sleep 1;
	sendkey "ret"; # confirm reboot
}

1;
