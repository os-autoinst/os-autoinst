use base "basetest";
use strict;
use bmwqemu;

sub run()
{
	my $self=shift;
	waitidle;
	if(waitimage("fedora_secondstage_date_and_time*",1,'')) {
		$self->take_screenshot;
		sendkey "alt-f"; # forward "Date and Time"
	}
}

1;
