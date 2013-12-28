use base "installstep";
use strict;
use bmwqemu;

sub run()
{
	waitidle(20);
	waitstillimage(20,250);
#	$self->take_screenshot;
	if (waitinststage("mageia4-pick-desktop", 10)) {
		if($ENV{DESKTOP}=~/kde/) {
			# KDE
			sendkey "tab"; # skip media check
			sendkey "tab"; # skip media check
			sendkey "tab"; # skip media check
			sleep 10;
			sendkey "ret";
		}
		if($ENV{DESKTOP}=~/gnome/) {
			# KDE
			sendkey "tab"; # skip media check
			sendkey "right";
			sleep 2;
			sendkey "tab";
			sleep 10;
			sendkey "tab";
			sleep 10;
			sendkey "ret";

		}
		# Custom
		if($ENV{DESKTOP}=~/none/) {
		#selecting kde, gnome, or custom.  This does not show up in all cases.  Maybe due to small root fs
		# TODO. detect if this screen is here or not
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
	} 
	elsif(waitinststage("mageia4-custom-packages",6) || waitinststage("mageia4-custom-packages1",6) || waitinststage("mageia4-custom-packages2",6)) {
		print "Small partition size, so desktop prompt skipped";
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
	} else {
		print "Sorry, can't proceed, no expected screen found";
		die('no valid input found');
	};

	if (waitinststage("mageia4-custom-packages",10)) {
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
