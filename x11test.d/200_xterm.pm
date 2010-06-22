use base "basetest";
use bmwqemu;

sub run()
{
	my $self=shift;
	x11_start_program("xterm");
	sleep 2;
	$self->take_screenshot;
	sendkey "alt-f4"; sleep 2;
}

sub checklist()
{
	# return hashref:
	return {qw(
		89eb3584933cacec266886cf5bc4094c OK
	)}
}

1;
