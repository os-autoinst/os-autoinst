use base "basetest";
use strict;
use bmwqemu;

sub is_applicable()
{
	return $ENV{WDUP};
}

sub run()
{
	my $self=shift;

	# Party time
	script_sudo("/sbin/yast wagon");
	sendkeyw "alt-n";

	# Wait while installing packages from beta repo
	waitstillimage(30, 700);

	# Enable "Check auto repo changes" option
	sendkey "alt-e";
	sleep 2;
	sendkeyw "alt-n";
	# NCC next
	sendkeyw "alt-n";
	waitstillimage(12, 300);
	# NCC ok
	$self->take_screenshot;
	sendkeyw "alt-o";
	sleep 5;
	# PKG ok
	$self->take_screenshot;
	sendkeyw "alt-o";
	sleep 5;
	# select "Full - upgrade frm all repos"
	sendkeyw "alt-f";
	sendkeyw "alt-n";

	# Final Overview
	waitstillimage(10, 300);
	# Close that scary license dialog
	sendkeyw "alt-y";
	waitstillimage(6, 100);
	$self->take_screenshot;
	if (waitimage('wdup_wagon-depfail', 10)) {
		sendkey $cmd{change};	# Change
		#waitserial('continue', 3600);
		sendkey "alt-p";
		#sendkey $cmd{software};	# Software
		#alarm 1;
		my $n=10;
		do {
			sendkey "tab";
			sendkey "down";
			sendkey "spc";
			sendkeyw "alt-o";
			alarm 1 unless($n--);
		} while (!waitimage('wdup_wagon-depresdone', 10));
		sendkeyw "alt-a";
		sendkeyw "alt-o";

	}
	sendkeyw "alt-n";
	# Start Update
	sendkeyw "alt-u";

	local $ENV{SCREENSHOTINTERVAL}=2;
	for(1..12) {
		sleep 60;
		sendkey "shift"; # prevent console screensaver
	}
	for(1..12) {
		waitstillimage(60,66) || sendkey "shift"; # prevent console screensaver
	}
	waitstillimage(160, 5000); # wait for upgrade to finish
	sendkey "shift"; # prevent console screensaver
	waitidle(400);
	$self->take_screenshot;
	sendkeyw "alt-o"; # reboot for new kernel ok
	sleep 4;
	$self->take_screenshot;
	sendkeyw "alt-n"; # ncc next
	sleep 4;
	$self->take_screenshot;
	sendkeyw "alt-o"; # ncc ok
	sleep 4;
	$self->take_screenshot;
	sendkeyw "alt-f"; # finish
}

1;
