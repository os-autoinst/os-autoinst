use strict;
use base "basetest";
use bmwqemu;

sub run()
{
	my $self=shift;
	waitinststage "performinstallation";
	local $ENV{SCREENSHOTINTERVAL}=5; # fast-forward
	$self->take_screenshot;
	waitinststage("bootloader|splashscreen|booted", 9000)==2 && sendkey "alt-d"; # details in case of error
}

1;
