use base "basetest";
use strict;
use bmwqemu;

sub run()
{
	my $self=shift;
	waitinststage("debian-popconconf", 140);
	$self->take_screenshot; sleep 1;
	sendkey "ret"; # no popcon
	sleep 5; waitidle;
}
sub checklist()
{
	return {qw(
		ba98a8f00feeea27a8eb3340a6635a03 OK
	)}
}


1;
