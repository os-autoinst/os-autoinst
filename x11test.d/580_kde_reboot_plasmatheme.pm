use base "basetest";
use bmwqemu;
# test for https://bugzilla.novell.com/show_bug.cgi?id=613824

sub is_applicable()
{
	return $ENV{DESKTOP} eq "kde";
}

sub run()
{
	my $self=shift;
	waitinststage "KDE", 200; # wait until reboot is finished
	waitidle 100;
}

sub checklist()
{
	# return hashref:
	return {qw(
		6d18b2d816f80e55fdc6ce1a06a908be fail
		866a30651084f519426acdb539574ed9 OK
	)}
}

1;
