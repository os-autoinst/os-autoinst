use base "basetest";
use strict;
use bmwqemu;

sub run()
{
	my $self=shift;
	sleep 10;
	waitidle;
	sendkey "ret"; # lang
	waitidle;
	$self->take_screenshot; sleep 2;
	sendkey "ret"; # keyboard
}

1;
