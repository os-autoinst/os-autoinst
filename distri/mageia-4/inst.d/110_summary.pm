use base "installstep";
use strict;
use bmwqemu;

sub run()
{
        mouse_set(10,10);
        mouse_hide(1);
        sleep 1;
	waitidle(600);
	waitstillimage(60,600);
	mouse_hide();
#	waitgoodimage(300);
	if ($ENV{DESKTOP}=~/none/) {
		waitinststage('mageia4-summary-nographics',10);
	} else {
		unless (waitinststage('mageia4-summary',10) || waitinststage('mageia4-summary1',10)) {
			print "Summary page not found, installer must have changed";
			die ("No summary found");
		}
	}

        sendkey "shift-tab"; # 
	sendkey "ret";


}

1;
