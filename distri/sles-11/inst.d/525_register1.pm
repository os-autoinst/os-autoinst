use base "installstep";
use strict;
use bmwqemu;

sub run()
{ my $self=shift;
        sendkey "alt-n";
        sleep 29; waitidle; # test internet con
	$self->take_screenshot;
        sendkeyw "alt-o"; # continue after server-side error
#        sendkey "alt-n";
#        sleep 9; waitidle;
        # success
	$self->take_screenshot;
        sendkeyw "alt-n";
}

1;
