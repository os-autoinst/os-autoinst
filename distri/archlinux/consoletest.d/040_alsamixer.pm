use base "basetest";
use bmwqemu;
use Time::HiRes qw(sleep);


sub run()
{ my $self=shift;
	sendautotype "alsamixer\n";
	waitidle;
	sendkey "m";
	for(1..11) {
		sendkey "pgup";
		sleep 0.2;
	}
	sleep 1;
	for(1..4) {
		sendkey "right";
		sleep 0.2;
	}
	sleep 1;
	sendkey "m";
	for(1..13) {
		sendkey "pgup";
		sleep 0.2;
	}
	$self->take_screenshot;
	sleep 1;
	sendkey "esc";
}

1;
