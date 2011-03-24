use base "basetest";
use strict;
use bmwqemu;

sub sendkeyw($) {sendkey(shift); waitidle;}

sub run()
{ my $self=shift;
	# timezone
	$self->take_screenshot;
	sendkeyw("alt-n");
	# summary/confirm
	$self->take_screenshot;
	sendkeyw("alt-a"); # accept
	$self->take_screenshot;
	sendkeyw("alt-a"); # agree agfa license
	sendkeyw("alt-i"); # install
	$self->take_screenshot;
	# perform installation
	# long wait
	local $ENV{SCREENSHOTINTERVAL}=5; # speedup video
	waitinststage("booted", 3600); # will timeout on standstill
}

1;
