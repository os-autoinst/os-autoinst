use base "installstep";
use strict;
use bmwqemu;

sub run()
{
	waitidle(20);
	waitstillimage(20,250);

if($ENV{DESKTOP}=~/kde/) {
	# KDE
        sendkey "tab"; # skip media check
        sendkey "tab"; # skip media check
        sendkey "tab"; # skip media check
	sleep 10;
	sendkey "ret";
}
elsif($ENV{DESKTOP}=~/gnome/) {
	# KDE
        sendkey "tab"; # skip media check
	sendkey "right";
	sleep 2;
	sendkey "tab";
	sleep 10;
	sendkey "tab";
	sleep 10;
	sendkey "ret";

} else {
# Custom

#selecting kde, gnome, or custom.  This does not show up in all cases.  Maybe due to small root fs
# TODO. detect if this screen is here or not
	waitstillimage(35,250);
        if (waitinststage("mageia-pick-desktop", 10)) {
         	sendkey "tab";
         	sleep 2;
         	sendkey "right";
         	sleep 2;
         	sendkey "right";
         	sleep 2;
         	sendkey "tab";
         	sleep 10;
         	sendkey "tab";
         	sleep 10;
         	sendkey "ret";
         	waitstillimage(15,150);
        }

        waitinststage("mageia-custom-packages",300);
	# Unselect all
	sendkey "tab";
	sleep 1;
	sendkey "shift-tab";
	sleep 1;
	sendkey "shift-tab";
	sleep 2;
	sendkey "ret";
	sleep 2;
	sendkey "tab";
	sleep 2;
	sendkey "ret";

# minial	
	waitidle(10);
	waitstillimage(10,250);
	sleep 2;
	sendkey "ret";

}

}

1;
