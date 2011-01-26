use base "basetest";
use bmwqemu;

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
