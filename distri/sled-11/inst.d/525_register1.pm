use base "basetest";
use strict;
use bmwqemu;

sub is_applicable()
{
	return $ENV{UPGRADE};
}

sub run()
{ my $self=shift;
        sendkey "alt-n";
        sleep 9; waitidle; # test internet con
	$self->take_screenshot;
        sendkeyw "alt-o"; # continue after server-side error
        # success
	$self->take_screenshot;
        sendkeyw "alt-n";
}

1;
