use base "installstep";
use strict;
use bmwqemu;

sub run()
{
	waitidle(60);
#	waitstillimage(60,290);
	mouse_hide();
#	waitgoodimage(300);
	waitinststage('mageia-summary',300);

        sendkey "shift-tab"; # skip media check
	sendkey "ret";


}

1;
