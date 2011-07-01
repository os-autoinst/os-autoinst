use strict;
use base "basenoupdate";
use bmwqemu;

sub run()
{
	my $self=shift;
	waitinststage "performinstallation";
	local $ENV{SCREENSHOTINTERVAL}=5; # fast-forward
	$self->take_screenshot;
	waitinststage "^[^p][^e][^r][^f]", 5000;
}

1;
