use base "basetest";
use bmwqemu;

sub is_applicable()
{
	return !$ENV{LIVETEST};
}

sub run()
{
	my $self=shift;
	waitinststage "booted", 150; # wait until booted again
	mousemove_raw(30000, 30000); # move mouse off screen again
}

sub checklist()
{
	# return hashref:
	return {qw(
	)}
}

1;
