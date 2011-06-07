use strict;
use base "basenoupdate";
use bmwqemu;

sub run()
{
	my $self=shift;
	sendkey "ret"; # boot from HDD (in DVD isolinux)
	$self->take_screenshot;
	sleep 3;
}

1;
