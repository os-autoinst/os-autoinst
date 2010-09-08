use base "basetest";
use bmwqemu;

sub is_applicable()
{
	return $ENV{DESKTOP}=~/kde|gnome/;
}

sub run()
{
	my $self=shift;
	x11_start_program("oowriter");
	sleep 2; waitidle; # extra wait because oo sometimes appears to be idle during start
	$self->take_screenshot;
	sendkey "alt-f4"; sleep 2;
}

sub checklist()
{
	# return hashref:
	return {qw(
		a5fbe661f892c38c5069bf3430cac25b OK
		190acc3807f1f613aae461f805473e02 OK
		6bec2316aa83ea457da19f15bba8752a OK
	)}
}

1;
