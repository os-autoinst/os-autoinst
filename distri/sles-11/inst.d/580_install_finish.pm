use base "basetest";
use strict;
use bmwqemu;

sub run()
{ my $self=shift;
        # Completed
        sendkey "alt-f"; # finish
        sleep 20;
        waitidle(120);
        # done booting first time here
}

1;
