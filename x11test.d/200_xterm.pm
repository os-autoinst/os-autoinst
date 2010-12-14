use base "basetest";
use bmwqemu;

sub is_applicable
{
	return !$ENV{NICEVIDEO};
}

sub run()
{
	my $self=shift;
	mousemove_raw(31000, 31000); # move mouse off screen again
	x11_start_program("xterm");
	sleep 2;
	for(1..13) { sendkey "ret" }
	sendautotype("echo If you can see this text xterm is working.\n");
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
		5714694cf15ca5caf5723de391cb2a6b OK
		f275ea7aca207e429e54403e0982d295 OK
		97d2682c8a1184cdf24baf4e4e624e67 OK
		864746b577a070d4da4385aa27c51e34 OK
	)}
}

1;
