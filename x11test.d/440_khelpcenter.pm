use base "basetest";
use bmwqemu;

sub is_applicable()
{
	return $ENV{DESKTOP} eq "kde";
}

sub run()
{
	my $self=shift;
	x11_start_program("khelpcenter");
	$self->take_screenshot;
	sendkey "alt-f4"; sleep 2;
}

sub checklist()
{
	# return hashref:
	return {qw(
		7a92ffcf15a7928d2510af0b55e48132 OK
		d6fb5e87f3c4e691c2ddda32819d4504 OK
		de10526990420374dc96720f9e2e3087 OK
		4d732245dd555b3484bfc52cd59ca0ee OK
	)}
}

1;
