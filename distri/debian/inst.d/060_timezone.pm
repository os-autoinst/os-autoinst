use base "basetest";
use strict;
use bmwqemu;

sub run()
{
	my $self=shift;
	waitstillimage(15,60);
	#waitidle;
	$self->take_screenshot;sleep 1;
	sendkey "ret"; # timezone
}

1;
