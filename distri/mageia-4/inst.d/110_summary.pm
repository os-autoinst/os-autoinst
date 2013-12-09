use base "installstep";
use strict;
use bmwqemu;

sub run()
{
        mouse_set(10,10);
        mouse_hide(1);
        sleep 1;
	waitidle(60);
#	waitstillimage(60,290);
	mouse_hide();
#	waitgoodimage(300);
	if ($ENV{DESKTOP}=~/none/) {
	waitinststage('mageia4-summary-nographics',3000);
	} else {
	waitinststage('mageia4-summary',3000);
	}

        sendkey "shift-tab"; # skip media check
	sendkey "ret";


}

1;
