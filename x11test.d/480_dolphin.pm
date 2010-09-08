use base "basetest";
use bmwqemu;

sub is_applicable()
{
	return $ENV{DESKTOP} eq "kde";
}

sub run()
{
	my $self=shift;
	x11_start_program("dolphin");
	$self->take_screenshot;
	sendkey "alt-f4"; sleep 2;
}

sub checklist()
{
	# return hashref:
	return {qw(
		fb0591d0a2b7abde1f20f7f3e1f05389 OK
		75264048ecf8d5bf807270a4d52bf2a8 OK
		79107c3fca63d4798f1d24709d005231 OK
	)}
}

1;
