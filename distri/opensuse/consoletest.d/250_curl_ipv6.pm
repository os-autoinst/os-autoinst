use base "basetest";
use bmwqemu;
# test for bug https://bugzilla.novell.com/show_bug.cgi?id=598574
sub is_applicable()
{
	return ($ENV{BIGTEST});
}

sub run()
{
	my $self=shift;
	script_run('curl www3.zq1.de/test.txt');
	sleep 2;
	$self->check_screen;
	script_run('rpm -q curl libcurl4');
	sleep 2;
}

1;
