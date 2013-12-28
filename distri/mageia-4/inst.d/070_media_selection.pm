use base "installstep";
use strict;
use bmwqemu;

sub run()
{
        mouse_set(10,10);
        mouse_hide(1);
        sleep 1;

 	waitidle(10);
	waitstillimage(20,800);
	# Asking for
	# 2 tabs, return.  Leave all default
	# highlight media list (none selected)
        sendkey "tab"; # highlight help 
        sendkey "tab"; # highlight next button
	sendkey "ret"; # push next button
	waitstillimage(25,200);

	# Asking to enable more media (Core, Nonfree release)
	# 3 tabs, return.  Leave all default
	# Core selected already
        sendkey "tab"; # nonfree 
        sendkey "tab"; # help    
        sendkey "tab"; # next    
	sendkey "ret";  

}

1;
