use base "basetest";
use bmwqemu;

sub run()
{
	my $self=shift;
	x11_start_program("oowriter");
	$self->take_screenshot;
	sendkey "alt-f4"; sleep 2;
}

sub checklist()
{
	# return hashref:
	return {qw(
		49724acd3f6f83b58ff8b901099d15eb OK
	)}
}

1;
