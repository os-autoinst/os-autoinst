use base "installstep";
use strict;
use bmwqemu;

sub run()
{
	waitidle(300);
	waitstillimage(10,150);

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
	sendkey "tab";
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

	sleep 500;
#  THIS FAILS in RC3 right now.
# Unselect all
	sleep 2;
	sendkey "shift-tab";
	sendkey "shift-tab";
	sleep 2;
	sendkey "ret";
	sleep 2;
	sendkey "tab";
	sleep 2;
	sendkey "ret";

# minial	
	waitstillimage(10,150);
	sleep 2;
	sendkey "ret";

}

}

1;
