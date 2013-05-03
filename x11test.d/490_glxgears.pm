use base "basetest";
use bmwqemu;

sub is_applicable
{
	return $ENV{BIGTEST} && !$ENV{NICEVIDEO};
}

sub run()
{
	my $self=shift;
	ensure_installed("Mesa-demo-x");
	x11_start_program("glxgears");
	$self->check_screen;
	sendkeyw "alt-f4";
	sendkey "ret";
	sleep 5; # time to close
}

1;
