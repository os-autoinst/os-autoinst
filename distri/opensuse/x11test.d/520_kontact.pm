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
	$self->check_screen;
	sendkey "alt-f4"; sleep 10; # close popup Account assistant
	sendkey "alt-f4"; sleep 10; # close popup (tips on startup)
	$self->check_screen;
	sendkey "alt-f4";

}

1;
