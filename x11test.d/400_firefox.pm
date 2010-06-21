use base "basetest";
use bmwqemu;

sub run()
{
	my $self=shift;
	x11_start_program("firefox");
	$self->take_screenshot;
	sendkey "alt-f4"; sleep 2;
	sendkey "ret"; # confirm "save&quit"
}

sub checklist()
{
	# return hashref:
	return {qw(
		4299006210d21ee52570d99916500f76 OK
	)}
}

1;
