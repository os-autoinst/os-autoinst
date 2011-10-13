use base "basetest";
use bmwqemu;

sub run()
{
	my $self=shift;
	x11_start_program("/sbin/yast2 users");
	#xdg-su -c "/sbin/yast2 users"
	$self->take_screenshot;
	sendkeyw "alt-o"; # OK => Exit
}

1;
