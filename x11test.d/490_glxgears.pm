use base "basetest";
use bmwqemu;

sub is_applicable
{
	return !$ENV{NICEVIDEO};
}

sub run()
{
	my $self=shift;
	x11_start_program("glxgears");
	$self->take_screenshot;
	sendkey "q";
	sleep 1; # time to close
}

sub checklist()
{
	# return hashref:
	return {qw(
	)}
}

1;
