use base "basetest";
use bmwqemu;

sub is_applicable
{
	return $ENV{BIGTEST} && !$ENV{NICEVIDEO};
}

sub run()
{
	my $self=shift;
	x11_start_program("glxgears");
	$self->take_screenshot;
	sendkey "q";
	sleep 5; # time to close
}

sub checklist()
{
	# return hashref:
	return {qw(
	)}
}

1;
