use base "basetest";
use strict;
use bmwqemu;

sub run()
{
	my $self=shift;
	waitinststage("splashscreen",90);
	$self->take_screenshot;
	sleep 2;
	sendkey "esc";
	sleep 15;
	waitidle;
}

#sub checklist()
#{
#}

1;
