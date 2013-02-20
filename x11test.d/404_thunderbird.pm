use base "basetest";
use bmwqemu;

sub is_applicable()
{
	return $ENV{DESKTOP} eq "gnome" && !$ENV{LIVECD};
}

sub run()
{
	my $self=shift;
	x11_start_program("thunderbird");
	$self->take_screenshot;
	sendkeyw "alt-f4";	# close wizzard
	sendkeyw "alt-f4";	# close prog
}

sub checklist()
{
	# return hashref:
	return {qw(
	)}
}

1;
