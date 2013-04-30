use base "basenoupdate";
use strict;
use bmwqemu;

sub run()
{ my $self=shift;
        # Users / User Auth Method
        sendkeyw "alt-n";
        sleep 2;
        waitidle;
        sendautotype "$realname\t\t";
        sendautotype "$password\t";
        sendautotype $password;
        #sendkey "alt-a"; # automatic login
	$self->take_screenshot;
        sendkeyw "alt-n";
        sleep 1;
        sendkeyw "alt-y"; # confirm weak PW
}

1;
