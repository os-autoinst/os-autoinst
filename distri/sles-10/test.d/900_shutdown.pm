use base "basetest";
use strict;
use bmwqemu;

sub run()
{ my $self=shift;
	$self->take_screenshot;
        x11_start_program("xterm");
	$self->take_screenshot;
        script_sudo("/sbin/halt");
}

1;
