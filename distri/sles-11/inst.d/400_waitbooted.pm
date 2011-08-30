use base "basetest";
use strict;
use bmwqemu;

sub run()
{ my $self=shift;
	waitinststage("config-rootpw|networktest",190);
	waitidle(60); # especially for upgrade case
        mousemove_raw(31000, 31000); # move mouse off screen again
}

1;
