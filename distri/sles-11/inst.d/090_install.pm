use strict;
use base "installstep";
use bmwqemu;

sub is_applicable()
{
	my $self=shift;
        return $self->SUPER::is_applicable || $ENV{AUTOYAST};
}

sub run()
{
	my $self=shift;
	waitinststage "performinstallation";
	local $ENV{SCREENSHOTINTERVAL}=5; # fast-forward
	$self->take_screenshot;
	if($ENV{HW}) {
		waitimage("waitbooted-*", 9000, 'd');
	}
	else {
		waitinststage("bootloader|splashscreen|booted|rootuser", 9000)==2 && sendkey "alt-d"; # details in case of error
	}
}

1;
