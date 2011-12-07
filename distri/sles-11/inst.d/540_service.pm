use base "basenoupdate";
use strict;
use bmwqemu;

sub run()
{ my $self=shift;
        # Service
	$self->take_screenshot;
        sendkeyw "alt-n";
	if($ENV{ADDONURL}=~m/POS/) {
        	sendkey "alt-a"; # Admin-Server
		sleep 5;
        	sendkey "alt-c"; # Branch-Server
        	sendkey "alt-i"; # Image-Server
		sleep 5;
        	sendkey "alt-n";
		waitidle(200);
		waitstillimage(12,200);
	}
}

1;
