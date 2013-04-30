use strict;
use base "autoinstallstep";
use bmwqemu;

sub run()
{
	my $self=shift;
	waitinststage "performinstallation";
	local $ENV{SCREENSHOTINTERVAL}=5; # fast-forward
	$self->take_screenshot;
	if($ENV{HW}) {
	    waitimage("waitbooted", 9000, 'd');
	}
	else {
	    waitinststage("bootloader-loadkernel", 9000)==2 && sendkey "alt-d"; # details in case of error
	}
}

1;
