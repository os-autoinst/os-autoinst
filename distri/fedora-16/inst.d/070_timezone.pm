use base "basetest";
use strict;
use bmwqemu;

sub run()
{
	my $self=shift;
	waitidle;
	$self->take_screenshot; sleep 2;
	sendkey "alt-n"; # timezone
}

1;
