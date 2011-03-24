use base "basetest";
use strict;
use bmwqemu;

sub sendkeyw($) {sendkey(shift); waitidle;}

sub run()
{ my $self=shift;
        # Users / User Auth Method
        sendkeyw "alt-n";
        sendautotype $realname;
        sendkey "alt-s"; # Suggest user name
        for(1..3) {sendkey "tab";}
        sendautotype "$password\t";
        sendautotype $password;
        sendkey "alt-a"; # automatic login
	$self->take_screenshot;
        sendkeyw "alt-n";
}

1;
