use base "basetest";
use strict;
use bmwqemu;

sub run()
{
	my $self=shift;
	# speed up main install video
	local $ENV{SCREENSHOTINTERVAL}=5;
	waitstillimage(20,3600);
	$self->take_screenshot; sleep 2;
	sendkey "ret"; # default workgroup
}

1;
