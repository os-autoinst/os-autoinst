use base "basetest";
use bmwqemu;

sub is_applicable()
{
	return $ENV{DESKTOP} eq "gnome";
}

sub run()
{
	my $self=shift;
	x11_start_program("application-browser");
	$self->take_screenshot;
	sendkey "alt-f4"; 
	waitidle;
}

sub checklist()
{
	# return hashref:
	return {qw(
	)}
}

1;
