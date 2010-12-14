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
		4671f9678b18c1e3aaed4ca276b754ef OK
		9568dfaee345caa1e744015d6ef1e5d6 OK
		defdea5ace1615733f32f4638a4ddc3d OK
		2cb178ffd11052176e91bed06f40feab OK
		35ea6afbdf32009b77a6e3871b751e1d OK
	)}
}

1;
