use base "basetest";
use bmwqemu;
# test for bug https://bugzilla.novell.com/show_bug.cgi?id=598574
sub run()
{
	my $self=shift;
	script_run('curl www3.zq1.de/test.txt');
	sleep 2;
	$self->take_screenshot;
	script_run('pacman -Q curl');
	sleep 2;
}

1;
