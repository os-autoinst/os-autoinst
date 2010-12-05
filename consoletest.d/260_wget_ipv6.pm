use base "basetest";
use bmwqemu;
# test for equivalent of bug https://bugzilla.novell.com/show_bug.cgi?id=598574
sub run()
{
	my $self=shift;
	script_run('wget -O- -q www3.zq1.de/test.txt');
	sleep 2;
	$self->take_screenshot;
	script_run('rpm -q wget');
	sleep 2;
}

sub checklist()
{
	# return hashref:
	return {qw(
		c9b4091649ce76874d9b77b41fe85f67 OK
	)}
}

1;
