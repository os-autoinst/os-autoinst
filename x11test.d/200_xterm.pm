use base "basetest";
use bmwqemu;

sub is_applicable
{
	return !$ENV{NICEVIDEO};
}

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
		d3228b99ff8c54127cd8d2aa9c8f95f6 OK
		93f94f5ea3b73b2e442a30c03d2e8be9 OK
	)}
}

1;
