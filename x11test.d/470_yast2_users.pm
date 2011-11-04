use base "basetest";
use bmwqemu;

sub run()
{
	my $self=shift;
	x11_start_program("xdg-su -c '/sbin/yast2 users'");
	if($password) { sendpassword; sendkeyw "ret"; }
	$self->take_screenshot;
	sendkey "alt-o"; # OK => Exit
}

1;
