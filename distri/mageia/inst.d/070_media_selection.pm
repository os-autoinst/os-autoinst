use base "installstep";
use strict;
use bmwqemu;

sub run()
{
	waitstillimage(30,200);
	# Asking for
	# 2 tabs, return.  Leave all default
	# highlight media list (none selected)
        sendkey "tab"; # highlight help 
        sendkey "tab"; # highlight next button
	sendkey "ret"; # push next button
	waitstillimage(10,20);

	# Asking to enable more media (Core, Nonfree release)
	# 3 tabs, return.  Leave all default
	# Core selected already
        sendkey "tab"; # nonfree 
        sendkey "tab"; # help    
        sendkey "tab"; # next    
	sendkey "ret";  

}

1;
