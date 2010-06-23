use base "basetest";
use bmwqemu;

sub is_applicable()
{
	return $ENV{DESKTOP} eq "kde";
}

sub run()
{
	my $self=shift;
	x11_start_program("kontact");
	sleep 10; waitidle 100; sleep 10; # pim needs extra time for first init
	$self->take_screenshot;
	sendkey "alt-f4"; sleep 10; # close popup (tips on startup)
	$self->take_screenshot;
	sendkey "alt-f4";

}

sub checklist()
{
	# return hashref:
	return {qw(
		0791f673be71d1ce43788135fc6aa0f7 OK
		5bf3bbb9c13f6297856702935f910735 OK
	)}
}

1;
