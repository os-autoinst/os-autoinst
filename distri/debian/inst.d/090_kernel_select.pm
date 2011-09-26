use base "basetest";
use strict;
use bmwqemu;

sub run()
{
	my $self=shift;
	{
		local $ENV{SCREENSHOTINTERVAL}=5;
		waitstillimage(12, 600);
	}
	$self->take_screenshot; sleep 2;
	sendkey "ret"; # select default kernel
	sleep 1;
}

1;
