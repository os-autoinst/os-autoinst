use base "basetest";
use bmwqemu;

sub run()
{
	my $self=shift;
	x11_start_program("xterm");
	$self->take_screenshot;
	sendkey "alt-f4"; sleep 2;
}

sub checklist()
{
	# return hashref:
	return {qw(
	)}
}

1;
