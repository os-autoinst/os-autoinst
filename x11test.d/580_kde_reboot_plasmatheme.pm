use base "basetest";
use bmwqemu;
# test for https://bugzilla.novell.com/show_bug.cgi?id=613824

sub is_applicable()
{
	return $ENV{DESKTOP} eq "kde" && !$ENV{LIVETEST};
}

sub run()
{
	my $self=shift;
	waitinststage "KDE", 20; # wait until reboot is finished
}

1;
